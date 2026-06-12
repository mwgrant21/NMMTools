# Porting Batch 1: Diagnostics — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the 21 remaining v8 Diagnostics tools into v9 template shape, preceded by the pre-porting hardening from the foundation final review.

**Architecture:** Each tool = one file in `src\tools\diagnostics\` + one registry entry in `src\registry\tools.psd1`, hardened to the standard template (New-ToolRun/Complete-ToolRun, Write-ToolOutput, Read-ToolChoice). v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` is the behavioral reference (READ-ONLY).

**Tech Stack:** Windows PowerShell 5.1, Pester 5.7.1, PSScriptAnalyzer 1.25.0.

**Repo:** `C:\Users\IT\Desktop\NMMToolkit`, work on branch `port/batch-1-diagnostics`.

**Standing rules for every task:** PS 5.1 only (no ternary/`??`/`&&`; never assign `$input`/`$matches`). Save files UTF-8 with BOM + trailing newline. `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`. Never execute tools that modify the system (temp-cleanup, file-system-check, winget-upgrade) during verification — read-only tools may be executed.

---

## Task 0: Pre-porting hardening (from foundation final review)

**Files:**
- Modify: `build.ps1` (explicit UTF-8 reads)
- Create: `tests\template.tests.ps1`
- Modify: `src\core\05-ui-console.ps1` + `tests\ui-console.tests.ps1` (category letters)
- Modify: `tests\artifact.tests.ps1` (one analyzer-gated build)
- Create: `docs\porting-playbook.md`

- [ ] **Step 1: build.ps1 — read source as UTF-8 explicitly.** Change every `Get-Content <path> -Raw` to `Get-Content <path> -Raw -Encoding UTF8` (4 places: param file, core loop, registry, tools loop, entry file). This makes BOM-less UTF-8 source files safe (PS 5.1 otherwise decodes them as ANSI).

- [ ] **Step 2: Write failing template-compliance tests** — `tests\template.tests.ps1`:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:Registry = Import-PowerShellDataFile (Join-Path $repoRoot 'src\registry\tools.psd1')
    $script:Tools = @($script:Registry.Tools)
    $script:ToolAsts = @{}
    foreach ($f in (Get-ChildItem (Join-Path $repoRoot 'src\tools') -Recurse -Filter *.ps1)) {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) { throw "Parse errors in $($f.Name)" }
        foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            $script:ToolAsts[$fn.Name] = $fn
        }
    }
}

Describe 'Tool template compliance' {
    It 'every tool function uses an approved PowerShell verb' {
        $approved = (Get-Verb).Verb
        foreach ($name in $script:ToolAsts.Keys) {
            ($name -split '-')[0] | Should -BeIn $approved -Because "$name must use an approved verb"
        }
    }

    It 'every tool function declares a Silent switch (required by the dispatcher)' {
        foreach ($name in $script:ToolAsts.Keys) {
            $params = $script:ToolAsts[$name].Body.ParamBlock.Parameters.Name.VariablePath.UserPath
            $params | Should -Contain 'Silent' -Because "$name is invoked with -Silent:`$Silent"
        }
    }

    It 'every tool function calls New-ToolRun and Complete-ToolRun' {
        foreach ($name in $script:ToolAsts.Keys) {
            $calls = $script:ToolAsts[$name].FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() }
            $calls | Should -Contain 'New-ToolRun' -Because "$name must bracket its run"
            $calls | Should -Contain 'Complete-ToolRun' -Because "$name must record an outcome"
        }
    }

    It 'every New-ToolRun -Id literal matches the registry entry for that function' {
        foreach ($name in $script:ToolAsts.Keys) {
            $entry = $script:Tools | Where-Object { $_.Function -eq $name } | Select-Object -First 1
            $entry | Should -Not -BeNullOrEmpty -Because "$name needs a registry entry"
            $idCalls = $script:ToolAsts[$name].FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                $args[0].GetCommandName() -eq 'New-ToolRun' }, $true)
            foreach ($call in $idCalls) {
                $idArg = $null
                for ($i = 0; $i -lt $call.CommandElements.Count; $i++) {
                    $el = $call.CommandElements[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -eq 'Id') {
                        $idArg = $call.CommandElements[$i + 1]
                    }
                }
                $idArg | Should -Not -BeNullOrEmpty -Because "$name must pass -Id to New-ToolRun"
                $idArg.Value | Should -Be $entry.Id -Because "$name's New-ToolRun -Id must match its registry Id (a mismatch silently breaks PDQ exit codes)"
            }
        }
    }
}
```

Run them: the 4 tests must PASS against the two existing pilots (they are compliant). These tests bite as porting adds files — verify non-vacuousness by checking they iterate ≥2 functions (add `$script:ToolAsts.Count | Should -BeGreaterThan 1` inside the first It if needed during development, then remove).

- [ ] **Step 3: Category letters (landing-number namespace decision).** In `src\core\05-ui-console.ps1` category mode, replace numeric category indexes with letters so all 106 legacy tool NUMBERS stay direct-run from the landing screen. In `Show-LandingMenu` category branch:

```powershell
        $index = 0
        foreach ($c in $categories) {
            $letter = [string][char](65 + $index)   # A, B, C... (7 categories max planned; T/X are safe at 20+/24+)
            $count = @($tools | Where-Object { $_.Category -eq $c }).Count
            Write-Host (' {0}. {1} ({2} tools)' -f $letter, $c, $count)
            $map[$letter] = $c
            $index++
        }
        Write-Host ''
        Write-Host ' Enter: category letter | tool number | search text' -ForegroundColor Gray
        Write-Host '        T = save session summary (for tickets)   X = exit' -ForegroundColor Gray
