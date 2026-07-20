function Get-DeviceManagerErrors {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'device-manager-errors'

        $codeMeaning = @{
            1  = 'Device is not configured correctly'
            10 = 'Device cannot start'
            18 = 'Reinstall the drivers for this device'
            19 = 'Registry may be corrupted'
            22 = 'Device is disabled'
            24 = 'Device is not present, not working, or missing drivers'
            28 = 'Drivers for this device are not installed'
            31 = 'Device is not working properly (drivers or required software missing)'
            32 = 'Driver service is disabled'
            37 = 'Windows cannot initialize the device driver'
            39 = 'Driver is missing or corrupted'
            43 = 'Windows has stopped this device because it has reported problems'
            45 = 'Device is not currently connected'
        }

        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 })

        if ($devices.Count -eq 0) {
            Write-ToolOutput 'No devices reporting errors.'
            Complete-ToolRun $run -Status Success -Summary 'No Device Manager errors'
            return
        }

        Write-ToolOutput ('Devices with errors: {0}' -f $devices.Count)
        foreach ($d in $devices) {
            $meaning = $codeMeaning[[int]$d.ConfigManagerErrorCode]
            if (-not $meaning) { $meaning = 'Unknown error code' }
            Write-ToolOutput ('{0}  [Code {1}] {2} - {3}' -f $d.Name, $d.ConfigManagerErrorCode, $d.PNPClass, $meaning) -Level Detail
        }

        Complete-ToolRun $run -Status Warning -Summary ('{0} device(s) reporting Device Manager errors' -f $devices.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
