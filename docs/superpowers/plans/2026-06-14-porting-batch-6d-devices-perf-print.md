# Porting Batch 6D: Devices / Performance / Print Tools - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 tools 52/53/56 as three new report-then-action tools (Category 'User'), fold tool 98 into the printer tool, and fold tool 77 into the existing camera tool.

**Architecture:** Three new self-contained tools plus a modification to the shipped `Repair-TeamsCamera.ps1` (add a ReinstallDriver action + rename its registry Name/Tags/Description). Report-then-action with safe `None` default; destructive sub-actions gated.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs\superpowers\specs\2026-06-14-batch-6d-devices-perf-print-design.md`.

**v8 reference (READ-ONLY):** `C:\Users\IT\Desktop\NMMTools.ps1` - `Repair-PrinterIssues` L5925, `Optimize-Performance` L6242, `Repair-AudioAdvanced` L6990, `Repair-WebcamDriver` L9237, `Reset-PrintSpooler` L11550.

---

## Standing rules (carried from batches 1-6)

- PS 5.1: no ternary / `??` / `&&`; never assign `$input`/`$matches`/`$profile`. **ASCII-only source** (encoding test fails build), UTF-8 BOM + trailing newline.
- Tools use `Write-ToolOutput` / `Read-ToolChoice` only - never `Write-Host`/`Read-Host` (v8's `Show-GUIConfirm` becomes `Read-ToolChoice`). Native reads (`Get-Printer`, `Get-Service`, `Get-CimInstance`, `pnputil`) allowed.
- Every tool function: approved verb (Repair/Optimize - both approved), `[switch]$Silent`, calls `New-ToolRun` + `Complete-ToolRun`, `New-ToolRun -Id` literal == registry Id.
- `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`.
- One tool file per registered function in `src\tools\user\`; one registry entry each.

## Registry entries (added/edited per task)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable |
|---|---|---|---|---|---|---|---|
| printer-repair | 52 | Printer Troubleshooter | Repair-PrinterIssues | User | $true | Modifies | $true |
| perf-optimizer | 53 | Performance Optimizer | Optimize-Performance | User | $true | Modifies | $true |
| audio-repair | 56 | Audio Troubleshooter | Repair-AudioAdvanced | User | $true | Modifies | $true |
| teams-camera-repair (EDIT) | 84 | Camera and Mic Repair | Repair-TeamsCamera | User | $true | Modifies | $true |

Tool count **77 -> 80** (3 new; the 77 fold-in is an action add). 98 -> consolidated into 52; 77 -> consolidated into 84.

## Smoke safety (non-elevated dev session)

- `printer-repair -Silent`, `perf-optimizer -Silent`, `audio-repair -Silent` -> RequiresAdmin -> dispatcher refuses (Refused / exit 1).
- The modified `teams-camera-repair -Silent` -> still Refused (RequiresAdmin).
- NEVER run the destructive actions in dev. Verify by reading + the admin refusals.

---

## Setup: create the batch branch

- [ ] **Step 1: Branch off master**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" checkout -b port/batch-6d-devices-perf-print
```
Expected: `Switched to a new branch 'port/batch-6d-devices-perf-print'`

---

## Task 1: printer-repair (52 + 98)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-PrinterIssues.ps1`

- [ ] **Step 1: Append the registry entry** (LAST element of the `Tools = @( ... )` array, before its closing `)`):
```powershell
        @{
            Id            = 'printer-repair'
            LegacyId      = '52'
            Name          = 'Printer Troubleshooter'
            Category      = 'User'
            Function      = 'Repair-PrinterIssues'
            Description   = 'Report printers, spooler status, and stuck jobs; restart the spooler, clear jobs, clear the spool folder (deep reset), remove offline/ghost printers, or full reset'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('printer','spooler','print','queue')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-PrinterIssues.ps1`** with EXACTLY this content:
