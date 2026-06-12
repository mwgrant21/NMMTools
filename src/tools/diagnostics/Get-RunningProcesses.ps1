function Get-RunningProcesses {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'running-processes'

        $processes = @(Get-Process |
            Sort-Object WorkingSet -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                [PSCustomObject]@{
                    ProcessName = $_.ProcessName
                    PID         = $_.Id
                    Memory_MB   = [math]::Round($_.WorkingSet / 1MB, 2)
                }
            })

        Write-ToolOutput 'Top 10 processes by memory:'
        foreach ($p in $processes) {
            Write-ToolOutput ('  {0,-36} PID {1,-8} {2,8} MB' -f
                $p.ProcessName, $p.PID, $p.Memory_MB) -Level Detail
        }

        $top = $processes | Select-Object -First 1
        Complete-ToolRun $run -Status Success -Summary (
            'Top 10 processes by memory listed; highest: {0} ({1} MB)' -f
            $top.ProcessName, $top.Memory_MB)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
