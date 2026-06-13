function Repair-SleepHibernate {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'sleep-hibernate'

        # --- Report: supported sleep states ---
        Write-ToolOutput 'Supported sleep states:' -Level Info
        $sleepStates = powercfg /availablesleepstates 2>&1
        foreach ($line in $sleepStates) {
            if ($line) {
                Write-ToolOutput ('  {0}' -f $line) -Level Detail
            }
        }

        # --- Report: power request blockers ---
        Write-ToolOutput 'Power request blockers (powercfg /requests):' -Level Info
        $blockers = powercfg /requests 2>&1
        foreach ($line in $blockers) {
            if ($line) {
                Write-ToolOutput ('  {0}' -f $line) -Level Detail
            }
        }

        # --- Action menu: report above, action below (v9 gate - v8 applied timers silently without confirm) ---
        $action = Read-ToolChoice `
            -Prompt 'Sleep/hibernate repair action' `
            -Choices @('None','ApplyStandardTimers','ClearWakeBlockers') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'ApplyStandardTimers' {
                Write-ToolOutput 'WARNING: This will overwrite lid/sleep/hibernate timer settings on the current power scheme.' -Level Warning
                $gate = Read-ToolChoice `
                    -Prompt 'Apply standard timers (lid=sleep, sleep 30/15 min, hibernate 3h/2h AC/DC)?' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Applying standard sleep/hibernate timers to SCHEME_CURRENT...' -Level Info
                    # Lid close action: sleep on AC and DC (1 = sleep)
                    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1 2>&1 | Out-Null
                    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1 2>&1 | Out-Null
                    # Sleep idle timeout: 30 min AC (1800s), 15 min DC (900s)
                    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 1800 2>&1 | Out-Null
                    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 900 2>&1 | Out-Null
                    # Hibernate idle timeout: 3 hr AC (10800s), 2 hr DC (7200s)
                    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 10800 2>&1 | Out-Null
                    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 7200 2>&1 | Out-Null
                    powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
                    Write-ToolOutput 'Standard timers applied: lid=sleep, sleep 30/15 min, hibernate 3h/2h (AC/DC)' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Standard sleep/hibernate timers applied to SCHEME_CURRENT'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'ApplyStandardTimers cancelled by user'
                }
            }
            'ClearWakeBlockers' {
                $gate = Read-ToolChoice `
                    -Prompt 'Restart Audiosrv to clear audio wake blockers (audio briefly drops)?' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Restarting Audiosrv to clear audio-related sleep blockers...' -Level Info
                    Stop-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
                    Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
                    Write-ToolOutput 'Audiosrv restarted' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Audiosrv restarted to clear wake blockers'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearWakeBlockers cancelled by user'
                }
            }
            default {
                Complete-ToolRun $run -Status Success -Summary 'Sleep states and wake blockers reported; no changes made'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
