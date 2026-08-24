function Repair-AudioAdvanced {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'audio-repair'

        # --- Report ---
        $devices = @(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)
        if ($devices.Count -gt 0) {
            Write-ToolOutput ('Audio devices: {0}' -f $devices.Count) -Level Info
            foreach ($d in $devices) { Write-ToolOutput ('  {0} [{1}]' -f $d.Name, $d.Status) -Level Detail }
        } else {
            Write-ToolOutput 'No audio devices found.' -Level Warning
        }
        foreach ($svc in @('Audiosrv','AudioEndpointBuilder')) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) { Write-ToolOutput ('  {0}: {1}' -f $s.DisplayName, $s.Status) -Level Detail }
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Audio action' `
            -Choices @('None','RestartAudioServices','ResetAudioSettings','RunAudioTroubleshooter') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartAudioServices' {
                Restart-Service -Name 'AudioEndpointBuilder' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Restart-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $now = (Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue).Status
                if (-not $now) { $now = 'Unknown' }
                if ($now -eq 'Running') {
                    Complete-ToolRun $run -Status Success -Summary 'Audio services restarted (Audiosrv Running)'
                } else {
                    Complete-ToolRun $run -Status Warning -Summary ('Audio services restart left Audiosrv {0}' -f $now)
                }
            }

            'ResetAudioSettings' {
                $confirm = Read-ToolChoice -Prompt 'Cycle the audio devices and restart the audio services?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ResetAudioSettings cancelled'
                } else {
                    $cycled = 0
                    try {
                        Stop-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
                        Stop-Service -Name 'AudioEndpointBuilder' -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        foreach ($dev in @(Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })) {
                            try {
                                Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                Start-Sleep -Seconds 1
                                Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction Stop
                                $cycled++
                            } catch {
                                # Best-effort re-enable so the device is not left disabled, then warn.
                                Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                Write-ToolOutput ('  Could not cleanly cycle {0}; attempted re-enable' -f $dev.FriendlyName) -Level Warning
                            }
                        }
                    } finally {
                        Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 1
                        Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                    }
                    $now = (Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue).Status
                    if (-not $now) { $now = 'Unknown' }
                    if ($now -eq 'Running') {
                        Complete-ToolRun $run -Status Success -Summary ('Audio reset: {0} device(s) cycled; Audiosrv Running' -f $cycled)
                    } else {
                        Complete-ToolRun $run -Status Warning -Summary ('Audio reset: {0} device(s) cycled but Audiosrv is {1}' -f $cycled, $now)
                    }
                }
            }

            'RunAudioTroubleshooter' {
                Start-Process 'ms-settings:troubleshoot' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Opened the Windows troubleshooter settings (run the Playing Audio troubleshooter there).' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened the Windows troubleshooter settings'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('{0} audio device(s) reported; no action taken' -f $devices.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
