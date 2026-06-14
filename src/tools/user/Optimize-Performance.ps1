function Optimize-Performance {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'perf-optimizer'

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
        Write-ToolOutput ('RAM: {0} of {1} MB used ({2}%)' -f ($totalRamMB - $freeRamMB), $totalRamMB, $usedPct) -Level Detail

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
        Write-ToolOutput ('Startup programs: {0}  (manage via startup-programs tool 16 / Task Manager)' -f $startup.Count) -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Performance action' `
            -Choices @('None','OpenStartupManager','ClearTempCaches','SetPerformanceVisualEffects','OptimizeVirtualMemory') -Default 'None' -Silent:$Silent

        switch ($action) {

            'OpenStartupManager' {
                Start-Process 'ms-settings:startupapps' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Startup Apps settings opened; disable unneeded entries there.' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened Startup Apps settings'
            }

            'ClearTempCaches' {
                $confirm = Read-ToolChoice -Prompt 'Clear the user and Windows TEMP folders?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearTempCaches cancelled'
                } else {
                    $freed = [int64]0
                    foreach ($tp in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'))) {
                        if ($tp -and (Test-Path -LiteralPath $tp)) {
                            $before = [int64]0
                            try { $s = (Get-ChildItem -LiteralPath $tp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if ($s) { $before = [int64]$s } } catch { }
                            Get-ChildItem -LiteralPath $tp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
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
                } else {
                    $vfx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
                    if (-not (Test-Path -LiteralPath $vfx)) { New-Item -LiteralPath $vfx -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -LiteralPath $vfx -Name 'VisualFXSetting' -Value 2 -Type DWord -ErrorAction SilentlyContinue
                    Write-ToolOutput 'Visual effects set to best performance; sign out/in or restart Explorer to apply fully.' -Level Info
                    Complete-ToolRun $run -Status Success -Summary 'Visual effects set to best performance (current user)'
                }
            }

            'OptimizeVirtualMemory' {
                $confirm = Read-ToolChoice -Prompt 'Set the page file to system-managed (recommended)?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'OptimizeVirtualMemory cancelled'
                } else {
                    try {
                        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                        if (-not $cs.AutomaticManagedPagefile) {
                            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
                        }
                        Complete-ToolRun $run -Status Success -Summary 'Page file set to system-managed; reboot to apply'
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
