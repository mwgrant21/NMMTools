function Repair-HotkeyFnKeys {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'hotkey-fn'

        # --- OEM hotkey/Fn service inventory ---
        $oemServiceNames = @(
            'LenovoVantageService',
            'Dell Digital Delivery Services',
            'HP Hotkey Support',
            'HP Software Framework Service',
            'SynTPEnhService',
            'ELAN Service'
        )

        $presentServices = @()
        $stoppedServices = @()

        Write-ToolOutput 'Checking OEM hotkey and Fn key services:'
        foreach ($svcName in $oemServiceNames) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $presentServices += $svc
                if ($svc.Status -ne 'Running') {
                    Write-ToolOutput ('  {0}: {1}' -f $svcName, $svc.Status) -Level Warning
                    $stoppedServices += $svc
                } else {
                    Write-ToolOutput ('  {0}: Running' -f $svcName) -Level Detail
                }
            } else {
                Write-ToolOutput ('  {0}: Not installed' -f $svcName) -Level Detail
            }
        }

        if ($presentServices.Count -eq 0) {
            Write-ToolOutput 'None of the checked OEM hotkey services are installed on this machine' -Level Info
        }

        # --- NumLock state ---
        $numLock = [Console]::NumberLock
        Write-ToolOutput ('NumLock: {0}' -f $(if ($numLock) { 'ON' } else { 'OFF' }))

        # --- Fn key BIOS advisory (informational only - cannot be changed from Windows) ---
        Write-ToolOutput 'Note: Fn key behavior is controlled by BIOS. Check BIOS for Fn Lock or Function Key Mode if Fn keys are inverted.' -Level Info

        # --- Action menu (report above, action below) ---
        $action = Read-ToolChoice `
            -Prompt 'Hotkey/Fn key action' `
            -Choices @('None','StartStoppedServices') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'StartStoppedServices' {
                if ($stoppedServices.Count -eq 0) {
                    Write-ToolOutput 'No stopped OEM hotkey services to start' -Level Info
                    Complete-ToolRun $run -Status Skipped -Summary 'No stopped OEM hotkey services found'
                } else {
                    $gate = Read-ToolChoice `
                        -Prompt ('Start and enable {0} stopped OEM service(s)?' -f $stoppedServices.Count) `
                        -Choices @('Yes','No') `
                        -Default 'No' `
                        -Silent:$Silent
                    if ($gate -eq 'Yes') {
                        $started = 0
                        foreach ($svc in $stoppedServices) {
                            try {
                                Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
                                Set-Service -Name $svc.Name -StartupType Automatic -ErrorAction SilentlyContinue
                                Write-ToolOutput ('  Started: {0}' -f $svc.Name) -Level Success
                                $started++
                            } catch {
                                Write-ToolOutput ('  Could not start {0}: {1}' -f $svc.Name, $_.Exception.Message) -Level Warning
                            }
                        }
                        Complete-ToolRun $run -Status Success `
                            -Summary ('Started {0}/{1} OEM hotkey service(s) and set to Automatic' -f $started, $stoppedServices.Count)
                    } else {
                        Complete-ToolRun $run -Status Skipped -Summary 'StartStoppedServices cancelled by user'
                    }
                }
            }
            default {
                if ($stoppedServices.Count -gt 0) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary ('{0} OEM service(s) present; {1} stopped' -f $presentServices.Count, $stoppedServices.Count)
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} OEM hotkey service(s) checked; none stopped' -f $presentServices.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
