function Get-BatteryHealth {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'battery-health'

        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue

        if (-not $battery) {
            Complete-ToolRun $run -Status Warning -Summary 'No battery detected (desktop system)'
            return
        }

        # Generate powercfg battery report to TEMP (ReadOnly: report artifact, no config change)
        $reportPath = "$env:TEMP\battery-report.html"
        powercfg /batteryreport /output $reportPath 2>&1 | Out-Null

        $designCap    = $battery.DesignCapacity
        $fullCap      = $battery.FullChargeCapacity
        $currentPct   = $battery.EstimatedChargeRemaining
        $statusCode   = $battery.BatteryStatus

        $statusLabel = switch ($statusCode) {
            1 { 'Discharging' }
            2 { 'AC Power' }
            3 { 'Fully Charged' }
            4 { 'Low' }
            5 { 'Critical' }
            default { 'Unknown' }
        }

        if ($fullCap -and $designCap -and $designCap -gt 0) {
            $wearPct   = [math]::Round((($designCap - $fullCap) / $designCap) * 100, 2)
            $healthPct = [math]::Round(($fullCap / $designCap) * 100, 2)
        } else {
            $wearPct   = $null
            $healthPct = $null
        }

        # Battery overview headline; detail rows follow
        Write-ToolOutput ('Battery status: {0}  Current charge: {1}%' -f $statusLabel, $currentPct)

        if ($null -ne $healthPct) {
            $healthLine = 'Health: {0}%  Wear: {1}%' -f $healthPct, $wearPct
            if ($healthPct -lt 60) {
                Write-ToolOutput $healthLine -Level Warning
            } else {
                Write-ToolOutput $healthLine -Level Detail
            }
        } else {
            Write-ToolOutput 'Health/wear: unknown (capacity data not available)' -Level Detail
        }

        # Capacity figures at Detail level
        if ($designCap) {
            Write-ToolOutput ('Design capacity: {0} Wh' -f [math]::Round($designCap / 1000, 2)) -Level Detail
        }
        if ($fullCap) {
            Write-ToolOutput ('Full-charge capacity: {0} Wh' -f [math]::Round($fullCap / 1000, 2)) -Level Detail
        }

        Write-ToolOutput ('Battery report saved: {0}' -f $reportPath) -Level Detail

        # Recommendation at Info/Warning level
        if ($null -ne $healthPct) {
            if ($healthPct -lt 60) {
                Write-ToolOutput 'RECOMMENDATION: Battery health below 60% - consider replacement.' -Level Warning
            } elseif ($healthPct -lt 80) {
                Write-ToolOutput 'RECOMMENDATION: Battery health declining - monitor and plan replacement.' -Level Warning
            }
        }

        # Summary for the ticket
        if ($null -ne $healthPct) {
            $summaryHealth = 'Health {0}%, Wear {1}%' -f $healthPct, $wearPct
            if ($healthPct -lt 60) {
                Complete-ToolRun $run -Status Warning -Summary ('{0}; report: {1}' -f $summaryHealth, $reportPath)
            } else {
                Complete-ToolRun $run -Status Success -Summary ('{0}; report: {1}' -f $summaryHealth, $reportPath)
            }
        } else {
            Complete-ToolRun $run -Status Success -Summary ('Capacity data unavailable - status: {0}; report: {1}' -f $statusLabel, $reportPath)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
