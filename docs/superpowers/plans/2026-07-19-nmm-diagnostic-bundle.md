# NMM Diagnostic Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one new orchestrator tool (`Invoke-DiagnosticBundle`) that runs a set of read-only
checks, zips raw per-check output plus a health summary and ticket-ready text to the Desktop,
backed by four new gap-filling diagnostic tools and two small additive core changes.

**Architecture:** Existing tools already emit via `Write-ToolOutput`/`Complete-ToolRun`; add a
fourth `Capture` output sink so the bundle can call any existing tool function unchanged and
collect its raw text. Reuse `$script:ToolRuns`/`Complete-ToolRun` status for the health summary
and `Export-TicketSummary` (given an optional `-Runs` slice) for the copyable technician summary.
Package with `Compress-Archive`, matching the existing browser-backup ZIP pattern.

**Tech Stack:** PowerShell 5.1, Pester 5.0 (tests), CIM cmdlets, `Compress-Archive`.

## Global Constraints

- PowerShell 5.1 target; no PS7-only syntax (ternary, `??`, `?.`).
- ASCII only; no em dashes, smart quotes, box-drawing characters.
- `Write-ToolOutput`/`Read-ToolChoice` for all output/prompting; never `Write-Host`/`Read-Host`
  directly inside a tool.
- Every tool function: `[CmdletBinding()]`, `param([switch]$Silent)` (dispatcher requirement),
  wraps its body in `New-ToolRun`/`Complete-ToolRun`, every path ends in exactly one
  `Complete-ToolRun` call with `Status` in `Success|Warning|Failed|Skipped`.
- One function per file under `src\tools\<category>\`; helper functions used by more than one
  tool (or that need direct unit testing) go in a new numbered `src\core\` file instead — every
  function defined under `src\tools\` must have exactly one registry entry
  (`tests\registry.tests.ps1` enforces this), so tool files cannot carry private helpers.
- Registry entries: exactly the 10 fields in `CLAUDE.md`'s order; `Category` must match the tool
  file's directory name (capitalized); `LegacyId` unique, numeric string; `Id` kebab-case.
- `.\build.ps1` then `Invoke-Pester .\tests` after every task; only advance on green.
- Never use bare `(if ...)` as a sub-expression (throws `CommandNotFoundException` in PS 5.1) —
  use `$x = if (...) {a} else {b}` as a direct statement, or a plain `if/else` block.

---

### Task 1: Capture output sink

**Files:**
- Modify: `src\core\02-output.ps1`
- Test: `tests\output.tests.ps1`

**Interfaces:**
- Produces: `Start-ToolOutputCapture` (no params) — redirects `Write-ToolOutput` into an
  in-memory buffer. `Stop-ToolOutputCapture` (no params) — returns the buffered text (`string`)
  and restores the prior `$script:OutputSink`/`$script:LogFilePath`.

- [ ] **Step 1: Write the failing tests**

Add to `tests\output.tests.ps1`, after the existing `Describe 'Read-ToolChoice'` block:

```powershell
Describe 'Start-ToolOutputCapture / Stop-ToolOutputCapture' {
    AfterEach { Set-OutputSink -Sink Console }

    It 'buffers Write-ToolOutput calls instead of writing to console' {
        Set-OutputSink -Sink Console
        Start-ToolOutputCapture
        Write-ToolOutput 'line one'
        Write-ToolOutput 'line two' -Level Warning
        $text = Stop-ToolOutputCapture
        $text | Should -Match 'line one'
        $text | Should -Match 'line two'
    }

    It 'restores the prior sink after Stop-ToolOutputCapture' {
        Set-OutputSink -Sink Silent
        Start-ToolOutputCapture
        Write-ToolOutput 'captured'
        [void](Stop-ToolOutputCapture)
        $script:OutputSink | Should -Be 'Silent'
    }

    It 'restores the prior log path after Stop-ToolOutputCapture' {
        $tmpDir = Join-Path $env:TEMP "nmm-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $tmpDir | Out-Null
        Set-OutputSink -Sink Console -LogDirectory $tmpDir
        $priorLog = $script:LogFilePath
        Start-ToolOutputCapture
        Write-ToolOutput 'should not hit the log file'
        [void](Stop-ToolOutputCapture)
        $script:LogFilePath | Should -Be $priorLog
        Remove-Item $tmpDir -Recurse -Force
    }

    It 'returns an empty string when nothing was written' {
        Start-ToolOutputCapture
        Stop-ToolOutputCapture | Should -Be ''
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\output.tests.ps1 -CI`
Expected: FAIL — `Start-ToolOutputCapture` is not recognized.

- [ ] **Step 3: Implement the capture sink**

In `src\core\02-output.ps1`, change the top of the file (currently lines 5-7) to:

```powershell
$script:OutputSink      = 'Console'
$script:LogFilePath     = $null
$script:GuiSync         = $null
$script:CaptureBuffer   = $null
$script:CapturePrevSink = $null
$script:CapturePrevLog  = $null
```

In `Write-ToolOutput`, add a new branch after the existing `elseif ($script:OutputSink -eq 'GUI')`
block (immediately before the function's closing `}`):

```powershell
    } elseif ($script:OutputSink -eq 'Capture') {
        [void]$script:CaptureBuffer.AppendLine($Message)
    }
