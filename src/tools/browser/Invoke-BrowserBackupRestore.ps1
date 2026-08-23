function Invoke-BrowserBackupRestore {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'browser-backup-restore'
        $catalog = Get-BrowserCatalog

        # --- Report (always, read-only) ---
        $present = @()
        Write-ToolOutput 'Detected browsers:' -Level Info
        foreach ($b in $catalog) {
            $profiles = @(Get-BrowserProfiles -Browser $b)
            if ($profiles.Count -gt 0) {
                $present += $b
                Write-ToolOutput ('  {0}: {1} profile(s)' -f $b.Name, $profiles.Count) -Level Detail
            }
        }
        if ($present.Count -eq 0) {
            Write-ToolOutput 'No supported browsers found for this user.' -Level Warning
        }

        $userRoot = Get-BrowserBackupRoot
        Write-ToolOutput ('Backup root: {0}' -f $userRoot) -Level Info
        $existing = @(Get-ChildItem -LiteralPath $userRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'BrowserBackup_*' } | Sort-Object LastWriteTime -Descending)
        if ($existing.Count -gt 0) {
            Write-ToolOutput ('Existing backups ({0}):' -f $existing.Count) -Level Info
            for ($i = 0; $i -lt [Math]::Min(10, $existing.Count); $i++) {
                Write-ToolOutput ('  [{0}] {1}  {2}' -f $i,
                    $existing[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $existing[$i].Name) -Level Detail
            }
        }

        # --- Action menu (safe default None -> -Silent reports only) ---
        $action = Read-ToolChoice -Prompt 'Browser action' `
            -Choices @('None','Backup','Restore') -Default 'None' -Silent:$Silent

        switch ($action) {

            'Backup' {
                Write-ToolOutput 'WARNING: backup INCLUDES saved passwords (Chromium Login Data; Firefox key4.db/logins.json).' -Level Warning
                Write-ToolOutput 'Chromium passwords are encrypted to THIS machine/user and will NOT decrypt if restored elsewhere. Firefox passwords DO travel.' -Level Warning

                $closeChoice = Read-ToolChoice -Prompt 'Close all browsers for a clean backup?' `
                    -Choices @('Yes','No') -Default 'Yes' -Silent:$Silent
                if ($closeChoice -eq 'Yes') {
                    $procs = @($present | ForEach-Object { $_.ProcessNames } | Sort-Object -Unique)
                    if ($procs.Count -gt 0) { Close-Browsers -ProcessNames $procs | Out-Null }
                }

                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                $destDir = Join-Path $userRoot ('BrowserBackup_{0}' -f $stamp)
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null

                # ACL-lock the destination BEFORE any file (including credential stores like
                # Chromium Login Data or Firefox key4.db/logins.json, which genuinely travel in
                # the clear) is copied into it - locking after the fact leaves plaintext-
                # equivalent credential material under inherited (broader, possibly
                # network-share) permissions for the whole copy window. Grant by SID rather
                # than $env:USERNAME so this can't collide with a same-named account.
                $currentSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
                & icacls "$destDir" /inheritance:r /grant:r ("*$($currentSid):(OI)(CI)F") | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Remove-Item -LiteralPath $destDir -Recurse -Force -ErrorAction SilentlyContinue
                    Write-ToolOutput 'ACL-lock failed (common on network shares); refusing to back up credential-bearing browser data unprotected.' -Level Warning
                    Complete-ToolRun $run -Status Warning -Summary 'Backup aborted: could not restrict destination folder permissions before writing'
                    return
                }
                Write-ToolOutput 'Backup destination ACL-restricted to current user.' -Level Success

                $backedUp = 0
                foreach ($b in $present) {
                    foreach ($prof in @(Get-BrowserProfiles -Browser $b)) {
                        $target = Join-Path (Join-Path $destDir $b.Name) $prof.Name
                        New-Item -Path $target -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                        $profCount = 0
                        foreach ($file in $b.BackupFiles) {
                            $src = Join-Path $prof.FullName $file
                            if (Test-Path -LiteralPath $src) {
                                try {
                                    Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction Stop
                                    $backedUp++
                                    $profCount++
                                } catch {
                                    Write-ToolOutput ('  [FAIL] {0}/{1}/{2}: {3}' -f $b.Name, $prof.Name, $file, $_.Exception.Message) -Level Warning
                                }
                            }
                        }
                        Write-ToolOutput ('  {0}/{1}: {2} file(s) backed up' -f $b.Name, $prof.Name, $profCount) -Level Detail
                    }
                }

                # Build the zip inside the already-locked directory, then apply the same SID
                # grant to the zip itself (a new file, so it doesn't inherit destDir's ACL).
                $zipPath = '{0}.zip' -f $destDir
                try {
                    Compress-Archive -Path ('{0}\*' -f $destDir) -DestinationPath $zipPath -Force -ErrorAction Stop
                    & icacls "$zipPath" /inheritance:r /grant:r ("*$($currentSid):F") | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
                        Write-ToolOutput 'ZIP ACL-lock failed; removed the unprotected zip (unzipped backup folder remains ACL-locked).' -Level Warning
                        $zipPath = $null
                    } else {
                        Write-ToolOutput ('ZIP created and ACL-restricted: {0}' -f $zipPath) -Level Success
                    }
                } catch {
                    Write-ToolOutput ('ZIP creation failed: {0}' -f $_.Exception.Message) -Level Warning
                    $zipPath = $null
                }

                Complete-ToolRun $run -Status Success `
                    -Summary ('Backed up {0} file(s) to {1} (ACL-locked)' -f $backedUp, $destDir)
            }

            'Restore' {
                if ($existing.Count -eq 0) {
                    Write-ToolOutput ('No backups found under {0}.' -f $userRoot) -Level Warning
                    Complete-ToolRun $run -Status Warning -Summary 'Restore aborted: no backups found'
                    return
                }
                # A bare Read-Host here throws in the GUI's hostless tool runspace (caught by
                # the outer catch before any state change - fails closed, but the feature
                # silently can't be used from the default UI mode). Read-ToolChoice only
                # supports enumerated choices, so offer the same numbered list already printed
                # above (capped at 10, matching the displayed list) instead of an arbitrary
                # typed number or path.
                $shownCount = [Math]::Min(10, $existing.Count)
                $indexChoices = @(0..($shownCount - 1) | ForEach-Object { "$_" })
                $sel = Read-ToolChoice -Prompt 'Backup number to restore (from the list above)' `
                    -Choices ($indexChoices + @('Cancel')) -Default 'Cancel' -Silent:$Silent
                $backupPath = $null
                if ($sel -ne 'Cancel' -and $sel -match '^\d+$' -and [int]$sel -lt $existing.Count) {
                    $backupPath = $existing[[int]$sel].FullName
                }
                if (-not $backupPath) {
                    Complete-ToolRun $run -Status Skipped -Summary 'Restore cancelled (no backup selected)'
                    return
                }

                $sourceRoot = $backupPath
                $tempFolder = $null
                if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                    if ($backupPath.ToLower().EndsWith('.zip')) {
                        $tempFolder = Join-Path $env:TEMP ('NMM_BrowserRestore_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                        New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
                        try {
                            Expand-Archive -LiteralPath $backupPath -DestinationPath $tempFolder -Force -ErrorAction Stop
                        } catch {
                            Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                            Complete-ToolRun $run -Status Failed -Summary ('Restore aborted: could not extract zip - {0}' -f $_.Exception.Message)
                            return
                        }
                        $sourceRoot = $tempFolder
                    } else {
                        Complete-ToolRun $run -Status Warning -Summary 'Restore aborted: file is not a .zip'
                        return
                    }
                }

                Write-ToolOutput 'WARNING: restore OVERWRITES current browser data with the backup.' -Level Warning
                Write-ToolOutput 'Chromium passwords from another machine/user will not decrypt here.' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Proceed with restore (overwrites current data)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    if ($tempFolder -and (Test-Path -LiteralPath $tempFolder)) {
                        Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Complete-ToolRun $run -Status Skipped -Summary 'Restore cancelled by user'
                    return
                }

                $closeChoice = Read-ToolChoice -Prompt 'Close all browsers before restore?' `
                    -Choices @('Yes','No') -Default 'Yes' -Silent:$Silent
                if ($closeChoice -eq 'Yes') {
                    $restoreProcs = @($catalog | ForEach-Object { $_.ProcessNames } | Sort-Object -Unique)
                    if ($restoreProcs.Count -gt 0) { Close-Browsers -ProcessNames $restoreProcs | Out-Null }
                }

                $restored = 0
                foreach ($b in $catalog) {
                    $browserSource = Join-Path $sourceRoot $b.Name
                    if (-not (Test-Path -LiteralPath $browserSource)) { continue }
                    if (-not (Test-Path -LiteralPath $b.BasePath)) {
                        Write-ToolOutput ('  [skip] {0} is not installed on this machine; not restored' -f $b.Name) -Level Detail
                        continue
                    }
                    foreach ($profDir in @(Get-ChildItem -LiteralPath $browserSource -Directory -ErrorAction SilentlyContinue)) {
                        $targetProfile = Join-Path $b.BasePath $profDir.Name
                        if (-not (Test-Path -LiteralPath $targetProfile)) {
                            New-Item -ItemType Directory -Path $targetProfile -Force | Out-Null
                        }
                        foreach ($file in @(Get-ChildItem -LiteralPath $profDir.FullName -File -ErrorAction SilentlyContinue)) {
                            if ($b.BackupFiles -notcontains $file.Name) {
                                Write-ToolOutput ('  [skip] unexpected file {0}/{1}/{2}' -f $b.Name, $profDir.Name, $file.Name) -Level Detail
                                continue
                            }
                            try {
                                Copy-Item -LiteralPath $file.FullName -Destination $targetProfile -Force -ErrorAction Stop
                                $restored++
                            } catch {
                                Write-ToolOutput ('  [FAIL] {0}/{1}/{2}: {3}' -f $b.Name, $profDir.Name, $file.Name, $_.Exception.Message) -Level Warning
                            }
                        }
                    }
                }

                if ($tempFolder -and (Test-Path -LiteralPath $tempFolder)) {
                    Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                }
                Write-ToolOutput 'Restart browsers to load the restored data.' -Level Info
                Complete-ToolRun $run -Status Success -Summary ('Restored {0} file(s) from {1}' -f $restored, $backupPath)
            }

            default {
                # 'None' -> report only
                if ($present.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No browsers found; no action taken'
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} browser(s) detected; no action taken' -f $present.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
