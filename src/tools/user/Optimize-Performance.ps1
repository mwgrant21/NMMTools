function Optimize-Performance {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'perf-optimizer'

        # The report below is machine-wide (CPU/RAM/processes), but three of the
        # four actions touch per-user state: the user TEMP folder, the visual
        # effects key, and a Settings page that opens in the calling session.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # --- Report (read-only) ---
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $totalRamMB = 0
        $freeRamMB = 0
        if ($os) {
            $totalRamMB = [math]::Round(($os.TotalVisibleMemorySize / 1KB), 0)
            $freeRamMB = [math]::Round(($os.FreePhysicalMemory / 1KB), 0)
        }
        $usedPct = 0
        if ($totalRamMB -gt 0) { $usedPct = [math]::Round((($totalRamMB - $freeRamMB) / $totalRamMB) * 100, 0) }
        if ($cpu) { Write-ToolOutput ('CPU: {0}' -f $cpu.Name) -Level Info }
        $load = $null
        try { $load = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue, 0) } catch { }
        if ($null -ne $load) { Write-ToolOutput ('CPU load: {0}%' -f $load) -Level Detail }
        if ($os) { Write-ToolOutput ('RAM: {0} of {1} MB used ({2}%)' -f ($totalRamMB - $freeRamMB), $totalRamMB, $usedPct) -Level Detail }

        Write-ToolOutput 'Top CPU processes:' -Level Detail
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
            $c = 0
            if ($_.CPU) { $c = [math]::Round($_.CPU, 0) }
            Write-ToolOutput ('  {0}: {1}s CPU' -f $_.Name, $c) -Level Detail
        }
        Write-ToolOutput 'Top memory processes:' -Level Detail
        Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 5 | ForEach-Object {
            Write-ToolOutput ('  {0}: {1} MB' -f $_.Name, [math]::Round($_.WorkingSet / 1MB, 0)) -Level Detail
        }
        $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
        Write-ToolOutput ('Startup programs: {0}  (Run-key/Startup-folder entries; manage via startup-programs tool 16 / Task Manager)' -f $startup.Count) -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Performance action' `
            -Choices @('None','OpenStartupManager','ClearTempCaches','SetPerformanceVisualEffects','OptimizeVirtualMemory') -Default 'None' -Silent:$Silent

        switch ($action) {

            'OpenStartupManager' {
                # ms-settings: opens in the CALLING session. From an elevated
                # session the window appears on the technician's desktop, not
                # the user's, and shows the technician's startup apps.
                if ($ctx.IsRedirected) {
                    Write-ToolOutput ('Startup Apps settings would open as {0} and show their startup entries, not {1}. Ask the user to open Settings > Apps > Startup.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Warning
                    Complete-ToolRun $run -Status Skipped -Summary 'Startup Apps settings not opened - would show the wrong account'
                } else {
                    Start-Process 'ms-settings:startupapps' -ErrorAction SilentlyContinue
                    Write-ToolOutput 'Startup Apps settings opened; disable unneeded entries there.' -Level Info
                    Complete-ToolRun $run -Status Success -Summary 'Opened Startup Apps settings'
                }
            }

            'ClearTempCaches' {
                $confirm = Read-ToolChoice -Prompt 'Clear the user and Windows TEMP folders?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearTempCaches cancelled'
                } elseif (-not $ctx.Resolved) {
                    Complete-ToolRun $run -Status Failed `
                        -Summary ('Cannot clear the user TEMP folder - {0}. Nothing was changed.' -f $ctx.Reason)
                } else {
                    $freed = [int64]0
                    # Windows\Temp is machine-wide; the first path is per-user.
                    foreach ($tp in @((Join-Path $ctx.LocalAppData 'Temp'), (Join-Path $env:SystemRoot 'Temp'))) {
                        if ($tp -and (Test-Path -LiteralPath $tp)) {
                            $before = [int64]0
                            try { $s = (Get-ChildItem -LiteralPath $tp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if ($s) { $before = [int64]$s } } catch { }
                            # This loop mixes a per-user Temp with the machine-wide
                            # %SystemRoot%\Temp. Only the former is inside a tree the
                            # standard user controls, so only it needs the containment
                            # gate; the containment helper would (correctly) refuse
                            # the machine path for being outside the profile.
                            if ($tp.StartsWith($ctx.LocalAppData, [System.StringComparison]::OrdinalIgnoreCase)) {
                                [void](Remove-UserPathContent -Context $ctx -Path $tp)
                            } else {
                                Get-ChildItem -LiteralPath $tp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            $after = [int64]0
                            try { $s = (Get-ChildItem -LiteralPath $tp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if ($s) { $after = [int64]$s } } catch { }
                            $freed += [math]::Max([int64]0, $before - $after)
                        }
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Cleared TEMP; freed {0} MB' -f [math]::Round($freed / 1MB, 1))
                }
            }

            'SetPerformanceVisualEffects' {
                $confirm = Read-ToolChoice -Prompt 'Set visual effects to best performance (current user)?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'SetPerformanceVisualEffects cancelled'
                } elseif (-not $ctx.Resolved) {
                    Complete-ToolRun $run -Status Failed `
                        -Summary ('Cannot set visual effects - {0}. Nothing was changed.' -f $ctx.Reason)
                } else {
                    $vfx = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
                    try {
                        if (-not (Test-Path -LiteralPath $vfx)) { New-Item -LiteralPath $vfx -Force -ErrorAction Stop | Out-Null }
                        Set-ItemProperty -LiteralPath $vfx -Name 'VisualFXSetting' -Value 2 -Type DWord -ErrorAction Stop
                        Write-ToolOutput 'Visual effects set to best performance; sign out/in or restart Explorer to apply fully.' -Level Info
                        Complete-ToolRun $run -Status Success -Summary 'Visual effects set to best performance (current user)'
                    } catch {
                        Complete-ToolRun $run -Status Warning -Summary ('Could not set visual effects: {0}' -f $_.Exception.Message)
                    }
                }
            }

            'OptimizeVirtualMemory' {
                $confirm = Read-ToolChoice -Prompt 'Set the page file to system-managed (recommended)?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'OptimizeVirtualMemory cancelled'
                } else {
                    try {
                        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                        if ($cs.AutomaticManagedPagefile) {
                            Complete-ToolRun $run -Status Success -Summary 'Page file already system-managed (no change)'
                        } else {
                            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
                            Complete-ToolRun $run -Status Success -Summary 'Page file set to system-managed; reboot to apply'
                        }
                    } catch {
                        Complete-ToolRun $run -Status Warning -Summary ('Could not set page file to system-managed: {0}' -f $_.Exception.Message)
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Performance reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