```powershell
function Repair-PrinterIssues {
    [CmdletBinding()]
    param([switch]$Silent)

    # v8 tool-98 deep reset: stop Spooler -> clear spool\PRINTERS contents -> start Spooler.
    function Invoke-SpoolerFolderReset {
        Stop-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $spoolDir = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
        $files = 0
        if (Test-Path -LiteralPath $spoolDir) {
            $items = @(Get-ChildItem -LiteralPath $spoolDir -Force -ErrorAction SilentlyContinue)
            $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            $files = $items.Count
        }
        Start-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $now = (Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue).Status
        if (-not $now) { $now = 'Unknown' }
        if ($now -eq 'Running') {
            return @{ Status = 'Success'; Text = ('spool folder cleared ({0} file(s)); Spooler Running' -f $files) }
        } else {
            return @{ Status = 'Warning'; Text = ('spool folder cleared ({0} file(s)) but Spooler status is {1}' -f $files, $now) }
        }
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'printer-repair'

        # --- Report ---
        $printers = @(Get-Printer -ErrorAction SilentlyContinue)
        if ($printers.Count -gt 0) {
            Write-ToolOutput ('Installed printers: {0}' -f $printers.Count) -Level Info
            foreach ($pr in $printers) {
                Write-ToolOutput ('  {0}  [{1}]  port={2}' -f $pr.Name, $pr.PrinterStatus, $pr.PortName) -Level Detail
            }
        } else {
            Write-ToolOutput 'No printers found on this system.' -Level Warning
        }
        $spooler = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        if ($spooler) {
            Write-ToolOutput ('Print Spooler: {0} (StartType {1})' -f $spooler.Status, $spooler.StartType) -Level Info
        }
        $jobs = @(Get-PrintJob -PrinterName * -ErrorAction SilentlyContinue)
        Write-ToolOutput ('Queued print jobs: {0}' -f $jobs.Count) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Printer action' `
            -Choices @('None','RestartSpooler','ClearJobs','ClearSpoolFolder','RemoveGhostPrinters','FullReset') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartSpooler' {
                Restart-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                $now = (Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue).Status
                if (-not $now) { $now = 'Unknown' }
                if ($now -eq 'Running') {
                    Complete-ToolRun $run -Status Success -Summary 'Print Spooler restarted (Running)'
                } else {
                    Complete-ToolRun $run -Status Warning -Summary ('Spooler restart left status {0}' -f $now)
                }
            }

            'ClearJobs' {
                $confirm = Read-ToolChoice -Prompt 'Cancel all queued print jobs?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearJobs cancelled'
                } else {
                    $n = 0
                    foreach ($j in @(Get-PrintJob -PrinterName * -ErrorAction SilentlyContinue)) {
                        Remove-PrintJob -InputObject $j -ErrorAction SilentlyContinue
                        $n++
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Cancelled {0} print job(s)' -f $n)
                }
            }

            'ClearSpoolFolder' {
                $confirm = Read-ToolChoice -Prompt 'Stop the Spooler, clear the spool folder, and restart it?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearSpoolFolder cancelled'
                } else {
                    $res = Invoke-SpoolerFolderReset
                    Complete-ToolRun $run -Status $res.Status -Summary $res.Text
                }
            }

            'RemoveGhostPrinters' {
                $ghosts = @($printers | Where-Object { $_.PrinterStatus -eq 'Offline' -or $_.PrinterStatus -eq 'Error' })
                if ($ghosts.Count -eq 0) {
                    Complete-ToolRun $run -Status Success -Summary 'No offline/error printers to remove'
                } else {
                    Write-ToolOutput ('Will remove: {0}' -f (($ghosts | ForEach-Object { $_.Name }) -join ', ')) -Level Detail
                    $confirm = Read-ToolChoice -Prompt ('Remove {0} offline/error printer(s)?' -f $ghosts.Count) -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                    if ($confirm -ne 'Yes') {
                        Complete-ToolRun $run -Status Skipped -Summary 'RemoveGhostPrinters cancelled'
                    } else {
                        $n = 0
                        foreach ($g in $ghosts) {
                            Remove-Printer -Name $g.Name -ErrorAction SilentlyContinue
                            $n++
                        }
                        Complete-ToolRun $run -Status Success -Summary ('Removed {0} offline/error printer(s)' -f $n)
                    }
                }
            }

            'FullReset' {
                $confirm = Read-ToolChoice -Prompt 'Full reset: stop Spooler, clear the spool folder, restart Spooler?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'FullReset cancelled'
                } else {
                    $res = Invoke-SpoolerFolderReset
                    Complete-ToolRun $run -Status $res.Status -Summary ('Full printer reset: {0}' -f $res.Text)
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('{0} printer(s) reported; no action taken' -f $printers.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite**
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: `Built ...`; suite `Failed: 0` (71 passed). Verb `Repair` approved; Id matches. (The nested `Invoke-SpoolerFolderReset` is fine - registry/template tests enumerate top-level tool functions only.)

- [ ] **Step 4: Smoke the silent refusal (RequiresAdmin)**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $false
. "$r\src\tools\user\Repair-PrinterIssues.ps1"
$tool = Resolve-NmmTool -Query 'printer-repair'
Write-Output ("RESULT: " + (Invoke-NmmTool -Tool $tool -Silent))
```
Expected: `RESULT: Refused`. Paste that line. Do NOT run the actions.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-PrinterIssues.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-PrinterIssues.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port batch 6d.1 (printer-repair, folds tool 98 spooler reset)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 2: perf-optimizer (53)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Optimize-Performance.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'perf-optimizer'
            LegacyId      = '53'
            Name          = 'Performance Optimizer'
            Category      = 'User'
            Function      = 'Optimize-Performance'
            Description   = 'Report CPU/RAM and top processes, then open startup apps, clear TEMP, set visual effects to performance, or set the page file to system-managed (see also tools 4/7/11/16)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('performance','startup','pagefile','optimize')
        }
```

- [ ] **Step 2: Create `src\tools\user\Optimize-Performance.ps1`** with EXACTLY this content:
```powershell
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
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`. Verb `Optimize` is an approved PowerShell verb.

- [ ] **Step 4: Smoke the silent refusal**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $false
. "$r\src\tools\user\Optimize-Performance.ps1"
$tool = Resolve-NmmTool -Query 'perf-optimizer'
Write-Output ("RESULT: " + (Invoke-NmmTool -Tool $tool -Silent))
```
Expected: `RESULT: Refused`. Paste that line.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Optimize-Performance.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Optimize-Performance.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port batch 6d.2 (perf-optimizer)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 3: audio-repair (56)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-AudioAdvanced.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'audio-repair'
            LegacyId      = '56'
            Name          = 'Audio Troubleshooter'
            Category      = 'User'
            Function      = 'Repair-AudioAdvanced'
            Description   = 'Report audio devices and services, then restart the audio services, cycle the audio devices, or launch the Windows audio troubleshooter'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('audio','sound','playback','services')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-AudioAdvanced.ps1`** with EXACTLY this content:
```powershell
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
                    Stop-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
                    Stop-Service -Name 'AudioEndpointBuilder' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $cycled = 0
                    foreach ($dev in @(Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })) {
                        try {
                            Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 1
                            Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                            $cycled++
                        } catch { }
                    }
                    Start-Service -Name 'AudioEndpointBuilder' -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    Start-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
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
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`. Verb `Repair` approved.

- [ ] **Step 4: Smoke the silent refusal**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $false
. "$r\src\tools\user\Repair-AudioAdvanced.ps1"
$tool = Resolve-NmmTool -Query 'audio-repair'
Write-Output ("RESULT: " + (Invoke-NmmTool -Tool $tool -Silent))
```
Expected: `RESULT: Refused`. Paste that line.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-AudioAdvanced.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-AudioAdvanced.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port batch 6d.3 (audio-repair)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 4: Fold tool 77 into the existing camera tool (MODIFY)

**Files:**
- Modify: `src\registry\tools.psd1` (EDIT the existing LegacyId-84 entry)
- Modify: `src\tools\user\Repair-TeamsCamera.ps1` (add a ReinstallDriver action; broaden the action prompt)

This is a MODIFICATION of a shipped tool, not a new file. Keep the `Id` (`teams-camera-repair`) and `Function` (`Repair-TeamsCamera`) UNCHANGED so the New-ToolRun-Id<->registry AST test still passes; change only the Name/Tags/Description and add one action.

- [ ] **Step 1: Edit the existing registry entry.** Find the entry with `Id = 'teams-camera-repair'` in `src\registry\tools.psd1` and replace its `Name`, `Description`, and `Tags` lines (leave Id/LegacyId/Category/Function/RequiresAdmin/SilentCapable/Risk unchanged). The whole entry should become:
```powershell
        @{
            Id            = 'teams-camera-repair'
            LegacyId      = '84'
            Name          = 'Camera and Mic Repair'
            Category      = 'User'
            Function      = 'Repair-TeamsCamera'
            Description   = 'Fix camera/mic: set Windows privacy access to Allow (FixPermissions), reset the media stack (ResetMediaStack - close hogging apps, clear cache, cycle the device), or remove and reinstall the camera driver (ReinstallDriver - reboot required)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','camera','microphone','media','webcam','driver')
        }
```

- [ ] **Step 2: Broaden the action menu** in `src\tools\user\Repair-TeamsCamera.ps1`. Find:
```powershell
        $action = Read-ToolChoice -Prompt 'Teams camera action' `
            -Choices @('None','FixPermissions','ResetMediaStack') -Default 'None' -Silent:$Silent
```
Replace with (renamed prompt + added choice):
```powershell
        $action = Read-ToolChoice -Prompt 'Camera / mic action' `
            -Choices @('None','FixPermissions','ResetMediaStack','ReinstallDriver') -Default 'None' -Silent:$Silent
```

- [ ] **Step 3: Add the ReinstallDriver action arm.** In the same `switch ($action)`, insert this new arm AFTER the closing `}` of the `'ResetMediaStack'` arm and BEFORE the `default` arm:
```powershell
            'ReinstallDriver' {
                if ($cams.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No camera devices found; nothing to reinstall'
                } else {
                    Write-ToolOutput 'WARNING: this REMOVES the camera driver - a REBOOT is required and the camera is offline until then.' -Level Warning
                    $confirm = Read-ToolChoice -Prompt 'Remove the camera driver(s) and let Windows reinstall on reboot?' `
                        -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                    if ($confirm -ne 'Yes') {
                        Complete-ToolRun $run -Status Skipped -Summary 'ReinstallDriver cancelled'
                    } else {
                        foreach ($p in @('Teams','ms-teams','MSTeams','WebexMeetings','zoom','chrome','msedge','firefox','CameraApp','WindowsCamera')) {
                            Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        }
                        Start-Sleep -Seconds 2
                        $removed = 0
                        foreach ($cam in $cams) {
                            & pnputil.exe /remove-device $cam.InstanceId *>$null
                            if ($LASTEXITCODE -eq 0) {
                                Write-ToolOutput ('  Removed driver: {0}' -f $cam.FriendlyName) -Level Success
                                $removed++
                            } else {
                                Write-ToolOutput ('  Could not remove {0} via pnputil (exit {1}); use Device Manager > Uninstall device' -f $cam.FriendlyName, $LASTEXITCODE) -Level Warning
                            }
                        }
                        try {
                            $session = New-Object -ComObject Microsoft.Update.Session
                            $searcher = $session.CreateUpdateSearcher()
                            $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
                            $camUpd = @($result.Updates | Where-Object { $_.Title -match 'camera|webcam|video|imaging' })
                            if ($camUpd.Count -gt 0) {
                                Write-ToolOutput ('Windows Update has {0} camera driver update(s) pending:' -f $camUpd.Count) -Level Info
                                foreach ($u in $camUpd) { Write-ToolOutput ('  - {0}' -f $u.Title) -Level Detail }
                            } else {
                                Write-ToolOutput 'No pending camera driver updates in Windows Update.' -Level Detail
                            }
                        } catch {
                            Write-ToolOutput 'Could not query Windows Update for driver updates (check Settings manually).' -Level Detail
                        }
                        if ($removed -gt 0) {
                            Complete-ToolRun $run -Status Success -Summary ('Removed {0} camera driver(s); REBOOT to trigger automatic reinstall' -f $removed)
                        } else {
                            Complete-ToolRun $run -Status Warning -Summary 'No camera drivers removed; use Device Manager to uninstall manually'
                        }
                    }
                }
            }
```

- [ ] **Step 4: Build + full suite**
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: `Built ...`; suite `Failed: 0` (71 passed). The Id `teams-camera-repair` is unchanged so the template AST test still passes; the registry Name change is cosmetic.

- [ ] **Step 5: Smoke - the modified tool still refuses non-elevated -Silent, and the new action is wired**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $false
. "$r\src\tools\user\Repair-TeamsCamera.ps1"
$tool = Resolve-NmmTool -Query 'teams-camera-repair'
Write-Output ("NAME: " + $tool.Name)
Write-Output ("RESULT: " + (Invoke-NmmTool -Tool $tool -Silent))
```
Expected: `NAME: Camera and Mic Repair` and `RESULT: Refused`. Paste both lines.

- [ ] **Step 6: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-TeamsCamera.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-TeamsCamera.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: fold tool 77 into camera tool (ReinstallDriver action; rename to Camera and Mic Repair)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 5: Sub-batch 6D close-out

**Files:**
- Modify: `docs\parity-checklist.md`

- [ ] **Step 1: Verify 80 tools and the new rows**
```powershell
$tk = "$env:USERPROFILE\Desktop\NMMToolkit"
$lines = (& "$tk\dist\NMMTools.ps1" -ListTools | Out-String) -split "`r?`n"
$toolRows = $lines | Where-Object { $_ -match '\s(Browser|Cloud|Diagnostics|Laptop|Repair|User)\s+(ReadOnly|Modifies|Disruptive)\s' }
Write-Output ("Total tool rows: {0}" -f $toolRows.Count)
$lines | Where-Object { $_ -match '^(printer-repair|perf-optimizer|audio-repair|teams-camera-repair)\b' }
```
Expected: Total = **80**; the 3 new rows (printer-repair/perf-optimizer/audio-repair = User/Modifies/Admin True) + teams-camera-repair now showing Name `Camera and Mic Repair`. Quote them.

- [ ] **Step 2: Confirm build + full suite are green**
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: Build OK; `Failed: 0`.

- [ ] **Step 3: Update the parity checklist** in `docs\parity-checklist.md`:

(a) Set the ported/consolidated rows:
```markdown
| 52 | Printer Troubleshooter | ported (batch 6d) | printer-repair |
| 53 | Performance Optimizer | ported (batch 6d) | perf-optimizer |
| 56 | Audio Troubleshooter | ported (batch 6d) | audio-repair |
| 77 | Webcam Driver Fix (Soft Reset + Optional Driver Reinstall) | consolidated -> tool 84 (teams-camera-repair) | — |
| 98 | Reset Print Spooler (Deep) | consolidated -> tool 52 (printer-repair) | — |
```
(b) Update the header count line from `77 of ~111 items ported` to `80 of ~111 items ported`, add `, 52, 53, 56` to the ported-items list, and add `77, 98` to the consolidated list.

- [ ] **Step 4: Commit the docs**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add docs/parity-checklist.md
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "docs: batch 6d complete - parity checklist (80/106 ported)"
```

- [ ] **Step 5: Final review + finish the branch**

Review focus: printer-repair's spool-folder clear is scoped to `%SystemRoot%\System32\spool\PRINTERS` contents (never a drive root) and re-queries Spooler status honestly; perf-optimizer's page-file/visual-effects changes are gated + note reboot/relogon, TEMP clear is contents-only and cross-references shipped tools; audio-repair re-queries Audiosrv status; the camera-tool ReinstallDriver is gated (reboot warning) + WU scan is report-only + the Id stayed `teams-camera-repair`. All 4 are admin (silent-refused). 80 tools, 71/71.

Then invoke the **superpowers:finishing-a-development-branch** skill to merge `port/batch-6d-devices-perf-print` to master. **Use a simple single-line `-m` merge message** (here-string mangles git args). Verify the suite on the merged result before deleting the branch.

---

## Self-review (completed by plan author)

- **Spec coverage:** 3 new tools -> Tasks 1-3; tool 98 fold-in -> Task 1 (ClearSpoolFolder/FullReset via Invoke-SpoolerFolderReset); tool 77 fold-in -> Task 4 (ReinstallDriver action + registry rename, Id preserved); perf-optimizer full port + cross-references -> Task 2; 80-tool/parity verify -> Task 5.
- **Placeholder scan:** none - every step has complete code, exact commands, expected output.
- **Type/name consistency:** registry Function names (`Repair-PrinterIssues`, `Optimize-Performance`, `Repair-AudioAdvanced`) match the defined functions and the `New-ToolRun -Id` literals match each registry Id (`printer-repair`, `perf-optimizer`, `audio-repair`). The camera tool keeps Id `teams-camera-repair` / Function `Repair-TeamsCamera` (only Name/Tags/Description + one action change). All new functions use approved verbs (Repair/Optimize) and declare `[switch]$Silent`. The nested `Invoke-SpoolerFolderReset` is not registry-scanned (top-level enumeration only).