```

In `Start-ConsoleMenu`, the map lookup becomes case-insensitive: `if ($map.ContainsKey($selection.ToUpper()))` → `Show-CategoryTools -Category $map[$selection.ToUpper()]`, and the category-mode prompt becomes `' Select category letter or tool number, search text, or X to exit'`. NOTE: T and X are matched before the map lookup, so future categories must never be assigned letters T or X — add that as a comment. Update `tests\ui-console.tests.ps1` category-mode test: `$map['A'] | Should -Be 'CategoryA'` and map keys are letters.

- [ ] **Step 4: artifact tests — exercise the analyzer gate once.** In `tests\artifact.tests.ps1` add:

```powershell
    It 'builds clean with the analyzer gate enabled' {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        { & (Join-Path $repoRoot 'build.ps1') *> $null } | Should -Not -Throw
    }
```

- [ ] **Step 5: Write `docs\porting-playbook.md`:**

```markdown
# NMM Toolkit v9 — Porting Playbook

Rules for porting a v8 tool. The v8 monolith (`C:\Users\IT\Desktop\NMMTools.ps1`)
is READ-ONLY behavioral reference.

## The Id-in-three-places rule
The kebab-case slug must be identical in: (1) the registry `Id`, (2) the tool's
`New-ToolRun -Id '<slug>'`, (3) nowhere else. `tests\template.tests.ps1` enforces this.

## Template (mandatory shape)
    function Verb-Noun {
        [CmdletBinding()]
        param([switch]$Silent)   # required by dispatcher even when unused

        $run = $null
        try {
            $run = New-ToolRun -Id '<slug>'
            # ... port v8 behavior here ...
            Complete-ToolRun $run -Status Success -Summary '<one line for the ticket>'
        }
        catch {
            Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
        }
    }

## Hard rules
- NEVER call Write-Host or Read-Host in a tool. Use `Write-ToolOutput -Level Info|Success|Warning|Error|Detail`
  and `Read-ToolChoice -Prompt ... -Default ... -Silent:$Silent`.
- Every prompt needs a safe `-Default` — that default is what `-Silent` (PDQ) auto-selects.
- Approved verbs only (`Get-Verb`); rename v8 `Fix-*` → `Repair-*` etc., keep the old name in registry Tags.
- Status meanings: Success = did the thing; Warning = ran, found something worth flagging;
  Skipped = user declined; Failed = could not do the thing. Summary goes on the ticket — write it for a tech.
- Registry fields: `Risk` = ReadOnly | Modifies | Disruptive (Disruptive needs -Force under -Silent).
  `SilentCapable = $false` only when the tool is meaningless without interaction.
