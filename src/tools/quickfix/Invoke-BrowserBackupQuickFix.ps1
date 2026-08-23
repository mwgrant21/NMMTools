function Invoke-BrowserBackupQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'browser-backup-quick-fix'

        $catalog = Get-BrowserCatalog
        $root = Get-BrowserBackupRoot -PreferredRoot 'M:\BrowserBackups'

        Write-ToolOutput ('Browser backup quick fix will: close all browsers, then back up bookmarks/logins for installed browsers to {0}.' -f $root) -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed? This closes all browsers.' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Browser backup quick fix declined'
            return
        }

        $procNames = @($catalog | ForEach-Object { $_.ProcessNames } | Sort-Object -Unique)
        [void](Close-Browsers -ProcessNames $procNames)

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $destDir = Join-Path $root ('QuickBackup_{0}' -f $stamp)
        try { New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null }
        catch {
            Complete-ToolRun $run -Status Warning -Summary ('Backup destination not writable: {0}' -f $destDir)
            return
        }

        # ACL-lock the destination BEFORE any file (including credential stores like Chromium
        # Login Data or Firefox key4.db/logins.json, which genuinely travel in the clear) is
        # copied into it - this backup set is identical to Invoke-BrowserBackupRestore.ps1's
        # Backup action, which applies this same lock; this quick-fix twin had drifted from
        # that sibling and shipped with no ACL protection at all.
        $currentSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        & icacls "$destDir" /inheritance:r /grant:r ("*$($currentSid):(OI)(CI)F") | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $destDir -Recurse -Force -ErrorAction SilentlyContinue
            Complete-ToolRun $run -Status Warning -Summary 'Backup aborted: could not restrict destination folder permissions before writing'
            return
        }

        $files = 0
        $browsers = 0
        foreach ($b in $catalog) {
            $profiles = @(Get-BrowserProfiles -Browser $b)
            if ($profiles.Count -eq 0) { continue }
            $browsers++
            foreach ($prof in $profiles) {
                $target = Join-Path (Join-Path $destDir $b.Name) $prof.Name
                New-Item -ItemType Directory -Path $target -Force -ErrorAction SilentlyContinue | Out-Null
                foreach ($fn in $b.BackupFiles) {
                    $src = Join-Path $prof.FullName $fn
                    if (Test-Path -LiteralPath $src) {
                        Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath (Join-Path $target $fn)) { $files++ }
                    }
                }
            }
        }

        $zip = ('{0}.zip' -f $destDir)
        Compress-Archive -Path (Join-Path $destDir '*') -DestinationPath $zip -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $zip) {
            & icacls "$zip" /inheritance:r /grant:r ("*$($currentSid):F") | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path -LiteralPath $zip) {
            Complete-ToolRun $run -Status Success -Summary ('{0} file(s) from {1} browser(s) backed up to {2}' -f $files, $browsers, $zip)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('{0} file(s) copied to {1} but ZIP was not created' -f $files, $destDir)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
