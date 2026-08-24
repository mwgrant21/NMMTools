# -Version is handled before anything else - it is the lowest-risk path and must
# not depend on elevation detection, sink setup, or tool resolution succeeding.
if ($Version) {
    Write-ToolOutput ('NMM System Toolkit v{0}' -f $script:ToolkitVersion) -Level Info
    Write-ToolOutput ('Commit: {0}' -f $script:ToolkitCommit) -Level Info
    Write-ToolOutput ('Built: {0}' -f $script:ToolkitBuildDate) -Level Info
    exit 0
}

# ---- Entry point ------------------------------------------------------------
$script:IsAdmin = Test-IsAdmin

if ($LogPath) {
    Set-OutputSink -Sink Console -LogDirectory $LogPath
}

if ($ListTools -and $Tool) {
    Write-ToolOutput "Warning: -Tool '$Tool' is ignored when -ListTools is specified." -Level Warning
}

if ($ListTools) {
    Get-NmmTools | ForEach-Object { [PSCustomObject]$_ } |
        Sort-Object Category, Name |
        Format-Table Id, LegacyId, Name, Category, Risk, SilentCapable, RequiresAdmin -AutoSize
    exit 0
}

if ($Tool) {
    $resolved = Resolve-NmmTool -Query $Tool
    if (-not $resolved) {
        Write-ToolOutput "No tool matches '$Tool'. Use -ListTools to see available tools." -Level Error
        exit 1
    }
    $status = Invoke-NmmTool -Tool $resolved -Silent:$Silent -Force:$Force
    if ($status -eq 'Success' -or $status -eq 'Skipped' -or $status -eq 'Warning') { exit 0 }
    exit 1
}

# Mode selection - only in interactive sessions without -Tool/-ListTools
if ($Mode -eq 'Auto' -and [Environment]::UserInteractive) {
    Write-Host ('NMM System Toolkit v{0}' -f $script:ToolkitVersion)
    Write-Host '  1 = Console  2 = GUI'
    try { $modeInput = Read-Host '' } catch { $modeInput = '' }
    if ($modeInput.Trim() -eq '2') { $script:Mode = 'GUI' } else { $script:Mode = 'Console' }
} else {
    $script:Mode = $Mode
}

Invoke-ElevationCheck

if ($script:Mode -eq 'GUI') {
    Start-GuiMenu
    exit 0
}

Start-ConsoleMenu
