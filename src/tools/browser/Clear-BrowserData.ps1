function Clear-BrowserData {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'browser-clear'
        $catalog = Get-BrowserCatalog

        # --- Report ---
        Write-ToolOutput 'Comprehensive Browser Clear' -Level Info
        Write-ToolOutput '  CLEARS:    cache, cookies, history, sessions, site permissions' -Level Detail
        Write-ToolOutput '  PRESERVES: saved passwords, autofill, and Firefox bookmarks' -Level Detail
        $present = @()
        foreach ($b in $catalog) {
            $profiles = @(Get-BrowserProfiles -Browser $b)
            if ($profiles.Count -gt 0) {
                $present += [PSCustomObject]@{ Browser = $b; Profiles = $profiles }
                Write-ToolOutput ('  {0}: {1} profile(s)' -f $b.Name, $profiles.Count) -Level Detail
            }
        }
        if ($present.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No supported browsers found; nothing to clear'
            return
        }

        # --- Disruptive typed gate (dispatcher already refuses -Silent without -Force) ---
        $gate = Read-ToolChoice `
            -Prompt 'Type CONFIRM to clear browsing data (passwords/autofill/Firefox bookmarks are kept)' `
            -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
        if ($gate -ne 'CONFIRM') {
            Complete-ToolRun $run -Status Skipped -Summary 'Browser clear cancelled (no CONFIRM)'
            return
        }

        # Force-close browsers (locked files block deletion)
        $allProcs = @($present | ForEach-Object { $_.Browser.ProcessNames } | Sort-Object -Unique)
        Write-ToolOutput 'Closing browsers...' -Level Info
        if ($allProcs.Count -gt 0) { Close-Browsers -ProcessNames $allProcs | Out-Null }
        Start-Sleep -Seconds 1

        $clearedItems = 0
        $clearedBrowsers = 0
        foreach ($entry in $present) {
            $b = $entry.Browser
            $browserItems = 0
            foreach ($prof in $entry.Profiles) {
                foreach ($dir in $b.ClearDirs) {
                    $full = Join-Path $prof.FullName $dir
                    if (Test-Path -LiteralPath $full) {
                        Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        if (-not @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)) { $browserItems++ }
                    }
                }
                foreach ($file in $b.ClearFiles) {
                    $full = Join-Path $prof.FullName $file
                    if (Test-Path -LiteralPath $full) {
                        Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
                        if (-not (Test-Path -LiteralPath $full)) { $browserItems++ }
                    }
                }
                # Chromium: clear site permissions from Preferences JSON, preserving all other prefs.
                # Written UTF-8 without BOM (Chrome rejects a BOM in Preferences; v8 used ANSI Set-Content).
                if ($b.PrefsFile) {
                    $prefPath = Join-Path $prof.FullName $b.PrefsFile
                    if (Test-Path -LiteralPath $prefPath) {
                        try {
                            $prefs = Get-Content -LiteralPath $prefPath -Raw | ConvertFrom-Json
                            if ($prefs.profile.content_settings.exceptions) {
                                $prefs.profile.content_settings.exceptions = New-Object PSObject
                            }
                            if ($prefs.profile.per_host_zoom_levels) {
                                $prefs.profile.per_host_zoom_levels = New-Object PSObject
                            }
                            $json = $prefs | ConvertTo-Json -Depth 100 -Compress
                            [System.IO.File]::WriteAllText($prefPath, $json, (New-Object System.Text.UTF8Encoding($false)))
                            $browserItems++
                        } catch {
                            Write-ToolOutput ('  Note: could not edit {0} Preferences ({1})' -f $b.Name, $prof.Name) -Level Detail
                        }
                    }
                }
            }
            if ($browserItems -gt 0) {
                Write-ToolOutput ('  [OK] {0}: cleared {1} item(s) across {2} profile(s)' -f $b.Name, $browserItems, @($entry.Profiles).Count) -Level Success
                $clearedBrowsers++
                $clearedItems += $browserItems
            }
        }

        Complete-ToolRun $run -Status Success `
            -Summary ('Cleared {0} item(s) across {1} browser(s); passwords/autofill/Firefox bookmarks preserved' -f $clearedItems, $clearedBrowsers)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
