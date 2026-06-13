function Repair-TouchpadKeyboard {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'touchpad-keyboard'

        # --- Scan HID class devices: touchpad/trackpad/keyboard/OEM ---
        $hidDevices = @(Get-PnpDevice -Class 'HIDClass' -ErrorAction SilentlyContinue | Where-Object {
            $_.FriendlyName -match 'touchpad|trackpad|keyboard' -or
            $_.FriendlyName -match 'Synaptics|ELAN|Precision.*TouchPad'
        })

        $erroredDevices = @($hidDevices | Where-Object { $_.Status -eq 'Error' -or $_.Status -eq 'Unknown' })

        if ($hidDevices.Count -eq 0) {
            Write-ToolOutput 'No matching HID touchpad/keyboard devices found' -Level Warning
        } else {
            Write-ToolOutput ('HID input devices found ({0}):' -f $hidDevices.Count)
            foreach ($dev in $hidDevices) {
                if ($dev.Status -eq 'Error' -or $dev.Status -eq 'Unknown') {
                    Write-ToolOutput ('  {0}  Status: {1}' -f $dev.FriendlyName, $dev.Status) -Level Warning
                } else {
                    Write-ToolOutput ('  {0}  Status: {1}' -f $dev.FriendlyName, $dev.Status) -Level Detail
                }
            }
        }

        if ($erroredDevices.Count -eq 0) {
            Write-ToolOutput 'No errored/unknown HID input devices detected' -Level Info
        } else {
            Write-ToolOutput ('{0} device(s) in Error/Unknown state' -f $erroredDevices.Count) -Level Warning
        }

        # --- FilterKeys / StickyKeys flags (report phase) ---
        $filterFlags = (Get-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' `
            -Name 'Flags' -ErrorAction SilentlyContinue).Flags
        $stickyFlags = (Get-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' `
            -Name 'Flags' -ErrorAction SilentlyContinue).Flags

        # Flag values 122/510 indicate the feature was triggered/activated
        $accessTriggered = ($filterFlags -eq '122' -or $stickyFlags -eq '510')
        if ($accessTriggered) {
            Write-ToolOutput ('Filter/Sticky Keys activated (FilterKeys={0}, StickyKeys={1}) - may cause unexpected typing behavior' -f $filterFlags, $stickyFlags) -Level Warning
        } else {
            Write-ToolOutput ('Filter/Sticky Keys: FilterKeys={0}, StickyKeys={1} (OK)' -f $filterFlags, $stickyFlags) -Level Detail
        }

        # --- Action menu (report above, action below) ---
        $action = Read-ToolChoice `
            -Prompt 'Input device action' `
            -Choices @('None','EnableErroredDevices','ClearStickyFilterKeys') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'EnableErroredDevices' {
                if ($erroredDevices.Count -eq 0) {
                    Write-ToolOutput 'No errored HID input devices to enable' -Level Info
                    Complete-ToolRun $run -Status Skipped -Summary 'No errored HID input devices found'
                } else {
                    $gate = Read-ToolChoice `
                        -Prompt ('Enable {0} errored HID input device(s)?' -f $erroredDevices.Count) `
                        -Choices @('Yes','No') `
                        -Default 'No' `
                        -Silent:$Silent
                    if ($gate -eq 'Yes') {
                        $enabled = 0
                        foreach ($dev in $erroredDevices) {
                            try {
                                Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                Write-ToolOutput ('  Enabled: {0}' -f $dev.FriendlyName) -Level Success
                                $enabled++
                            } catch {
                                Write-ToolOutput ('  Could not enable {0}: {1}' -f $dev.FriendlyName, $_.Exception.Message) -Level Warning
                            }
                        }
                        Complete-ToolRun $run -Status Success `
                            -Summary ('Enabled {0}/{1} errored HID input device(s)' -f $enabled, $erroredDevices.Count)
                    } else {
                        Complete-ToolRun $run -Status Skipped -Summary 'EnableErroredDevices cancelled by user'
                    }
                }
            }
            'ClearStickyFilterKeys' {
                if (-not $accessTriggered) {
                    Write-ToolOutput 'Filter/Sticky Keys not in activated state - no change needed' -Level Info
                    Complete-ToolRun $run -Status Skipped -Summary 'Filter/Sticky Keys not activated; no change made'
                } else {
                    $gate = Read-ToolChoice `
                        -Prompt 'Disable Filter Keys and Sticky Keys?' `
                        -Choices @('Yes','No') `
                        -Default 'No' `
                        -Silent:$Silent
                    if ($gate -eq 'Yes') {
                        Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' `
                            -Name 'Flags' -Value '126' -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' `
                            -Name 'Flags' -Value '506' -ErrorAction SilentlyContinue
                        Write-ToolOutput 'Filter Keys and Sticky Keys disabled' -Level Success
                        Complete-ToolRun $run -Status Success -Summary 'Filter Keys and Sticky Keys cleared'
                    } else {
                        Complete-ToolRun $run -Status Skipped -Summary 'ClearStickyFilterKeys cancelled by user'
                    }
                }
            }
            default {
                if ($erroredDevices.Count -gt 0 -or $accessTriggered) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary ('{0} errored device(s); Filter/Sticky Keys activated: {1}' -f $erroredDevices.Count, $accessTriggered)
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('HID input devices OK; {0} device(s) checked' -f $hidDevices.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
