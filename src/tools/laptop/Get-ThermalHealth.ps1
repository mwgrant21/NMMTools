function Get-ThermalHealth {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'thermal-health'

        # --- CPU temperature via ACPI thermal zone (many machines don't expose this) ---
        $cpuTemp = $null
        try {
            $zones = Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop
            if ($zones -and $zones.CurrentTemperature) {
                # Tenths of Kelvin -> Celsius
                $firstTemp = @($zones.CurrentTemperature)[0]
                $cpuTemp   = [math]::Round(($firstTemp / 10) - 273.15, 1)
            }
        }
        catch {
            # Thermal sensor not exposed by firmware - this is normal; handled below
        }

        # --- CPU load (progress/slow counter read stays at Info level per convention) ---
        $cpuLoad = $null
        try {
            $sample  = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples
            if ($sample) {
                $cpuLoad = [math]::Round($sample[0].CookedValue, 2)
            }
        }
        catch {
            # Counter unavailable - leave as null
        }

        # --- Max CPU frequency ---
        $maxFreqMHz = $null
        try {
            $proc       = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
            $maxFreqMHz = if ($proc) { @($proc)[0].MaxClockSpeed } else { $null }
        }
        catch { }

        # Thermal snapshot headline; detail rows follow
        Write-ToolOutput 'Thermal and CPU snapshot'

        if ($null -ne $cpuTemp) {
            $tempLine = 'CPU Temperature: {0} C' -f $cpuTemp
            if ($cpuTemp -gt 80) {
                Write-ToolOutput $tempLine -Level Warning
            } else {
                Write-ToolOutput $tempLine -Level Detail
            }
        } else {
            # Absent sensor is normal - report at Detail, not Warning
            Write-ToolOutput 'CPU Temperature: not available (thermal sensor not exposed by firmware)' -Level Detail
        }

        if ($null -ne $cpuLoad) {
            $loadLine = 'CPU Load: {0}%' -f $cpuLoad
            if ($cpuLoad -gt 80) {
                Write-ToolOutput $loadLine -Level Warning
            } else {
                Write-ToolOutput $loadLine -Level Detail
            }
        } else {
            Write-ToolOutput 'CPU Load: not available' -Level Detail
        }

        if ($null -ne $maxFreqMHz) {
            Write-ToolOutput ('CPU Max Frequency: {0} MHz' -f $maxFreqMHz) -Level Detail
        }

        # --- Throttling risk verdict ---
        $throttleRisk = $false
        if ($null -ne $cpuTemp -and $cpuTemp -gt 85 -and $null -ne $cpuLoad -and $cpuLoad -gt 70) {
            $throttleRisk = $true
            Write-ToolOutput ('Throttling risk: high temperature ({0} C) with high load ({1}%)' -f $cpuTemp, $cpuLoad) -Level Warning
        } else {
            Write-ToolOutput 'Throttling risk: none detected' -Level Detail
        }

        # --- Summary ---
        if ($null -eq $cpuTemp) {
            $tempStr = 'sensor N/A'
        } else {
            $tempStr = '{0} C' -f $cpuTemp
        }
        $loadStr = if ($null -ne $cpuLoad) { '{0}%' -f $cpuLoad } else { 'N/A' }

        if ($throttleRisk) {
            Complete-ToolRun $run -Status Warning -Summary ('Thermal risk detected - Temp: {0}  Load: {1}' -f $tempStr, $loadStr)
        } elseif ($null -eq $cpuTemp) {
            Complete-ToolRun $run -Status Warning -Summary ('Thermal sensor not exposed by firmware; Load: {0}' -f $loadStr)
        } else {
            Complete-ToolRun $run -Status Success -Summary ('Temp: {0}  Load: {1}  No throttling detected' -f $tempStr, $loadStr)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