- Preserve v8 BEHAVIOR (what it checks/fixes/reports), not v8 code. Drop v8's Add-ToolResult,
  colors, Write-Host formatting; keep thresholds, registry paths, command invocations.
- File: `src\tools\<category>\<Verb-Noun>.ps1`, UTF-8 with BOM, one function per file
  (private helpers may be nested INSIDE the function body).

## Per-batch loop
    .\build.ps1
    Import-Module Pester -MinimumVersion 5.0; Invoke-Pester .\tests
Both must be green before commit. Smoke at least one ported read-only tool via:
    .\dist\NMMTools.ps1 -Tool <slug> -Silent
```

- [ ] **Step 6: Build, full suite (expect 52 + 4 template + 1 analyzer = 57), commit** `chore: pre-porting hardening - template gates, category letters, UTF-8 reads, playbook`.

---

## Tasks 1–5: Port the 21 Diagnostics tools

**Registry entries (exact values — append to `src\registry\tools.psd1` Tools array as each tool is ported).** Every entry uses `Category = 'Diagnostics'`; table → psd1 conversion follows the existing pilot-entry format exactly. Example row 1 becomes:

```powershell
        @{
            Id            = 'system-info'
            LegacyId      = '1'
            Name          = 'System Information'
            Category      = 'Diagnostics'
            Function      = 'Get-SystemInformation'
            Description   = 'OS, hardware, BIOS, and domain summary for the machine'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('system','os','hardware','bios')
        }
