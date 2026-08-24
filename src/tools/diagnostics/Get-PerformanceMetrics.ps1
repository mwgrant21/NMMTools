function Get-PerformanceMetrics {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'performance-metrics'

        # Win32_OperatingSystem is a singleton; Select-Object -First 1 guards against unexpected multi-instance results
        $os = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1

        $memUsed    = $os.TotalVisibleMemorySize - $os.FreePhysicalMemory
        $memPercent = [math]::Round(($memUsed / $os.TotalVisibleMemorySize) * 100, 2)
        # TotalVisibleMemorySize is in KB; dividing KB by 1MB (=1048576) yields GB
        $memUsedGB  = [math]::Round($memUsed / 1MB, 2)
        $memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $procCount  = (Get-Process).Count

        # Primary data rows use Info (default level)
        Write-ToolOutput ('Memory Used  : {0} GB / {1} GB ({2}%)' -f $memUsedGB, $memTotalGB, $memPercent)
        Write-ToolOutput ('Processes    : {0}' -f $procCount)

        if ($memPercent -gt 80) {
            Write-ToolOutput 'Memory usage is high (>80%).' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary ('RAM: {0}%; {1} processes - high memory' -f $memPercent, $procCount)
        }
        else {
            Complete-ToolRun $run -Status Success -Summary ('RAM: {0}%; {1} processes' -f $memPercent, $procCount)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
