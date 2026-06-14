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

                $zipPath = '{0}.zip' -f $destDir
                try {
                    Compress-Archive -Path ('{0}\*' -f $destDir) -DestinationPath $zipPath -Force -ErrorAction Stop
                    Write-ToolOutput ('ZIP created: {0}' -f $zipPath) -Level Success
                } catch {
                    Write-ToolOutput ('ZIP creation failed: {0}' -f $_.Exception.Message) -Level Warning
                    $zipPath = $null
                }

                # ACL-lock folder + zip to current user (best-effort; warn on failure)
                $aclOk = $true
                & icacls "$destDir" /inheritance:r /grant:r ('{0}:(OI)(CI)F' -f $env:USERNAME) | Out-Null
                if ($LASTEXITCODE -ne 0) { $aclOk = $false }
                if ($zipPath) {
                    & icacls "$zipPath" /inheritance:r /grant:r ('{0}:F' -f $env:USERNAME) | Out-Null
                    if ($LASTEXITCODE -ne 0) { $aclOk = $false }
                }
                if ($aclOk) {
                    Write-ToolOutput 'Backup ACL-restricted to current user.' -Level Success
                    $aclNote = 'ACL-locked'
                } else {
                    Write-ToolOutput 'WARNING: ACL lock failed (common on network shares); backup is NOT restricted.' -Level Warning
                    $aclNote = 'ACL-lock failed'
                }

                Complete-ToolRun $run -Status Success `
                    -Summary ('Backed up {0} file(s) to {1} ({2})' -f $backedUp, $destDir, $aclNote)
            }

            'Restore' {
                if ($existing.Count -eq 0) {
                    Write-ToolOutput ('No backups found under {0}.' -f $userRoot) -Level Warning
                }
                # Read-Host is safe here: only reached in the interactive Restore branch (never under -Silent).
                $sel = Read-Host 'Backup number (from the list above) or full path to a folder/.zip'
                $backupPath = $null
                if ($sel -match '^\d+$' -and [int]$sel -lt $existing.Count) {
                    $backupPath = $existing[[int]$sel].FullName
                } elseif ($sel -and (Test-Path -LiteralPath $sel)) {
                    $backupPath = $sel
                }
                if (-not $backupPath) {
                    Complete-ToolRun $run -Status Warning -Summary 'Restore aborted: no valid backup selected'
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
