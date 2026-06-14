function Reset-WindowsExplorer {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-explorer-reset'

        # --- Report ---
        $explorer = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        Write-ToolOutput ('explorer.exe running: {0}' -f ($explorer.Count -gt 0)) -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Explorer action' `
            -Choices @('None','RestartExplorer','ClearExplorerCache','RebuildIconCache') -Default 'None' -Silent:$Silent

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
                    $explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
                    if (Test-Path -LiteralPath $explorerDir) {
                        Get-ChildItem -LiteralPath $explorerDir -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
                    foreach ($sub in @('', 'AutomaticDestinations', 'CustomDestinations')) {
                        if ($sub) { $path = Join-Path $recent $sub } else { $path = $recent }
                        if (Test-Path -LiteralPath $path) {
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
                    $explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
                    if (Test-Path -LiteralPath $explorerDir) {
                        Get-ChildItem -LiteralPath $explorerDir -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    $iconDb = Join-Path $env:LOCALAPPDATA 'IconCache.db'
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