```

| Id | LegacyId | Name | Function (v8 line) | Admin | SilentCapable | Risk | Description | Tags |
|---|---|---|---|---|---|---|---|---|
| system-info | 1 | System Information | Get-SystemInformation (633) | $false | $true | ReadOnly | OS, hardware, BIOS, and domain summary for the machine | system,os,hardware,bios |
| disk-space | 2 | Disk Space Analysis | Get-DiskSpaceAnalysis (667) | $false | $true | ReadOnly | Per-volume capacity, free space, and low-space warnings | disk,space,storage,volume |
| network-diagnostics | 3 | Network Diagnostics | Get-NetworkDiagnostics (697) | $false | $true | ReadOnly | Adapter, IP, gateway, and DNS configuration overview | network,ip,dns,adapter |
| running-processes | 4 | Running Processes | Get-RunningProcesses (721) | $false | $true | ReadOnly | Top processes by CPU and memory usage | process,cpu,memory |
| services-status | 5 | Windows Services Status | Get-ServicesStatus (743) | $false | $true | ReadOnly | Stopped automatic services and key service health | services,automatic,stopped |
| event-log-errors | 6 | Recent Event Log Errors | Get-EventLogErrors (763) | $false | $true | ReadOnly | Recent System/Application error and warning events | events,errors,eventlog |
| performance-metrics | 7 | Performance Metrics | Get-PerformanceMetrics (789) | $false | $true | ReadOnly | CPU, memory, and disk performance counters snapshot | performance,cpu,memory,counters |
| installed-software | 8 | Installed Software List | Get-InstalledSoftware (819) | $false | $true | ReadOnly | Installed applications from registry uninstall keys | software,installed,apps,programs |
| windows-updates | 9 | Windows Updates Status | Get-WindowsUpdates (847) | $false | $true | ReadOnly | Recent installed updates and update service state | updates,hotfix,patch,kb |
| user-accounts | 10 | User Account Information | Get-UserAccounts (863) | $false | $true | ReadOnly | Local users, group membership, and account state | users,accounts,groups |
| network-connectivity | 12 | Network Connectivity Tests | Test-NetworkConnectivity (909) | $false | $true | ReadOnly | Ping/DNS reachability tests to key endpoints | network,ping,connectivity,dns |
| system-health | 13 | System Health Check | Get-SystemHealthCheck (938) | $false | $true | ReadOnly | Combined disk/memory/service/uptime health verdict | health,check,overview |
| security-analysis | 14 | Security Analysis | Get-SecurityAnalysis (980) | $false | $true | ReadOnly | Defender, firewall, UAC, and BitLocker posture summary | security,defender,firewall,uac |
| driver-info | 15 | Driver Information | Get-DriverInformation (1017) | $false | $true | ReadOnly | Problem devices and driver inventory highlights | drivers,devices,pnp |
| startup-programs | 16 | Startup Programs | Get-StartupPrograms (1037) | $false | $true | ReadOnly | Auto-start entries from registry and startup folders | startup,autorun,boot |
| scheduled-tasks | 17 | Scheduled Tasks Review | Get-ScheduledTasksReview (1073) | $false | $true | ReadOnly | Non-Microsoft scheduled tasks and their state | tasks,scheduler,scheduled |
| file-system-check | 18 | File System Check | Start-FileSystemCheck (1091) | $true | $true | Modifies | Read v8 1091-1105: if it only runs a scan/verify, keep Modifies; if it schedules a boot-time chkdsk, set Risk='Disruptive' and note it in the report | chkdsk,filesystem,scan |
| windows-features | 19 | Windows Features Status | Get-WindowsFeatures (1106) | $true | $true | ReadOnly | Enabled optional Windows features (Get-WindowsOptionalFeature needs admin; if v8 uses a non-admin source, set Admin $false and note it) | features,optional,windows |
| pending-reboot | 94 | Pending Reboot Status | Get-PendingRebootStatus (11096) | $false | $true | ReadOnly | Pending-reboot indicators from CBS/WU/PendingFileRename | reboot,pending,restart |
| winget-upgrade | 104 | winget App Update Sweep | Invoke-WingetUpgradeAll (11706) | $true | $true | Disruptive | Upgrades all winget-managed apps (can close/replace running apps) | winget,upgrade,apps,updates |
| hardware-summary | 69 | Offline Hardware Summary | Export-HardwareSummary (11956) | $false | $true | ReadOnly | Exports a hardware summary file for ticket attachments (writes to Desktop; use [Environment]::GetFolderPath('Desktop')) | hardware,summary,export,ticket |

**Porting procedure per tool (applies to every sub-batch):**
1. Read the v8 function (start line above; ends at the next `function` declaration). Identify: what it checks/changes, output lines, any prompts, any thresholds.
2. Write `src\tools\diagnostics\<Function>.ps1` in template shape per `docs\porting-playbook.md`. v8 `Read-Host` prompts become `Read-ToolChoice` with a safe default; v8 `Add-ToolResult` is replaced by the `Complete-ToolRun` summary.
3. Append the registry entry (exact values from the table).
4. After the sub-batch: `.\build.ps1` green + full Pester suite green + smoke one read-only tool of the sub-batch via `dist\NMMTools.ps1 -Tool <slug> -Silent` (exit 0). NEVER smoke file-system-check or winget-upgrade.
5. Commit: `feat: port diagnostics batch 1.<n> (<slugs>)`.

- [ ] **Task 1 (sub-batch 1.1):** system-info, disk-space, network-diagnostics, running-processes, services-status
- [ ] **Task 2 (sub-batch 1.2):** event-log-errors, performance-metrics, installed-software, windows-updates, user-accounts
- [ ] **Task 3 (sub-batch 1.3):** network-connectivity, system-health, security-analysis, driver-info, startup-programs
- [ ] **Task 4 (sub-batch 1.4):** scheduled-tasks, file-system-check, windows-features (flag the Risk/Admin questions from the table in the report)
- [ ] **Task 5 (sub-batch 1.5):** pending-reboot, winget-upgrade, hardware-summary

---

## Task 6: Batch close-out

- [ ] **Step 1:** Full build + suite green; `dist\NMMTools.ps1 -ListTools` shows **23 tools**, all Diagnostics; landing menu still flat mode (1 category) — scripted-stdin smoke shows all 23 listed in numeric order.
- [ ] **Step 2:** Update the parity checklist: create `docs\parity-checklist.md` listing all 106 v8 menu items with status (ported / pilot / pending batch N), marking 1-20, 69, 94, 104 as DONE.
- [ ] **Step 3:** Commit `docs: batch 1 complete - parity checklist`; merge to master after final review.
