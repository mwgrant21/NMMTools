function Get-DriverInformation {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'driver-info'

        $drivers = @(Get-CimInstance Win32_PnPSignedDriver |
            Where-Object { $_.DeviceName } |
            Select-Object DeviceName, DriverVersion, DriverDate |
            Sort-Object DriverDate -Descending)

        if ($drivers.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No signed drivers with a device name found'
            return
        }

        Write-ToolOutput ('Total drivers: {0} (showing first 15)' -f $drivers.Count)
        # Driver rows use Detail; showing first 15 matches v8 display behavior
        foreach ($d in ($drivers | Select-Object -First 15)) {
            $dateStr = if ($d.DriverDate) { '{0:yyyy-MM-dd}' -f $d.DriverDate } else { 'unknown date' }
            Write-ToolOutput ('{0}  v{1}  [{2}]' -f $d.DeviceName, $d.DriverVersion, $dateStr) -Level Detail
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} drivers found' -f $drivers.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
