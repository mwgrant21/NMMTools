function Reset-WindowsExplorer {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-explorer-reset'

        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # --- Report ---
        $explorer = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        Write-ToolOutput ('explorer.exe running: {0}' -f ($explorer.Count -gt 0)) -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Explorer action' `
            -Choices @('None','RestartExplorer','ClearExplorerCache','RebuildIconCache') -Default 'None' -Silent:$Silent

        # Every action here kills explorer.exe and relaunches it. From an
        # elevated session the kill lands on the USER's shell while the relaunch
        # starts explorer in the TECHNICIAN's session - so the user can be left
        # staring at an empty desktop. Refuse rather than risk that; the caches
        # below are also locked while the user's explorer is running, so a
        # half-run would achieve little anyway.
        if ($action -ne 'None' -and $ctx.IsRedirected) {
            Write-ToolOutput ('Explorer actions must run in the user session: the restart would start explorer as {0}, not {1}.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Error
            Complete-ToolRun $run -Status Failed `
                -Summary ('Explorer action refused - would restart explorer as {0}, not {1}. Nothing was changed.' -f $ctx.ProcessName, $ctx.DisplayName)
            return
        }
        if ($action -ne 'None' -and -not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot reset Explorer - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        switch ($action) {

            'RestartExplorer' {
                Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Process "$env:SystemRoot\explorer.exe"
                Start-Sleep -Seconds 2
                Write-ToolOutput 'Explorer restarted.' -Level Success
                Complete-ToolRun $run -Status Success -Summary 'Explorer restarted'
            }

            'ClearExplorerCache' {
                $confirm = Read-ToolChoice -Prompt 'Clear thumbnails, Recent files, and jump lists?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearExplorerCache cancelled'
                } else {
                    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $explorerDir = Join-Path $ctx.LocalAppData 'Microsoft\Windows\Explorer'
                    # These deletes are file-only and name-filtered, so they cannot
                    # recurse out of the profile - but Get-ChildItem on a junctioned
                    # DIRECTORY still enumerates the target, so a matching file
                    # elsewhere would be deleted. Gate the parent directory.
                    if (Test-UserPathContained -Context $ctx -Path $explorerDir) {
                        Get-ChildItem -LiteralPath $explorerDir -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    $recent = Join-Path $ctx.AppData 'Microsoft\Windows\Recent'
                    foreach ($sub in @('', 'AutomaticDestinations', 'CustomDestinations')) {
                        if ($sub) { $path = Join-Path $recent $sub } else { $path = $recent }
                        if (Test-UserPathContained -Context $ctx -Path $path) {
                            Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue |
                                Where-Object { -not $_.PSIsContainer } |
                                Remove-Item -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Start-Process "$env:SystemRoot\explorer.exe"
                    Start-Sleep -Seconds 2
                    Write-ToolOutput 'Explorer cache cleared; explorer restarted.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Cleared thumbnails, Recent, and jump lists'
                }
            }

            'RebuildIconCache' {
                $confirm = Read-ToolChoice -Prompt 'Rebuild the icon cache (deletes IconCache; explorer restarts)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RebuildIconCache cancelled'
                } else {
                    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $explorerDir = Join-Path $ctx.LocalAppData 'Microsoft\Windows\Explorer'
                    if (Test-UserPathContained -Context $ctx -Path $explorerDir) {
                        Get-ChildItem -LiteralPath $explorerDir -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    $iconDb = Join-Path $ctx.LocalAppData 'IconCache.db'
                    if (Test-Path -LiteralPath $iconDb) { Remove-Item -LiteralPath $iconDb -Force -ErrorAction SilentlyContinue }
                    Start-Process "$env:SystemRoot\explorer.exe"
                    Start-Sleep -Seconds 2
                    Write-ToolOutput 'Icon cache deleted; explorer restarted (icons regenerate over a few minutes).' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Icon cache rebuilt'
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Explorer reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
