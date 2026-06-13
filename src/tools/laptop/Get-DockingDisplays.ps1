function Get-DockingDisplays {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'docking-displays'

        # --- Monitor report via WMI ---
        $displays = @(Get-CimInstance WmiMonitorID -Namespace 'root\wmi' -ErrorAction SilentlyContinue)

        if ($displays.Count -eq 0) {
            Write-ToolOutput 'Unable to detect monitor information via WMI' -Level Warning
        } else {
            Write-ToolOutput ('Connected displays ({0}):' -f $displays.Count)
            foreach ($d in $displays) {
                $mfr = ''
                $mdl = ''
                if ($d.ManufacturerName) {
                    $mfrBytes = [byte[]]($d.ManufacturerName | Where-Object { $_ -gt 0 })
                    if ($mfrBytes.Count -gt 0) {
                        $mfr = ([System.Text.Encoding]::ASCII.GetString($mfrBytes)).Trim()
                    }
                }
                if ($d.UserFriendlyName) {
                    $mdlBytes = [byte[]]($d.UserFriendlyName | Where-Object { $_ -gt 0 })
                    if ($mdlBytes.Count -gt 0) {
                        $mdl = ([System.Text.Encoding]::ASCII.GetString($mdlBytes)).Trim()
                    }
                }
                $label = ('{0} {1}' -f $mfr, $mdl).Trim()
                if (-not $label) { $label = 'Unknown monitor' }
                Write-ToolOutput ('  - {0}' -f $label) -Level Detail
            }
        }

        # --- Action menu ---
        # ExternalOnly/InternalOnly can hide the active display; use Win+P to recover
        $action = Read-ToolChoice `
            -Prompt 'Display action (ExternalOnly/InternalOnly can hide the active display - use Win+P to recover)' `
            -Choices @('None','Detect','Extend','Clone','ExternalOnly','InternalOnly','DisplaySettings') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'Detect' {
                Write-ToolOutput 'Running display detection...' -Level Info
                DisplaySwitch.exe /detect
                Write-ToolOutput 'Display detection triggered' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} display(s) found; ran DisplaySwitch /detect' -f $displays.Count)
            }
            'Extend' {
                Write-ToolOutput 'Extending displays...' -Level Info
                DisplaySwitch.exe /extend
                Write-ToolOutput 'Displays extended' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} display(s) found; switched to Extend mode' -f $displays.Count)
            }
            'Clone' {
                Write-ToolOutput 'Duplicating/cloning displays...' -Level Info
                DisplaySwitch.exe /clone
                Write-ToolOutput 'Displays duplicated' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} display(s) found; switched to Clone mode' -f $displays.Count)
            }
            'ExternalOnly' {
                Write-ToolOutput 'Switching to external display only - laptop screen will go dark. Use Win+P to recover if needed.' -Level Warning
                DisplaySwitch.exe /external
                Write-ToolOutput 'Switched to external display only' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} display(s) found; switched to External Only' -f $displays.Count)
            }
            'InternalOnly' {
                Write-ToolOutput 'Switching to internal display only - external monitors will go dark. Use Win+P to recover if needed.' -Level Warning
                DisplaySwitch.exe /internal
                Write-ToolOutput 'Switched to internal display only' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} display(s) found; switched to Internal Only' -f $displays.Count)
            }
            'DisplaySettings' {
                Write-ToolOutput 'Opening Display settings...' -Level Info
                Start-Process 'ms-settings:display'
                Write-ToolOutput 'Display settings opened' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} display(s) found; Display settings opened' -f $displays.Count)
            }
            default {
                if ($displays.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No monitor information available via WMI'
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} display(s) detected; no action taken' -f $displays.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