```

Add two new functions immediately after `Write-ToolOutput` (before `function Read-ToolChoice`):

```powershell
function Start-ToolOutputCapture {
    # Redirects Write-ToolOutput into an in-memory buffer instead of the
    # console/log/GUI sink, so a caller (e.g. the diagnostic bundle) can run
    # another tool and collect its raw text without touching the console.
    $script:CapturePrevSink = $script:OutputSink
    $script:CapturePrevLog  = $script:LogFilePath
    $script:CaptureBuffer   = New-Object System.Text.StringBuilder
    $script:OutputSink      = 'Capture'
    $script:LogFilePath     = $null
}

function Stop-ToolOutputCapture {
    # Returns the buffered text and restores the sink/log path that were
    # active before Start-ToolOutputCapture was called.
    $text = ''
    if ($script:CaptureBuffer) { $text = $script:CaptureBuffer.ToString() }
    $script:OutputSink    = $script:CapturePrevSink
    $script:LogFilePath   = $script:CapturePrevLog
    $script:CaptureBuffer = $null
    return $text
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\output.tests.ps1 -CI`
Expected: PASS, all `Describe 'Start-ToolOutputCapture / Stop-ToolOutputCapture'` tests green.

- [ ] **Step 5: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green (no regressions).

- [ ] **Step 6: Commit**

```bash
git add src/core/02-output.ps1 tests/output.tests.ps1
git commit -m "feat(core): add Capture output sink for programmatic tool-output collection"
```

---

### Task 2: Export-TicketSummary -Runs parameter

**Files:**
- Modify: `src\core\03-results.ps1`
- Test: `tests\results.tests.ps1`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Export-TicketSummary` gains an optional `-Runs` parameter (any enumerable of run
  objects with `Status`/`Name`/`Summary`/`Duration`); defaults to `$script:ToolRuns` so every
  existing call site is unaffected.

- [ ] **Step 1: Write the failing tests**

Add to `tests\results.tests.ps1`, inside the existing `Describe 'Export-TicketSummary'` block
(after the `'writes the summary to a file when -Path is given'` test):

```powershell
    It 'summarizes only the runs passed via -Runs, not the full session' {
        $keep = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $keep -Status Success -Summary 'kept'
        $drop = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $drop -Status Failed -Summary 'dropped'
        $text = Export-TicketSummary -Runs @($keep)
        $text | Should -Match 'kept'
        $text | Should -Not -Match 'dropped'
    }

    It 'defaults to the full session when -Runs is omitted (regression guard)' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'still default'
        Export-TicketSummary | Should -Match 'still default'
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\results.tests.ps1 -CI`
Expected: FAIL — the first new test fails because `Export-TicketSummary -Runs @($keep)` still
returns both runs (parameter doesn't exist yet, so PowerShell either errors on the unknown
parameter or the summary body ignores it).

- [ ] **Step 3: Implement the -Runs parameter**

In `src\core\03-results.ps1`, change `Export-TicketSummary`'s signature and body:

```powershell
function Export-TicketSummary {
    param(
        [string]$Path,
        $Runs = $script:ToolRuns
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('NMM Toolkit Session Summary')
    [void]$sb.AppendLine(('Computer: {0}    User: {1}' -f $env:COMPUTERNAME, $env:USERNAME))
    [void]$sb.AppendLine(('Session:  {0:g} - {1:g}' -f $script:SessionStart, (Get-Date)))
    [void]$sb.AppendLine('')
    $runList = @($Runs)
    if ($runList.Count -eq 0) {
        [void]$sb.AppendLine('No tools were run this session.')
    }
    foreach ($run in $runList) {
        $dur = '--:--'
        if ($run.Duration) {
            if ($run.Duration.TotalHours -ge 1) {
                $dur = '{0:h\:mm\:ss}' -f $run.Duration
            } else {
                $dur = '{0:mm\:ss}' -f $run.Duration
            }
        }
        [void]$sb.AppendLine(('[{0}] {1} ({2})' -f $run.Status.ToUpper(), $run.Name, $dur))
        if ($run.Summary) { [void]$sb.AppendLine('    ' + $run.Summary) }
    }
    $text = $sb.ToString()
    if ($Path) {
        try {
            Set-Content -Path $Path -Value $text -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-ToolOutput "Warning: could not write ticket summary to '$Path' - $_" -Level Warning
        }
    }
    return $text
}
```

(Only the `param()` block and the two `$script:ToolRuns` references — now `$runList` — changed
from the current file; the rest is unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\results.tests.ps1 -CI`
Expected: PASS, all tests in `Describe 'Export-TicketSummary'` and `Describe 'Tool run tracking'`
green.

- [ ] **Step 5: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green.

- [ ] **Step 6: Commit**

```bash
git add src/core/03-results.ps1 tests/results.tests.ps1
git commit -m "feat(core): add -Runs parameter to Export-TicketSummary"
```

---

### Task 3: Get-EventLogErrors time window

**Files:**
- Modify: `src\tools\diagnostics\Get-EventLogErrors.ps1`

**Interfaces:**
- Produces: `Get-EventLogErrors` gains an optional `-HoursBack` parameter (`int`, default `24`,
  matching current fixed behavior); the bundle (Task 9) will pass `-HoursBack 168` for the 7-day
  window.

No dedicated test file: this repo has no per-tool business-logic test files for any of its ~115
existing diagnostic tools (only structural checks via `tests\template.tests.ps1` /
`tests\registry.tests.ps1`, which run automatically against every tool file). Verify with the
full suite plus a manual smoke test through the built artifact, matching this repo's own
"build -> Pester -> smoke-test" convention (`docs\porting-playbook.md`).

- [ ] **Step 1: Modify the tool**

Replace the full contents of `src\tools\diagnostics\Get-EventLogErrors.ps1` with:

```powershell
function Get-EventLogErrors {
    [CmdletBinding()]
    param(
        [switch]$Silent,   # required by dispatcher even when unused
        [int]$HoursBack = 24
    )

    $run = $null
    try {
        $run = New-ToolRun -Id 'event-log-errors'

        $cutoff = (Get-Date).AddHours(-$HoursBack)

        $evtErrors = @()
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName   = 'System', 'Application'
            Level     = 2
            StartTime = $cutoff
        } -MaxEvents 20 -ErrorAction SilentlyContinue -ErrorVariable evtErrors)

        # Distinguish real access/query failures from the benign "no matching events" non-terminating error
        $realFailures = @($evtErrors | Where-Object { $_.Exception.Message -notlike '*No events were found*' })
        if ($realFailures.Count -gt 0 -and $events.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary ('Event log query failed: {0}' -f $realFailures[0].Exception.Message)
            return
        }

        if ($events.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary ('0 errors in last {0}h' -f $HoursBack)
            return
        }

        Write-ToolOutput ('Recent errors found: {0} (showing up to 10)' -f $events.Count)
        # Scan rows use Detail; each event is a table row
        foreach ($e in ($events | Select-Object -First 10)) {
            Write-ToolOutput ('{0:g}  {1}  ID {2}' -f $e.TimeCreated, $e.ProviderName, $e.Id) -Level Detail
        }

        Complete-ToolRun $run -Status Warning -Summary ('{0} errors in last {1}h' -f $events.Count, $HoursBack)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green (structural tests re-validate the modified file
automatically; no test references the old fixed-24h summary text, so no test needs updating).

- [ ] **Step 3: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool event-log-errors -Silent -Mode Console`
Expected: exit code 0, output shows either "0 errors in last 24h" or a warning listing recent
errors — confirms the default behavior is unchanged.

- [ ] **Step 4: Commit**

```bash
git add src/tools/diagnostics/Get-EventLogErrors.ps1
git commit -m "feat(diagnostics): add -HoursBack parameter to Get-EventLogErrors"
```

---

### Task 4: Get-ReliabilityHistory tool

**Files:**
- Create: `src\tools\diagnostics\Get-ReliabilityHistory.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Produces: `Get-ReliabilityHistory -Silent:$Silent [-HoursBack <int>]` (default 24), registry
  `Id = 'reliability-history'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\diagnostics\Get-ReliabilityHistory.ps1`:

```powershell
function Get-ReliabilityHistory {
    [CmdletBinding()]
    param(
        [switch]$Silent,   # required by dispatcher even when unused
        [int]$HoursBack = 24
    )

    $run = $null
    try {
        $run = New-ToolRun -Id 'reliability-history'

        $cutoff = (Get-Date).AddHours(-$HoursBack)

        $records = @(Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction Stop |
            Where-Object { $_.TimeGenerated -ge $cutoff })

        if ($records.Count -eq 0) {
            Write-ToolOutput ('No reliability records in the last {0}h.' -f $HoursBack)
            Complete-ToolRun $run -Status Success -Summary ('0 reliability events in last {0}h' -f $HoursBack)
            return
        }

        $bySource = $records | Group-Object SourceName, EventIdentifier | Sort-Object Count -Descending

        Write-ToolOutput ('Reliability events in last {0}h: {1}' -f $HoursBack, $records.Count)
        foreach ($grp in ($bySource | Select-Object -First 10)) {
            $latest = ($grp.Group | Sort-Object TimeGenerated -Descending | Select-Object -First 1)
            Write-ToolOutput ('{0}x  {1}  (event {2})  last {3:g}' -f
                $grp.Count, $latest.SourceName, $latest.EventIdentifier, $latest.TimeGenerated) -Level Detail
        }

        $topSources = ($bySource | Select-Object -First 3 | ForEach-Object { $_.Group[0].SourceName }) -join ', '
        Complete-ToolRun $run -Status Warning -Summary (
            '{0} reliability events in last {1}h; top source(s): {2}' -f $records.Count, $HoursBack, $topSources)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1` (immediately before the closing `)` and
`}`, after the `wmi-repair` entry):

```powershell
        @{
            Id            = 'reliability-history'
            LegacyId      = '112'
            Name          = 'Reliability Monitor History'
            Category      = 'Diagnostics'
            Function      = 'Get-ReliabilityHistory'
            Description   = 'Summarizes recurring failure sources from Reliability Monitor within a lookback window'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('reliability', 'crash', 'history', 'stability')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds; `tests\registry.tests.ps1` and `tests\template.tests.ps1` pass for the
new entry/function automatically; all other tests green.

- [ ] **Step 4: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool reliability-history -Silent -Mode Console`
Expected: exit code 0, output shows either "0 reliability events..." or a list of recurring
failure sources.

- [ ] **Step 5: Commit**

```bash
git add src/tools/diagnostics/Get-ReliabilityHistory.ps1 src/registry/tools.psd1
git commit -m "feat(diagnostics): add reliability-history tool"
```

---

### Task 5: Get-GroupPolicyResult tool

**Files:**
- Create: `src\tools\diagnostics\Get-GroupPolicyResult.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Produces: `Get-GroupPolicyResult -Silent:$Silent`, registry `Id = 'group-policy-result'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\diagnostics\Get-GroupPolicyResult.ps1`:

```powershell
function Get-GroupPolicyResult {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'group-policy-result'

        $output = & gpresult /r 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
            Write-ToolOutput 'gpresult returned no data.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'gpresult returned no data (RSoP service issue)'
            return
        }

        foreach ($line in ($output -split "`r?`n")) {
            if ($line.Trim()) { Write-ToolOutput $line -Level Detail }
        }

        $lastApplied = ($output -split "`r?`n" | Where-Object { $_ -match 'Last time Group Policy was applied' } | Select-Object -First 1)
        $summary = 'gpresult completed'
        if ($lastApplied) { $summary = $lastApplied.Trim() }
        Complete-ToolRun $run -Status Success -Summary $summary
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1`:

```powershell
        @{
            Id            = 'group-policy-result'
            LegacyId      = '113'
            Name          = 'Group Policy Result'
            Category      = 'Diagnostics'
            Function      = 'Get-GroupPolicyResult'
            Description   = 'Runs gpresult /r and reports applied GPOs, group membership, and last refresh time'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('gpresult', 'grouppolicy', 'rsop', 'policy')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green.

- [ ] **Step 4: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool group-policy-result -Silent -Mode Console`
Expected: exit code 0, output shows RSoP text ending with a "Last time Group Policy was applied"
line.

- [ ] **Step 5: Commit**

```bash
git add src/tools/diagnostics/Get-GroupPolicyResult.ps1 src/registry/tools.psd1
git commit -m "feat(diagnostics): add group-policy-result tool"
```

---

### Task 6: Get-DeviceManagerErrors tool

**Files:**
- Create: `src\tools\diagnostics\Get-DeviceManagerErrors.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Produces: `Get-DeviceManagerErrors -Silent:$Silent`, registry
  `Id = 'device-manager-errors'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\diagnostics\Get-DeviceManagerErrors.ps1`:

```powershell
function Get-DeviceManagerErrors {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'device-manager-errors'

        $codeMeaning = @{
            1  = 'Device is not configured correctly'
            10 = 'Device cannot start'
            18 = 'Reinstall the drivers for this device'
            19 = 'Registry may be corrupted'
            22 = 'Device is disabled'
            24 = 'Device is not present, not working, or missing drivers'
            28 = 'Drivers for this device are not installed'
            31 = 'Device is not working properly (drivers or required software missing)'
            32 = 'Driver service is disabled'
            37 = 'Windows cannot initialize the device driver'
            39 = 'Driver is missing or corrupted'
            43 = 'Windows has stopped this device because it has reported problems'
            45 = 'Device is not currently connected'
        }

        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 })

        if ($devices.Count -eq 0) {
            Write-ToolOutput 'No devices reporting errors.'
            Complete-ToolRun $run -Status Success -Summary 'No Device Manager errors'
            return
        }

        Write-ToolOutput ('Devices with errors: {0}' -f $devices.Count)
        foreach ($d in $devices) {
            $meaning = $codeMeaning[[int]$d.ConfigManagerErrorCode]
            if (-not $meaning) { $meaning = 'Unknown error code' }
            Write-ToolOutput ('{0}  [Code {1}] {2} - {3}' -f $d.Name, $d.ConfigManagerErrorCode, $d.PNPClass, $meaning) -Level Detail
        }

        Complete-ToolRun $run -Status Warning -Summary ('{0} device(s) reporting Device Manager errors' -f $devices.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1`:

```powershell
        @{
            Id            = 'device-manager-errors'
            LegacyId      = '114'
            Name          = 'Device Manager Errors'
            Category      = 'Diagnostics'
            Function      = 'Get-DeviceManagerErrors'
            Description   = 'Scans for devices reporting a Device Manager error code and decodes the common ones'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('device', 'driver', 'pnp', 'configmanager')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green.

- [ ] **Step 4: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool device-manager-errors -Silent -Mode Console`
Expected: exit code 0, output shows either "No devices reporting errors." or a list of devices
with decoded error meanings.

- [ ] **Step 5: Commit**

```bash
git add src/tools/diagnostics/Get-DeviceManagerErrors.ps1 src/registry/tools.psd1
git commit -m "feat(diagnostics): add device-manager-errors tool"
```

---

### Task 7: Get-CrashDumpInventory tool

**Files:**
- Create: `src\tools\diagnostics\Get-CrashDumpInventory.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Produces: `Get-CrashDumpInventory -Silent:$Silent [-HoursBack <int>]` (default 24), registry
  `Id = 'wer-crash-inventory'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\diagnostics\Get-CrashDumpInventory.ps1`:

```powershell
function Get-CrashDumpInventory {
    [CmdletBinding()]
    param(
        [switch]$Silent,   # required by dispatcher even when unused
        [int]$HoursBack = 24
    )

    $run = $null
    try {
        $run = New-ToolRun -Id 'wer-crash-inventory'

        $cutoff = (Get-Date).AddHours(-$HoursBack)

        $paths = @(
            (Join-Path $env:LOCALAPPDATA 'CrashDumps'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive')
        )

        $found = @()
        foreach ($p in $paths) {
            if (Test-Path -LiteralPath $p) {
                $found += Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $cutoff }
            }
        }

        if ($found.Count -eq 0) {
            Write-ToolOutput ('No crash dump or WER report files in the last {0}h.' -f $HoursBack)
            Complete-ToolRun $run -Status Success -Summary ('0 crash items in last {0}h' -f $HoursBack)
            return
        }

        Write-ToolOutput ('Crash dump / WER items in last {0}h: {1}' -f $HoursBack, $found.Count)
        foreach ($f in ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 15)) {
            $sizeKB = [math]::Round($f.Length / 1KB, 1)
            Write-ToolOutput ('{0:g}  {1}  ({2} KB)' -f $f.LastWriteTime, $f.Name, $sizeKB) -Level Detail
        }

        Complete-ToolRun $run -Status Warning -Summary ('{0} crash dump/WER item(s) in last {1}h' -f $found.Count, $HoursBack)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1`:

```powershell
        @{
            Id            = 'wer-crash-inventory'
            LegacyId      = '115'
            Name          = 'Application Crash Dump Inventory'
            Category      = 'Diagnostics'
            Function      = 'Get-CrashDumpInventory'
            Description   = 'Lists Windows Error Reporting application-crash dump files within a lookback window'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('crash', 'dump', 'wer', 'application')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green.

- [ ] **Step 4: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool wer-crash-inventory -Silent -Mode Console`
Expected: exit code 0, output shows either "No crash dump or WER report files..." or a list of
recent dump/report files.

- [ ] **Step 5: Commit**

```bash
git add src/tools/diagnostics/Get-CrashDumpInventory.ps1 src/registry/tools.psd1
git commit -m "feat(diagnostics): add wer-crash-inventory tool"
```

---

### Task 8: Diagnostic bundle helpers (core)

**Files:**
- Create: `src\core\11-diagnostic-bundle-helpers.ps1`
- Test: `tests\diagnostic-bundle-helpers.tests.ps1`

**Interfaces:**
- Consumes: nothing (pure functions).
- Produces:
  `Build-DiagnosticBundleSummary -Runs <array>` returns
  `[PSCustomObject]@{ PassCount; WarnCount; FailCount; Lines }` where `Lines` is an array of
  formatted `[STATUS] Name - Summary` strings for every non-Success run.
  `Get-DiagnosticBundleZipPath -DesktopPath <string> -ComputerName <string> -Timestamp <datetime>`
  returns the full ZIP path string.

- [ ] **Step 1: Write the failing tests**

Create `tests\diagnostic-bundle-helpers.tests.ps1`:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\11-diagnostic-bundle-helpers.ps1')
}

Describe 'Build-DiagnosticBundleSummary' {
    It 'counts pass, warn, and fail runs separately' {
        $runs = @(
            [PSCustomObject]@{ Name = 'A'; Status = 'Success'; Summary = 'ok' }
            [PSCustomObject]@{ Name = 'B'; Status = 'Warning'; Summary = 'reboot pending' }
            [PSCustomObject]@{ Name = 'C'; Status = 'Failed';  Summary = 'query failed' }
            [PSCustomObject]@{ Name = 'D'; Status = 'Skipped'; Summary = '' }
        )
        $result = Build-DiagnosticBundleSummary -Runs $runs
        $result.PassCount | Should -Be 1
        $result.WarnCount | Should -Be 1
        $result.FailCount | Should -Be 2
    }

    It 'formats one line per non-passing run, omitting Success' {
        $runs = @(
            [PSCustomObject]@{ Name = 'System Information'; Status = 'Success'; Summary = 'ok' }
            [PSCustomObject]@{ Name = 'Pending Reboot'; Status = 'Warning'; Summary = 'Windows Update requires reboot' }
        )
        $result = Build-DiagnosticBundleSummary -Runs $runs
        $result.Lines.Count | Should -Be 1
        $result.Lines[0] | Should -Match '\[WARNING\]'
        $result.Lines[0] | Should -Match 'Pending Reboot'
        $result.Lines[0] | Should -Match 'Windows Update requires reboot'
    }

    It 'handles an empty run set without throwing' {
        { Build-DiagnosticBundleSummary -Runs @() } | Should -Not -Throw
        $result = Build-DiagnosticBundleSummary -Runs @()
        $result.PassCount | Should -Be 0
        $result.Lines.Count | Should -Be 0
    }
}

Describe 'Get-DiagnosticBundleZipPath' {
    It 'builds a Desktop-rooted path with computer name and timestamp' {
        $ts = Get-Date '2026-07-19 22:10:00'
        $path = Get-DiagnosticBundleZipPath -DesktopPath 'C:\Users\tech\Desktop' -ComputerName 'WKSTN-042' -Timestamp $ts
        $path | Should -Be 'C:\Users\tech\Desktop\NMM-Diagnostic-Bundle_WKSTN-042_20260719-221000.zip'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\diagnostic-bundle-helpers.tests.ps1 -CI`
Expected: FAIL — `Build-DiagnosticBundleSummary`/`Get-DiagnosticBundleZipPath` not recognized.

- [ ] **Step 3: Implement the helpers**

Create `src\core\11-diagnostic-bundle-helpers.ps1`:

```powershell
# Shared helpers for Invoke-DiagnosticBundle. Plain functions (no registry
# entries) so their pure logic (summary formatting, zip naming) is unit
# testable without mocking the system calls the bundle's checks make.

function Build-DiagnosticBundleSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Runs)

    $pass = @($Runs | Where-Object { $_.Status -eq 'Success' }).Count
    $warn = @($Runs | Where-Object { $_.Status -eq 'Warning' }).Count
    $fail = @($Runs | Where-Object { $_.Status -in 'Failed', 'Skipped' }).Count

    $lines = @()
    foreach ($run in ($Runs | Where-Object { $_.Status -in 'Warning', 'Failed', 'Skipped' })) {
        $tag = $run.Status.ToUpper()
        $lines += ('[{0}] {1,-28} - {2}' -f $tag, $run.Name, $run.Summary)
    }

    [PSCustomObject]@{
        PassCount = $pass
        WarnCount = $warn
        FailCount = $fail
        Lines     = $lines
    }
}

function Get-DiagnosticBundleZipPath {
    param(
        [Parameter(Mandatory)][string]$DesktopPath,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][datetime]$Timestamp
    )
    $name = 'NMM-Diagnostic-Bundle_{0}_{1:yyyyMMdd-HHmmss}.zip' -f $ComputerName, $Timestamp
    Join-Path $DesktopPath $name
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\diagnostic-bundle-helpers.tests.ps1 -CI`
Expected: PASS, all tests green.

- [ ] **Step 5: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds (new core file picked up automatically by numeric-order concatenation),
all tests green.

- [ ] **Step 6: Commit**

```bash
git add src/core/11-diagnostic-bundle-helpers.ps1 tests/diagnostic-bundle-helpers.tests.ps1
git commit -m "feat(core): add diagnostic bundle summary/zip-path helpers"
```

---

### Task 9: Invoke-DiagnosticBundle orchestrator tool

**Files:**
- Create: `src\tools\diagnostics\Invoke-DiagnosticBundle.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Consumes: `Start-ToolOutputCapture`/`Stop-ToolOutputCapture` (Task 1),
  `Export-TicketSummary -Runs` (Task 2), `Build-DiagnosticBundleSummary`/
  `Get-DiagnosticBundleZipPath` (Task 8), and the 11 check functions (existing tools plus Tasks
  3-7): `Get-EventLogErrors`, `Get-ReliabilityHistory`, `Get-WindowsUpdates`,
  `Get-DeviceManagerErrors`, `Get-NetworkDiagnostics`, `Get-AzureADHealthCheck`,
  `Get-GroupPolicyResult`, `Get-BSODCrashDumpParser`, `Get-CrashDumpInventory`,
  `Get-InstalledSoftware`, `Get-SystemUptime`, `Get-PendingRebootStatus`.
- Produces: `Invoke-DiagnosticBundle -Silent:$Silent`, registry `Id = 'diagnostic-bundle'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\diagnostics\Invoke-DiagnosticBundle.ps1`:

```powershell
function Invoke-DiagnosticBundle {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    $workDir = $null
    try {
        $run = New-ToolRun -Id 'diagnostic-bundle'

        $window = Read-ToolChoice -Prompt 'Time window for history-based checks' `
            -Choices @('24h', '7d') -Default '24h' -Silent:$Silent
        $hoursBack = 24
        if ($window -eq '7d') { $hoursBack = 168 }
        Write-ToolOutput ('Time window: {0} ({1}h)' -f $window, $hoursBack)

        $windowAware = 'Get-EventLogErrors', 'Get-ReliabilityHistory', 'Get-CrashDumpInventory'
        $checks = @(
            'Get-EventLogErrors',
            'Get-ReliabilityHistory',
            'Get-WindowsUpdates',
            'Get-DeviceManagerErrors',
            'Get-NetworkDiagnostics',
            'Get-AzureADHealthCheck',
            'Get-GroupPolicyResult',
            'Get-BSODCrashDumpParser',
            'Get-CrashDumpInventory',
            'Get-InstalledSoftware',
            'Get-SystemUptime',
            'Get-PendingRebootStatus'
        )

        $timestamp = Get-Date
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $workDir = Join-Path $env:TEMP ('NMMTools-Bundle-{0}-{1:yyyyMMdd-HHmmss}' -f $env:COMPUTERNAME, $timestamp)
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null

        $startIdx = $script:ToolRuns.Count
        foreach ($fn in $checks) {
            Write-ToolOutput ('Running {0}...' -f $fn) -Level Detail
            Start-ToolOutputCapture
            try {
                if ($windowAware -contains $fn) {
                    & $fn -Silent:$Silent -HoursBack $hoursBack
                } else {
                    & $fn -Silent:$Silent
                }
            } catch {
                Write-ToolOutput ('{0} threw: {1}' -f $fn, $_.Exception.Message) -Level Error
            }
            $raw = Stop-ToolOutputCapture
            $rawFile = Join-Path $workDir ('{0}.txt' -f $fn)
            Set-Content -Path $rawFile -Value $raw -Encoding UTF8
        }

        $bundleRuns = @($script:ToolRuns.GetRange($startIdx, $script:ToolRuns.Count - $startIdx))
        $summary = Build-DiagnosticBundleSummary -Runs $bundleRuns

        Write-ToolOutput ('Health summary   PASS {0}   WARN {1}   FAIL {2}' -f
            $summary.PassCount, $summary.WarnCount, $summary.FailCount)
        foreach ($line in $summary.Lines) { Write-ToolOutput ('  ' + $line) -Level Detail }

        $summaryLines = @()
        $summaryLines += 'NMM Diagnostic Bundle'
        $summaryLines += ('Time window: {0}' -f $window)
        $summaryLines += ('Health summary   PASS {0}   WARN {1}   FAIL {2}' -f
            $summary.PassCount, $summary.WarnCount, $summary.FailCount)
        $summaryLines += $summary.Lines
        $summaryLines += ''
        $summaryLines += (Export-TicketSummary -Runs $bundleRuns)
        $summaryFile = Join-Path $workDir 'summary.txt'
        Set-Content -Path $summaryFile -Value ($summaryLines -join "`r`n") -Encoding UTF8

        $zipPath = Get-DiagnosticBundleZipPath -DesktopPath $desktopPath -ComputerName $env:COMPUTERNAME -Timestamp $timestamp
        Compress-Archive -Path (Join-Path $workDir '*') -DestinationPath $zipPath -Force -ErrorAction Stop

        Write-ToolOutput ('Bundle: {0}' -f $zipPath) -Level Success

        Complete-ToolRun $run -Status Success -Summary (
            '{0} checks | PASS {1} WARN {2} FAIL {3} | {4}' -f
            $checks.Count, $summary.PassCount, $summary.WarnCount, $summary.FailCount, $zipPath)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
    finally {
        if ($workDir -and (Test-Path -LiteralPath $workDir)) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1`:

```powershell
        @{
            Id            = 'diagnostic-bundle'
            LegacyId      = '116'
            Name          = 'NMM Diagnostic Bundle'
            Category      = 'Diagnostics'
            Function      = 'Invoke-DiagnosticBundle'
            Description   = 'Runs a set of diagnostic checks and zips raw output plus a health summary and ticket-ready text to the Desktop'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('bundle', 'diagnostic', 'ticket', 'export', 'zip')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green (structural tests validate the new tool/registry entry
automatically; `tests\artifact.tests.ps1` smoke-tests the built `dist\NMMTools.ps1`).

- [ ] **Step 4: Manual smoke test**

Run:
```
pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool diagnostic-bundle -Silent -Mode Console
```
Expected: exit code 0; console shows the 12 checks running, a `Health summary PASS/WARN/FAIL`
line, and a `Bundle: C:\Users\<you>\Desktop\NMM-Diagnostic-Bundle_<COMPUTERNAME>_<timestamp>.zip`
line. Open the ZIP and confirm it contains 12 `<FunctionName>.txt` raw files plus `summary.txt`,
and that `summary.txt` ends with the same format as `Export-TicketSummary`'s existing output
(machine/user header, one `[STATUS] Name (duration)` line per check). Delete the test ZIP from
the Desktop afterward (it's a manual verification artifact, not something to keep).

- [ ] **Step 5: Commit**

```bash
git add src/tools/diagnostics/Invoke-DiagnosticBundle.ps1 src/registry/tools.psd1
git commit -m "feat(diagnostics): add NMM Diagnostic Bundle orchestrator tool"
```

---

### Task 10: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Full clean build**

Run: `.\build.ps1`
Expected: `Built ...\dist\NMMTools.ps1 (... KB, v9.1.0)` with no parse/analyzer errors.

- [ ] **Step 2: Full test suite**

Run: `Invoke-Pester .\tests -CI`
Expected: all tests pass, 0 failed (baseline was 134 passed before this plan; expect the
baseline plus every new test added in Tasks 1, 2, and 8).

- [ ] **Step 3: List the five new tools in the registry**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -ListTools | Select-String 'reliability-history|group-policy-result|device-manager-errors|wer-crash-inventory|diagnostic-bundle'`
Expected: all five listed under the `Diagnostics` category with `Risk = ReadOnly`.

- [ ] **Step 4: Note next steps for the user**

No commit in this task (nothing changes). Report to the user: implementation complete on branch
`codex/remote-business-tools`; shipping (build -> test -> copy to Desktop -> sync to the private
repo) is a separate, explicit step via the `/nmm-ship` skill per `CLAUDE.md` — not run as part of
this plan.
