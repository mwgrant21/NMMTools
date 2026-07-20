function Repair-WmiRepository {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    # --- Private helpers (nested: not registry-scanned as tools) ---

    function Invoke-WmiVerifyRepositoryCheck {
        # Runs winmgmt /verifyrepository once, captures its exit code alongside the
        # parsed text verdict, and returns both so no caller has to duplicate the
        # native-exe-plus-parse dance (house pattern: see Invoke-DISMRepair.ps1).
        # Verdict is one of: Inconsistent | Consistent | Unrecognized | NotRun.
        # NOTE: check 'inconsistent' before 'consistent' - 'consistent' is a
        # substring of 'inconsistent', so the order is deliberate and load-bearing.
        $result = [PSCustomObject]@{
            Output   = ''
            ExitCode = $null
            Ran      = $false
            Verdict  = 'NotRun'
        }
        try {
            $out = (& winmgmt.exe /verifyrepository 2>&1 | Out-String)
            $result.ExitCode = $LASTEXITCODE
            $result.Output = $out.Trim()
            $result.Ran = $true
            if ($result.Output -match 'inconsistent') {
                $result.Verdict = 'Inconsistent'
            } elseif ($result.Output -match 'consistent') {
                $result.Verdict = 'Consistent'
            } else {
                $result.Verdict = 'Unrecognized'
            }
        } catch {
            $result.Output = $_.Exception.Message
        }
        return $result
    }

    function Invoke-WmiDependentRestart {
        # Attempts Start-Service on each supplied service, confirms it actually
        # reached Running (not just that Start-Service didn't throw), and reports
        # which ones are confirmed restarted vs. which are still down.
        param([Parameter(Mandatory)][AllowNull()][array]$Services)
        $restarted = New-Object System.Collections.ArrayList
        $failed = New-Object System.Collections.ArrayList
        foreach ($svc in @($Services)) {
            try {
                Start-Service -Name $svc.Name -ErrorAction Stop
                $cur = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                if ($cur -and $cur.Status -eq 'Running') {
                    [void]$restarted.Add($svc.Name)
                    Write-ToolOutput ('Restarted dependent service: {0}' -f $svc.Name) -Level Info
                } else {
                    [void]$failed.Add($svc.Name)
                    Write-ToolOutput ('Dependent service {0} did not reach Running state after Start-Service' -f $svc.Name) -Level Warning
                }
            } catch {
                [void]$failed.Add($svc.Name)
                Write-ToolOutput ('Could not restart dependent service {0}: {1}' -f $svc.Name, $_.Exception.Message) -Level Warning
            }
        }
        return [PSCustomObject]@{ Restarted = @($restarted); Failed = @($failed) }
    }

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
        $verifyResult = Invoke-WmiVerifyRepositoryCheck
        $verifyInconsistent = $false
        $verifyConfirmedOk = $false
        if ($verifyResult.Ran) {
            Write-ToolOutput ('winmgmt /verifyrepository: {0}' -f $verifyResult.Output) -Level Info
            if ($verifyResult.ExitCode -ne 0) {
                Write-ToolOutput ('winmgmt /verifyrepository exited {0}' -f $verifyResult.ExitCode) -Level Warning
            }
            switch ($verifyResult.Verdict) {
                'Inconsistent' {
                    $verifyInconsistent = $true
                    Write-ToolOutput 'WMI repository verdict: INCONSISTENT' -Level Warning
                }
                'Consistent' {
                    if ($verifyResult.ExitCode -eq 0) {
                        $verifyConfirmedOk = $true
                        Write-ToolOutput 'WMI repository verdict: consistent' -Level Detail
                    } else {
                        Write-ToolOutput ('WMI repository reported consistent but winmgmt exited {0}' -f $verifyResult.ExitCode) -Level Warning
                    }
                }
                default {
                    Write-ToolOutput 'WMI repository verdict: unrecognized output' -Level Warning
                }
            }
        } else {
            Write-ToolOutput ('winmgmt /verifyrepository could not be run: {0}' -f $verifyResult.Output) -Level Warning
        }
        # Tri-state: verifyInconsistent (confirmed bad), verifyConfirmedOk (confirmed
        # good), or neither (could not verify - never claim "consistent" for this case).
        $verifyUnconfirmed = (-not $verifyInconsistent -and -not $verifyConfirmedOk)

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
            # MaxEvents bounds the raw log scan (newest 500 matching LogName/StartTime)
            # before the ProviderName regex filter runs, instead of walking the whole
            # 7-day Application log. The regex stays broader than an exact ProviderName
            # match so near-miss provider names (e.g. Microsoft-Windows-WMI-Activity)
            # are still caught.
            $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 500 -ErrorAction Stop |
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
                $result = Invoke-WmiVerifyRepositoryCheck
                if (-not $result.Ran) {
                    Complete-ToolRun $run -Status Failed -Summary ('Verify failed: {0}' -f $result.Output)
                    return
                }
                Write-ToolOutput $result.Output -Level Detail
                if ($result.ExitCode -ne 0) {
                    Write-ToolOutput ('winmgmt /verifyrepository exited {0}' -f $result.ExitCode) -Level Warning
                }
                switch ($result.Verdict) {
                    'Inconsistent' {
                        Complete-ToolRun $run -Status Warning -Summary ('WMI repository verified as INCONSISTENT (exit code {0})' -f $result.ExitCode)
                    }
                    'Consistent' {
                        if ($result.ExitCode -eq 0) {
                            Complete-ToolRun $run -Status Success -Summary ('WMI repository verified as consistent (exit code {0})' -f $result.ExitCode)
                        } else {
                            Complete-ToolRun $run -Status Warning -Summary ('WMI repository reported consistent but winmgmt exited {0}' -f $result.ExitCode)
                        }
                    }
                    default {
                        Complete-ToolRun $run -Status Warning -Summary ('WMI repository verify returned an unrecognized result (exit code {0})' -f $result.ExitCode)
                    }
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
                $depResult = [PSCustomObject]@{ Restarted = @(); Failed = @() }

                try {
                    Write-ToolOutput 'Stopping winmgmt service (and running dependents)...' -Level Info
                    Stop-Service -Name 'winmgmt' -Force -ErrorAction Stop

                    Write-ToolOutput 'Starting winmgmt service...' -Level Info
                    try {
                        Start-Service -Name 'winmgmt' -ErrorAction Stop
                    } catch {
                        Write-ToolOutput ('winmgmt failed to start: {0}; retrying once...' -f $_.Exception.Message) -Level Warning
                        try {
                            Start-Service -Name 'winmgmt' -ErrorAction Stop
                        } catch {
                            Write-ToolOutput ('winmgmt retry start also failed: {0}' -f $_.Exception.Message) -Level Warning
                        }
                    }

                    $depResult = Invoke-WmiDependentRestart -Services $wasRunning
                } catch {
                    # winmgmt did not stop cleanly. Do not strand every dependent on a
                    # bare exception - still attempt to bring winmgmt back up and
                    # restart whatever was running before we touched anything.
                    Write-ToolOutput ('Stopping winmgmt failed: {0}' -f $_.Exception.Message) -Level Warning
                    Write-ToolOutput 'Still attempting to bring winmgmt and its dependents back up...' -Level Info
                    try {
                        Start-Service -Name 'winmgmt' -ErrorAction Stop
                    } catch {
                        Write-ToolOutput ('Attempt to start winmgmt after stop failure also failed: {0}' -f $_.Exception.Message) -Level Warning
                    }
                    $depResult = Invoke-WmiDependentRestart -Services $wasRunning
                }

                # Residual-state check: runs regardless of which path above executed,
                # so a failed restart is never silently reported as healthy.
                $restartedCount = @($depResult.Restarted).Count
                $winmgmtFinal = Get-Service -Name 'winmgmt' -ErrorAction SilentlyContinue
                $finalStatusText = if ($winmgmtFinal) { $winmgmtFinal.Status } else { 'Unknown' }
                $winmgmtDown = (-not $winmgmtFinal -or $winmgmtFinal.Status -ne 'Running')
                $depsDown = @($depResult.Failed)

                if ($winmgmtDown) {
                    $downList = (@('winmgmt') + $depsDown) -join ', '
                    Complete-ToolRun $run -Status Failed -Summary ('WMI service restart failed (winmgmt Status={0}); {1} of {2} dependent service(s) restarted; still down: {3}' -f $finalStatusText, $restartedCount, $wasRunning.Count, $downList)
                } elseif ($depsDown.Count -gt 0) {
                    Complete-ToolRun $run -Status Warning -Summary ('WMI service restarted (Status={0}) but {1} of {2} dependent service(s) failed to restart: {3}' -f $finalStatusText, $depsDown.Count, $wasRunning.Count, ($depsDown -join ', '))
                } else {
                    Complete-ToolRun $run -Status Success -Summary ('WMI service restarted (Status={0}); {1} of {2} dependent service(s) restarted' -f $finalStatusText, $restartedCount, $wasRunning.Count)
                }
            }

            'SalvageRepository' {
                Write-ToolOutput 'Running winmgmt /salvagerepository...' -Level Info
                try {
                    $out = (& winmgmt.exe /salvagerepository 2>&1 | Out-String).Trim()
                    $exitCode = $LASTEXITCODE
                    Write-ToolOutput $out -Level Detail
                    if ($exitCode -eq 0) {
                        Complete-ToolRun $run -Status Success -Summary ('WMI repository salvage completed (exit code {0})' -f $exitCode)
                    } else {
                        Complete-ToolRun $run -Status Failed -Summary ('WMI repository salvage failed (exit code {0})' -f $exitCode)
                    }
                } catch {
                    Complete-ToolRun $run -Status Failed -Summary ('Salvage failed: {0}' -f $_.Exception.Message)
                }
            }

            'ResetRepository' {
                Write-ToolOutput 'WARNING: Resetting the WMI repository rebuilds it from scratch (winmgmt /resetrepository).' -Level Warning
                Write-ToolOutput 'WARNING: SCCM, monitoring agents, and other WMI-dependent management agents may stop reporting and need re-registration/repair after this.' -Level Warning

                # Exact-match typed confirm: Read-ToolChoice prefix-matches its
                # -Choices (a single 'r' would fire the reset), so this irreversible
                # gate uses a direct, case-sensitive Read-Host instead. Read-Host is
                # reached only from this interactive-only action (the action menu
                # above defaults to None, and -Silent auto-selects None before this
                # point is ever reached), but the try/catch still fails safe to
                # Cancel if a non-interactive host somehow gets here.
                try {
                    $typed = Read-Host 'Type RESET to permanently reset the WMI repository, or press Enter to cancel'
                } catch {
                    $typed = $null
                }
                if ($typed -cne 'RESET') {
                    Complete-ToolRun $run -Status Skipped -Summary 'User declined WMI repository reset'
                    return
                }

                try {
                    Write-ToolOutput 'Running winmgmt /resetrepository...' -Level Info
                    $out = (& winmgmt.exe /resetrepository 2>&1 | Out-String).Trim()
                    $exitCode = $LASTEXITCODE
                    Write-ToolOutput $out -Level Detail
                    if ($exitCode -eq 0) {
                        Complete-ToolRun $run -Status Success -Summary ('WMI repository reset (exit code {0}); re-register/repair SCCM and other management agents if they stop reporting' -f $exitCode)
                    } else {
                        Complete-ToolRun $run -Status Failed -Summary ('WMI repository reset failed (exit code {0})' -f $exitCode)
                    }
                } catch {
                    Complete-ToolRun $run -Status Failed -Summary ('Reset failed: {0}' -f $_.Exception.Message)
                }
            }

            default {
                if (-not $cimOk -or $verifyInconsistent) {
                    Complete-ToolRun $run -Status Warning -Summary 'WMI health issue detected (see report above); no action taken'
                } elseif ($verifyUnconfirmed) {
                    Complete-ToolRun $run -Status Warning -Summary 'WMI repository consistency could not be confirmed (see report above); no action taken'
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
