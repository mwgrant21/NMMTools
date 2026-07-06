function Repair-WmiRepository {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'wmi-repair'

        # --- Report: winmgmt service state and start type ---
        $svc = Get-Service -Name 'winmgmt' -ErrorAction SilentlyContinue
        if ($svc) {
            Write-ToolOutput ('winmgmt service: Status={0}  StartType={1}' -f $svc.Status, $svc.StartType) -Level Info
        } else {
            Write-ToolOutput 'winmgmt service not found.' -Level Warning
        }

        # --- Report: WMI repository path and size on disk ---
        $repoPath = Join-Path $env:SystemRoot 'System32\wbem\Repository'
        if (Test-Path $repoPath) {
            $repoSizeMB = 0
            try {
                $sum = (Get-ChildItem -Path $repoPath -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($sum) { $repoSizeMB = [math]::Round($sum / 1MB, 1) }
            } catch { $repoSizeMB = 0 }
            Write-ToolOutput ('WMI repository path: {0}  (approx {1} MB)' -f $repoPath, $repoSizeMB) -Level Info
        } else {
            Write-ToolOutput ('WMI repository path not found: {0}' -f $repoPath) -Level Warning
        }

        # --- Report: winmgmt /verifyrepository verdict ---
        $verifyInconsistent = $false
        try {
            $verifyOut = & winmgmt.exe /verifyrepository 2>&1 | Out-String
            $verifyOut = $verifyOut.Trim()
            Write-ToolOutput ('winmgmt /verifyrepository: {0}' -f $verifyOut) -Level Info
            if ($verifyOut -match 'inconsistent') {
                $verifyInconsistent = $true
                Write-ToolOutput 'WMI repository verdict: INCONSISTENT' -Level Warning
            } elseif ($verifyOut -match 'consistent') {
                Write-ToolOutput 'WMI repository verdict: consistent' -Level Detail
            } else {
                Write-ToolOutput 'WMI repository verdict: unrecognized output' -Level Warning
            }
        } catch {
            Write-ToolOutput ('winmgmt /verifyrepository could not be run: {0}' -f $_.Exception.Message) -Level Warning
        }

        # --- Report: live CIM smoke query ---
        $cimOk = $false
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $cimOk = $true
            Write-ToolOutput ('CIM smoke query (Win32_OperatingSystem): SUCCESS - {0}' -f $os.Caption) -Level Detail
        } catch {
            Write-ToolOutput ('CIM smoke query (Win32_OperatingSystem): FAILED - {0}' -f $_.Exception.Message) -Level Warning
        }

        # --- Report: recent WinMgmt-related Application event log errors ---
        Write-ToolOutput 'Recent WinMgmt/WMI Application log entries (last 7 days, up to 10):' -Level Info
        try {
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop |
                Where-Object { $_.ProviderName -match 'WinMgmt|WMI' } |
                Select-Object -First 10)
            if ($events.Count -eq 0) {
                Write-ToolOutput '  None found.' -Level Detail
            } else {
                foreach ($e in $events) {
                    $firstLine = ($e.Message -split "`n")[0]
                    Write-ToolOutput ('  [{0}] {1} (EventID {2}): {3}' -f $e.TimeCreated, $e.ProviderName, $e.Id, $firstLine) -Level Warning
                }
            }
        } catch {
            Write-ToolOutput ('  Could not query Application event log: {0}' -f $_.Exception.Message) -Level Warning
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'WMI repository action' `
            -Choices @('None', 'VerifyRepository', 'RestartWmiService', 'SalvageRepository', 'ResetRepository') `
            -Default 'None' -Silent:$Silent

        switch ($action) {

            'VerifyRepository' {
                Write-ToolOutput 'Re-running winmgmt /verifyrepository...' -Level Info
                try {
                    $out = (& winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()
                    Write-ToolOutput $out -Level Detail
                    if ($out -match 'inconsistent') {
                        Complete-ToolRun $run -Status Warning -Summary 'WMI repository verified as INCONSISTENT'
                    } elseif ($out -match 'consistent') {
                        Complete-ToolRun $run -Status Success -Summary 'WMI repository verified as consistent'
                    } else {
                        Complete-ToolRun $run -Status Warning -Summary 'WMI repository verify returned an unrecognized result'
                    }
                } catch {
                    Complete-ToolRun $run -Status Failed -Summary ('Verify failed: {0}' -f $_.Exception.Message)
                }
            }

            'RestartWmiService' {
                $dependents = @(Get-Service -Name 'winmgmt' -DependentServices -ErrorAction SilentlyContinue)
                if ($dependents.Count -gt 0) {
                    Write-ToolOutput ('{0} dependent service(s) will be stopped along with WMI:' -f $dependents.Count) -Level Warning
                    foreach ($d in $dependents) {
                        Write-ToolOutput ('  {0} ({1}) - current status: {2}' -f $d.DisplayName, $d.Name, $d.Status) -Level Warning
                    }
                } else {
                    Write-ToolOutput 'No dependent services found.' -Level Info
                }

                $confirm = Read-ToolChoice -Prompt 'Restart the WMI service (winmgmt) and its dependents now?' `
                    -Choices @('Yes', 'No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'User declined WMI service restart'
                    return
                }

                $wasRunning = @($dependents | Where-Object { $_.Status -eq 'Running' })
                try {
                    Write-ToolOutput 'Stopping winmgmt service (and running dependents)...' -Level Info
                    Stop-Service -Name 'winmgmt' -Force -ErrorAction Stop
                    Write-ToolOutput 'Starting winmgmt service...' -Level Info
                    Start-Service -Name 'winmgmt' -ErrorAction Stop

                    foreach ($d in $wasRunning) {
                        try {
                            Start-Service -Name $d.Name -ErrorAction Stop
                            Write-ToolOutput ('Restarted dependent service: {0}' -f $d.Name) -Level Info
                        } catch {
                            Write-ToolOutput ('Could not restart dependent service {0}: {1}' -f $d.Name, $_.Exception.Message) -Level Warning
                        }
                    }

                    $final = Get-Service -Name 'winmgmt'
                    Complete-ToolRun $run -Status Success -Summary ('WMI service restarted (Status={0}); {1} dependent service(s) restarted' -f $final.Status, $wasRunning.Count)
                } catch {
                    Complete-ToolRun $run -Status Failed -Summary ('WMI service restart failed: {0}' -f $_.Exception.Message)
                }
            }

            'SalvageRepository' {
                Write-ToolOutput 'Running winmgmt /salvagerepository...' -Level Info
                try {
                    $out = (& winmgmt.exe /salvagerepository 2>&1 | Out-String).Trim()
                    Write-ToolOutput $out -Level Detail
                    Complete-ToolRun $run -Status Success -Summary 'WMI repository salvage completed'
                } catch {
                    Complete-ToolRun $run -Status Failed -Summary ('Salvage failed: {0}' -f $_.Exception.Message)
                }
            }

            'ResetRepository' {
                Write-ToolOutput 'WARNING: Resetting the WMI repository rebuilds it from scratch (winmgmt /resetrepository).' -Level Warning
                Write-ToolOutput 'WARNING: SCCM, monitoring agents, and other WMI-dependent management agents may stop reporting and need re-registration/repair after this.' -Level Warning
                $gate = Read-ToolChoice -Prompt 'Type RESET to permanently reset the WMI repository, or Cancel to abort' `
                    -Choices @('RESET', 'Cancel') -Default 'Cancel' -Silent:$Silent
                if ($gate -ne 'RESET') {
                    Complete-ToolRun $run -Status Skipped -Summary 'User declined WMI repository reset'
                    return
                }
                try {
                    Write-ToolOutput 'Running winmgmt /resetrepository...' -Level Info
                    $out = (& winmgmt.exe /resetrepository 2>&1 | Out-String).Trim()
                    Write-ToolOutput $out -Level Detail
                    Complete-ToolRun $run -Status Success -Summary 'WMI repository reset; re-register/repair SCCM and other management agents if they stop reporting'
                } catch {
                    Complete-ToolRun $run -Status Failed -Summary ('Reset failed: {0}' -f $_.Exception.Message)
                }
            }

            default {
                if (-not $cimOk -or $verifyInconsistent) {
                    Complete-ToolRun $run -Status Warning -Summary 'WMI health issue detected (see report above); no action taken'
                } else {
                    Complete-ToolRun $run -Status Success -Summary 'WMI healthy (service running, repository consistent, CIM query succeeded); no action taken'
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
