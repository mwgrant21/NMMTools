function Get-SystemUptime {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = New-ToolRun -Id 'system-uptime'
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime
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
