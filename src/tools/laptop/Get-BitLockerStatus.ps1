function Get-BitLockerStatus {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'bitlocker-status'

        # --- Report phase (always runs, read-only) ---
        $volumes = @(Get-BitLockerVolume -ErrorAction SilentlyContinue)

        if ($volumes.Count -eq 0) {
            Write-ToolOutput 'BitLocker not present or not enabled on any volume.' -Level Warning
        } else {
            Write-ToolOutput 'BitLocker Volume Status:' -Level Info
            foreach ($vol in $volumes) {
                Write-ToolOutput ('  Drive: {0}  Status: {1}  Protection: {2}  Encryption: {3}%  Method: {4}' -f
                    $vol.MountPoint, $vol.VolumeStatus, $vol.ProtectionStatus,
                    $vol.EncryptionPercentage, $vol.EncryptionMethod) -Level Info
                if ($vol.KeyProtector) {
                    foreach ($kp in $vol.KeyProtector) {
                        # NEVER display the 48-digit RecoveryPassword -- show type and ID only
                        Write-ToolOutput ('    KeyProtector: Type={0}  Id={1}' -f
                            $kp.KeyProtectorType, $kp.KeyProtectorId) -Level Detail
                    }
                }
            }
        }

        # --- Action menu (REPORT-THEN-ACTION) ---
        # BackupToAAD is the safe, preferred backup; BackupToFile is hardened (warning+confirm+ACL+delete-prompt)
        $action = Read-ToolChoice `
            -Prompt 'BitLocker action' `
            -Choices @('None', 'BackupToAAD', 'BackupToFile', 'Suspend', 'Resume') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {

            'BackupToAAD' {
                # AAD/Intune escrow -- preferred backup; does NOT display or rotate the key
                if (-not (Get-Command BackupToAAD-BitLockerKeyProtector -ErrorAction SilentlyContinue)) {
                    Write-ToolOutput 'AAD backup cmdlet not available on this OS.' -Level Warning
                    Complete-ToolRun $run -Status Warning -Summary 'BackupToAAD: cmdlet not available on this OS'
                } else {
                    $aadSuccess = 0
                    $aadFail = 0
                    foreach ($vol in $volumes) {
                        $rpKeys = @($vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
                        foreach ($key in $rpKeys) {
                            try {
                                BackupToAAD-BitLockerKeyProtector -MountPoint $vol.MountPoint `
                                    -KeyProtectorId $key.KeyProtectorId -ErrorAction Stop
                                Write-ToolOutput ('  AAD backup succeeded: {0}  KeyId: {1}' -f
                                    $vol.MountPoint, $key.KeyProtectorId) -Level Success
                                $aadSuccess++
                            } catch {
                                Write-ToolOutput ('  AAD backup failed: {0}  KeyId: {1}  Error: {2}' -f
                                    $vol.MountPoint, $key.KeyProtectorId, $_.Exception.Message) -Level Error
                                $aadFail++
                            }
                        }
                    }
                    if ($aadFail -gt 0) {
                        Complete-ToolRun $run -Status Warning `
                            -Summary ('BackupToAAD: {0} succeeded, {1} failed' -f $aadSuccess, $aadFail)
                    } else {
                        Complete-ToolRun $run -Status Success `
                            -Summary ('BackupToAAD: {0} key(s) escrowed to AAD/Intune' -f $aadSuccess)
                    }
                }
            }

            'BackupToFile' {
                # Hardened: warning -> confirm (Default No) -> chosen folder -> write -> ACL-lock -> delete-prompt
                # Recovery key is written to file ONLY; never echoed to the console
                Write-ToolOutput 'WARNING: This writes the BitLocker RECOVERY KEY in PLAINTEXT to a file. Anyone with the file can unlock the drive. Store it securely and delete it when done.' -Level Warning
                $confirmFile = Read-ToolChoice `
                    -Prompt 'Write recovery key to a plaintext file?' `
                    -Choices @('Yes', 'No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($confirmFile -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'BackupToFile cancelled by user'
                } else {
                    # A bare Read-Host here throws in the GUI's hostless tool runspace (caught
                    # by the outer catch before any state change - fails closed, but the
                    # feature silently can't be used from the default UI mode). Read-ToolChoice
                    # only supports enumerated choices, not free text, so offer a fixed set of
                    # safe destinations instead of an arbitrary typed path.
                    $defaultFolder = [Environment]::GetFolderPath('MyDocuments')
                    $desktopFolder = [Environment]::GetFolderPath('Desktop')
                    $folderChoice = Read-ToolChoice `
                        -Prompt ('Save folder: Documents ({0}) or Desktop ({1})?' -f $defaultFolder, $desktopFolder) `
                        -Choices @('Documents', 'Desktop', 'Cancel') `
                        -Default 'Cancel' `
                        -Silent:$Silent
                    if ($folderChoice -eq 'Cancel') {
                        Complete-ToolRun $run -Status Skipped -Summary 'BackupToFile cancelled (no destination chosen)'
                        return
                    }
                    $saveFolder = if ($folderChoice -eq 'Desktop') { $desktopFolder } else { $defaultFolder }
                    if (-not (Test-Path $saveFolder -PathType Container)) {
                        Write-ToolOutput ('Folder not found: {0}' -f $saveFolder) -Level Warning
                        Complete-ToolRun $run -Status Warning `
                            -Summary ('BackupToFile aborted: folder not found: {0}' -f $saveFolder)
                    } else {
                        # Collect recovery passwords -- written to file only, NOT echoed to console
                        $keyLines = @()
                        foreach ($vol in $volumes) {
                            $rpKeys = @($vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
                            foreach ($key in $rpKeys) {
                                $keyLines += ('Drive {0}: {1}' -f $vol.MountPoint, $key.RecoveryPassword)
                            }
                        }
                        if ($keyLines.Count -eq 0) {
                            Write-ToolOutput 'No RecoveryPassword protectors found on any volume; no file written.' -Level Warning
                            Complete-ToolRun $run -Status Warning `
                                -Summary 'BackupToFile: no RecoveryPassword protectors found'
                        } else {
                            $keyFile = Join-Path $saveFolder ('BitLocker-Recovery-{0:yyyyMMdd-HHmmss}.txt' -f (Get-Date))

                            # Create the file empty and lock its ACL BEFORE any recovery key
                            # content is written - the plaintext key must never exist under
                            # inherited (broader) permissions, even briefly. Grant by the
                            # current user's SID rather than $env:USERNAME, which resolves to
                            # the machine account under SYSTEM and can collide with a
                            # same-named local account for a domain user.
                            New-Item -Path $keyFile -ItemType File -Force -ErrorAction Stop | Out-Null
                            $currentSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
                            & icacls "$keyFile" /inheritance:r /grant:r "*$($currentSid):F" | Out-Null
                            $icaclsExit = $LASTEXITCODE
                            if ($icaclsExit -ne 0) {
                                Remove-Item -Path $keyFile -Force -ErrorAction SilentlyContinue
                                Write-ToolOutput ('ACL-lock failed (exit {0}); refusing to write the recovery key file unprotected.' -f $icaclsExit) -Level Warning
                                Complete-ToolRun $run -Status Warning -Summary ('BackupToFile aborted: could not restrict file permissions before writing (icacls exit {0})' -f $icaclsExit)
                                return
                            }
                            Write-ToolOutput 'File ACL restricted to current user only.' -Level Success

                            Set-Content -Path $keyFile -Value $keyLines -Encoding UTF8
                            Write-ToolOutput ('Recovery key file written: {0}' -f $keyFile) -Level Success

                            # Offer immediate deletion (safe default: Yes)
                            $deleteChoice = Read-ToolChoice `
                                -Prompt 'Delete this key file now? (choose No only if you have moved it somewhere secure)' `
                                -Choices @('Yes', 'No') `
                                -Default 'Yes' `
                                -Silent:$Silent
                            if ($deleteChoice -eq 'Yes') {
                                Remove-Item $keyFile -Force -ErrorAction SilentlyContinue
                                Write-ToolOutput 'Recovery key file deleted.' -Level Success
                                $fileNote = 'created then deleted'
                            } else {
                                $fileNote = 'created and retained'
                            }
                            Complete-ToolRun $run -Status Success `
                                -Summary ('BackupToFile: key file {0} (ACL-locked)' -f $fileNote)
                        }
                    }
                }
            }

            'Suspend' {
                # Pre-firmware-update; suspends for 2 reboots (reversible)
                if ($volumes.Count -eq 0) {
                    Write-ToolOutput 'No BitLocker volumes found to suspend.' -Level Warning
                    Complete-ToolRun $run -Status Warning -Summary 'Suspend: no BitLocker volumes found'
                } else {
                    $driveList = @($volumes | ForEach-Object { $_.MountPoint }) + @('Cancel')
                    $driveDefault = 'C:'
                    if ($driveList -notcontains 'C:') { $driveDefault = $driveList[0] }
                    $drive = Read-ToolChoice `
                        -Prompt 'Select drive to suspend' `
                        -Choices $driveList `
                        -Default $driveDefault `
                        -Silent:$Silent
                    if ($drive -eq 'Cancel') {
                        Complete-ToolRun $run -Status Skipped -Summary 'Suspend cancelled by user'
                    } else {
                        Write-ToolOutput ('WARNING: BitLocker protection will be OFF on {0} until resumed or 2 reboots complete.' -f $drive) -Level Warning
                        $confirmSuspend = Read-ToolChoice `
                            -Prompt ('Suspend BitLocker on {0} for 2 reboots?' -f $drive) `
                            -Choices @('Yes', 'No') `
                            -Default 'No' `
                            -Silent:$Silent
                        if ($confirmSuspend -eq 'Yes') {
                            Suspend-BitLocker -MountPoint $drive -RebootCount 2 -ErrorAction Stop
                            Write-ToolOutput ('BitLocker suspended on {0} for 2 reboots.' -f $drive) -Level Success
                            Complete-ToolRun $run -Status Success `
                                -Summary ('BitLocker suspended on {0} for 2 reboots' -f $drive)
                        } else {
                            Complete-ToolRun $run -Status Skipped -Summary 'Suspend cancelled by user'
                        }
                    }
                }
            }

            'Resume' {
                # Resuming is the safe direction; single confirm with Default Yes
                if ($volumes.Count -eq 0) {
                    Write-ToolOutput 'No BitLocker volumes found to resume.' -Level Warning
                    Complete-ToolRun $run -Status Warning -Summary 'Resume: no BitLocker volumes found'
                } else {
                    $driveList = @($volumes | ForEach-Object { $_.MountPoint }) + @('Cancel')
                    $driveDefault = 'C:'
                    if ($driveList -notcontains 'C:') { $driveDefault = $driveList[0] }
                    $drive = Read-ToolChoice `
                        -Prompt 'Select drive to resume' `
                        -Choices $driveList `
                        -Default $driveDefault `
                        -Silent:$Silent
                    if ($drive -eq 'Cancel') {
                        Complete-ToolRun $run -Status Skipped -Summary 'Resume cancelled by user'
                    } else {
                        $confirmResume = Read-ToolChoice `
                            -Prompt ('Resume BitLocker protection on {0}?' -f $drive) `
                            -Choices @('Yes', 'No') `
                            -Default 'Yes' `
                            -Silent:$Silent
                        if ($confirmResume -eq 'Yes') {
                            Resume-BitLocker -MountPoint $drive -ErrorAction Stop
                            Write-ToolOutput ('BitLocker protection resumed on {0}.' -f $drive) -Level Success
                            Complete-ToolRun $run -Status Success `
                                -Summary ('BitLocker protection resumed on {0}' -f $drive)
                        } else {
                            Complete-ToolRun $run -Status Skipped -Summary 'Resume cancelled by user'
                        }
                    }
                }
            }

            default {
                # 'None' selected -- report only, no changes made
                if ($volumes.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary 'BitLocker not present or not enabled on any volume'
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} BitLocker volume(s) reported; no changes made' -f $volumes.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
