function Get-BluetoothDevices {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'bluetooth-devices'

        # --- Bluetooth adapter presence ---
        $btAdapter = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*Bluetooth*' })

        if ($btAdapter.Count -eq 0) {
            Write-ToolOutput 'No Bluetooth adapter detected on this device' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'No Bluetooth adapter detected'
            return
        }

        Write-ToolOutput ('Bluetooth adapter: {0}  Status: {1}' -f $btAdapter[0].Name, $btAdapter[0].Status)

        # --- Paired / visible BT devices ---
        $btDevices = @()
        try {
            $btDevices = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)
        } catch {
            Write-ToolOutput 'Unable to enumerate Bluetooth devices via Get-PnpDevice' -Level Warning
        }

        if ($btDevices.Count -gt 0) {
            Write-ToolOutput ('Bluetooth devices ({0}):' -f $btDevices.Count)
            foreach ($d in $btDevices) {
                $statusLabel = if ($d.Status -eq 'OK') { 'OK' } else { $d.Status }
                Write-ToolOutput ('  - {0}: {1}' -f $d.FriendlyName, $statusLabel) -Level Detail
            }
        } else {
            Write-ToolOutput 'No paired Bluetooth devices found' -Level Warning
        }

        # --- Action menu ---
        $action = Read-ToolChoice `
            -Prompt 'Bluetooth action' `
            -Choices @('None','RestartBluetoothService','OpenSettings') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'RestartBluetoothService' {
                $gate = Read-ToolChoice `
                    -Prompt 'Restart Bluetooth service (bthserv)? Bluetooth input devices will drop briefly.' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Restarting Bluetooth service (bthserv)...' -Level Info
                    Restart-Service bthserv -Force -ErrorAction Stop
                    Write-ToolOutput 'Bluetooth service restarted. Wait a few seconds for devices to reconnect.' -Level Success
                    Complete-ToolRun $run -Status Success `
                        -Summary ('BT adapter present, {0} device(s); bthserv restarted' -f $btDevices.Count)
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'RestartBluetoothService cancelled by user'
                }
            }
            'OpenSettings' {
                Write-ToolOutput 'Opening Bluetooth settings...' -Level Info
                Start-Process 'ms-settings:bluetooth'
                Write-ToolOutput 'Bluetooth settings opened' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('BT adapter present, {0} device(s); Bluetooth settings opened' -f $btDevices.Count)
            }
            default {
                Complete-ToolRun $run -Status Success `
                    -Summary ('BT adapter present; {0} device(s) listed' -f $btDevices.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
