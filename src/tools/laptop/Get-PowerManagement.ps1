function Get-PowerManagement {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'power-management'

        # --- Active power plan ---
        $activeScheme = powercfg /getactivescheme 2>&1
        Write-ToolOutput ('Active power plan: {0}' -f $activeScheme)

        # --- All available plans ---
        Write-ToolOutput 'Available power plans:' -Level Info
        $allPlans = powercfg /list 2>&1
        foreach ($line in $allPlans) {
            if ([string]$line -match 'Power Scheme GUID') {
                Write-ToolOutput ('  {0}' -f $line) -Level Detail
            }
        }

        # --- Battery info (laptops only) ---
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if ($battery) {
            $statusLabel = if ($battery.BatteryStatus -eq 2) { 'On AC Power' } else { 'On Battery' }
            Write-ToolOutput ('Battery: {0}%  Status: {1}' -f $battery.EstimatedChargeRemaining, $statusLabel)
        }

        # --- Extract plan name for summary ---
        $planName = [string]$activeScheme
        if ($planName -match '\((.+)\)') { $planName = $Matches[1] }

        # --- Action menu (report above; action below - REPORT-THEN-ACTION) ---
        $action = Read-ToolChoice `
            -Prompt 'Power plan action' `
            -Choices @('None','HighPerformance','Balanced','PowerSaver','ShowSleepTimers','DisableUsbSuspend') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'HighPerformance' {
                $gate = Read-ToolChoice `
                    -Prompt 'Switch to High Performance plan?' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Switching to High Performance...' -Level Info
                    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
                    Write-ToolOutput 'Power plan changed to High Performance' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Power plan set to High Performance'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'HighPerformance cancelled by user'
                }
            }
            'Balanced' {
                $gate = Read-ToolChoice `
                    -Prompt 'Switch to Balanced plan?' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Switching to Balanced...' -Level Info
                    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
                    Write-ToolOutput 'Power plan changed to Balanced' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Power plan set to Balanced'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'Balanced cancelled by user'
                }
            }
            'PowerSaver' {
                $gate = Read-ToolChoice `
                    -Prompt 'Switch to Power Saver plan?' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Switching to Power Saver...' -Level Info
                    powercfg /setactive a1841308-3541-4fab-bc81-f71556f20b4a 2>&1 | Out-Null
                    Write-ToolOutput 'Power plan changed to Power Saver' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Power plan set to Power Saver'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'PowerSaver cancelled by user'
                }
            }
            'ShowSleepTimers' {
                Write-ToolOutput 'Current sleep timer settings (SCHEME_CURRENT / SUB_SLEEP):' -Level Info
                $sleepSettings = powercfg /query SCHEME_CURRENT SUB_SLEEP 2>&1
                foreach ($line in $sleepSettings) {
                    if ($line) {
                        Write-ToolOutput ('  {0}' -f $line) -Level Detail
                    }
                }
                Complete-ToolRun $run -Status Success -Summary 'Sleep timer settings displayed (read-only)'
            }
            'DisableUsbSuspend' {
                $gate = Read-ToolChoice `
                    -Prompt 'Disable USB selective suspend (may improve USB device stability)?' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Disabling USB selective suspend...' -Level Info
                    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
                    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
                    powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
                    Write-ToolOutput 'USB selective suspend disabled on AC and DC' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'USB selective suspend disabled on AC and DC'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'DisableUsbSuspend cancelled by user'
                }
            }
            default {
                Complete-ToolRun $run -Status Success -Summary ('Active power plan: {0}' -f $planName)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
