function Get-SystemUptime {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'system-uptime'
        $os = Get-CimInstance Win32_OperatingSystem
        if ($null -eq $os.LastBootUpTime) {
            Complete-ToolRun $run -Status Failed -Summary 'CIM returned no LastBootUpTime - cannot compute uptime'
            return
        }
        $uptime = (Get-Date) - $os.LastBootUpTime
        if ($uptime.TotalSeconds -lt 0) {
            Complete-ToolRun $run -Status Warning -Summary ('Clock skew: current time precedes last boot ({0:g})' -f $os.LastBootUpTime)
            return
        }
        Write-ToolOutput ('Last boot: {0:g}' -f $os.LastBootUpTime)
        Write-ToolOutput ('Uptime:    {0} days, {1} hours, {2} minutes' -f
            $uptime.Days, $uptime.Hours, $uptime.Minutes)
        if ($uptime.Days -ge 14) {
            Write-ToolOutput 'Uptime exceeds 14 days - a reboot is recommended.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary ('Up {0} days - reboot recommended' -f $uptime.Days)
        } else {
            Complete-ToolRun $run -Status Success -Summary ('Up {0}d {1}h since {2:g}' -f
                $uptime.Days, $uptime.Hours, $os.LastBootUpTime)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
