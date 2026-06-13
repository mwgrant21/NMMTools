function Repair-OneDriveClient {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'onedrive-repair'

        # Locate OneDrive.exe: user install, system ProgramFiles, ProgramFiles(x86)
        $odCandidates = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
            (Join-Path $env:ProgramFiles  'Microsoft OneDrive\OneDrive.exe')
        )
        $x86PF = ${env:ProgramFiles(x86)}
        if ($x86PF) {
            $odCandidates += Join-Path $x86PF 'Microsoft OneDrive\OneDrive.exe'
        }
        $odExe = $odCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $odExe) {
            Write-ToolOutput 'OneDrive not found on this machine.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'OneDrive.exe not found; cannot restart or reset'
            return
        }

        Write-ToolOutput ('OneDrive found: {0}' -f $odExe) -Level Detail
        $running = Get-Process OneDrive -ErrorAction SilentlyContinue
        if ($running) {
            Write-ToolOutput 'OneDrive is currently running.' -Level Detail
        } else {
            Write-ToolOutput 'OneDrive is not currently running.' -Level Detail
        }

        $choice = Read-ToolChoice -Prompt 'OneDrive action' `
            -Choices @('Restart', 'Reset') `
            -Default 'Restart' `
            -Silent:$Silent

        switch ($choice) {
            'Restart' {
                Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Process $odExe
                Complete-ToolRun $run -Status Success -Summary 'OneDrive restarted'
            }
            'Reset' {
                Write-ToolOutput ('WARNING: /reset wipes the local OneDrive sync database ' +
                    'and triggers a full re-sync of all files.') -Level Warning
                Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Process $odExe -ArgumentList '/reset'
                Start-Sleep -Seconds 5
                Start-Process $odExe
                Complete-ToolRun $run -Status Success -Summary 'OneDrive reset (full re-sync will follow)'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
