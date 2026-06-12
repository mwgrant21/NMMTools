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
        Format-Table Id, LegacyId, Name, Category, Risk, SilentCapable -AutoSize
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

# Interactive mode: elevate, then menu
Invoke-ElevationCheck
Start-ConsoleMenu
