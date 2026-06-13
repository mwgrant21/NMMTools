function Test-WebcamAudio {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'webcam-audio-test'

        # --- Audio devices ---
        $audioDevices = @(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)
        Write-ToolOutput ('Audio devices ({0}):' -f $audioDevices.Count)
        foreach ($d in $audioDevices) {
            Write-ToolOutput ('  - {0}' -f $d.Name) -Level Detail
        }

        # --- Camera / Image PnP devices ---
        $videoDevices = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPClass -eq 'Camera' -or $_.PNPClass -eq 'Image' })

        if ($videoDevices.Count -eq 0) {
            Write-ToolOutput 'No camera/image devices detected' -Level Warning
        } else {
            Write-ToolOutput ('Video/camera devices ({0}):' -f $videoDevices.Count)
            foreach ($d in $videoDevices) {
                $status = if ($d.Status -eq 'OK') { 'Working' } else { $d.Status }
                Write-ToolOutput ('  - {0}: {1}' -f $d.Name, $status) -Level Detail
            }
        }

        # --- Action menu ---
        $action = Read-ToolChoice `
            -Prompt 'Webcam/audio action' `
            -Choices @('None','OpenCamera','OpenSoundRecorder','OpenSoundSettings','CloseConflictingApps') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'OpenCamera' {
                Write-ToolOutput 'Opening Camera app...' -Level Info
                Start-Process 'microsoft.windows.camera:'
                Write-ToolOutput 'Camera app launched' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} audio, {1} video device(s); Camera app launched' -f $audioDevices.Count, $videoDevices.Count)
            }
            'OpenSoundRecorder' {
                Write-ToolOutput 'Opening Sound Recorder...' -Level Info
                Start-Process 'ms-sound-recorder:'
                Write-ToolOutput 'Sound Recorder launched' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} audio, {1} video device(s); Sound Recorder launched' -f $audioDevices.Count, $videoDevices.Count)
            }
            'OpenSoundSettings' {
                Write-ToolOutput 'Opening Sound settings...' -Level Info
                Start-Process 'ms-settings:sound'
                Write-ToolOutput 'Sound settings opened' -Level Success
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} audio, {1} video device(s); Sound settings opened' -f $audioDevices.Count, $videoDevices.Count)
            }
            'CloseConflictingApps' {
                $candidateNames = @('Teams','Zoom','Skype','Chrome','firefox','msedge')
                $running = @()
                foreach ($n in $candidateNames) {
                    $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
                    if ($procs.Count -gt 0) { $running += $n }
                }
                if ($running.Count -eq 0) {
                    Write-ToolOutput 'No conflicting apps currently running (checked: Teams, Zoom, Skype, Chrome, firefox, msedge)' -Level Warning
                    Complete-ToolRun $run -Status Warning `
                        -Summary ('{0} audio, {1} video device(s); no conflicting apps running' -f $audioDevices.Count, $videoDevices.Count)
                } else {
                    $listStr = $running -join ', '
                    $gate = Read-ToolChoice `
                        -Prompt ('Close these apps? (unsaved work will be lost): {0}' -f $listStr) `
                        -Choices @('Yes','No') `
                        -Default 'No' `
                        -Silent:$Silent
                    if ($gate -eq 'Yes') {
                        foreach ($n in $running) {
                            Write-ToolOutput ('Stopping {0}...' -f $n) -Level Info
                            Get-Process -Name $n -ErrorAction SilentlyContinue |
                                Stop-Process -Force -ErrorAction SilentlyContinue
                        }
                        Write-ToolOutput ('Closed: {0}' -f $listStr) -Level Success
                        Complete-ToolRun $run -Status Success `
                            -Summary ('{0} audio, {1} video device(s); closed conflicting apps: {2}' -f $audioDevices.Count, $videoDevices.Count, $listStr)
                    } else {
                        Complete-ToolRun $run -Status Skipped -Summary 'CloseConflictingApps cancelled by user'
                    }
                }
            }
            default {
                if ($videoDevices.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary ('{0} audio device(s); no camera/image devices detected' -f $audioDevices.Count)
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} audio device(s), {1} video device(s) found' -f $audioDevices.Count, $videoDevices.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
