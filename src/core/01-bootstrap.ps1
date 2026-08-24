# Admin detection and interactive elevation. CLI/PDQ mode never auto-elevates;
# PDQ runs as SYSTEM, and a UAC prompt would hang an unattended deployment.

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-ElevationCheck {
    if (Test-IsAdmin) { return }
    Write-Host 'Requesting administrator privileges...' -ForegroundColor Yellow
    try {
        $scriptPath = $PSCommandPath
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            throw 'Unable to determine script path for elevation.'
        }
        # -Tool/-ListTools/-Silent/-Force are irrelevant here - the CLI/PDQ path they belong to
        # already exits before this function is ever reached (see src\entry\99-main.ps1). Only
        # -LogPath needs to survive the relaunch: it's set on the original process before this
        # runs, but that process exits immediately after spawning the elevated one, so an
        # unforwarded -LogPath silently produces no log file for the entire (elevated) session.
        # Built as an argument array, not a concatenated string, so a path containing spaces or
        # special characters can't be misparsed by Start-Process.
        $elevatedArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-Mode', $script:Mode)
        if ($LogPath) { $elevatedArgs += @('-LogPath', $LogPath) }
        Start-Process -FilePath 'PowerShell.exe' -ArgumentList $elevatedArgs -Verb RunAs
    } catch {
        Write-Host 'ERROR: Failed to request administrator privileges.' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host 'Run PowerShell as Administrator and re-launch the script.' -ForegroundColor Yellow
        if ([Environment]::UserInteractive) { Read-Host 'Press Enter to exit' | Out-Null }
        # A bare `exit` below returns 0 regardless of which branch ran - a declined/failed
        # elevation request must not look like success to anything reading the exit code
        # (a PDQ package output check, a scheduled task, a launcher script).
        exit 1
    }
    exit
}
