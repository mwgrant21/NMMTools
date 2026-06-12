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
        # TODO (GUI/cutover phase): forward $PSBoundParameters so interactive flags (-LogPath etc.) survive elevation relaunch
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process -FilePath 'PowerShell.exe' -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host 'ERROR: Failed to request administrator privileges.' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host 'Run PowerShell as Administrator and re-launch the script.' -ForegroundColor Yellow
        if ([Environment]::UserInteractive) { Read-Host 'Press Enter to exit' | Out-Null }
    }
    exit
}
