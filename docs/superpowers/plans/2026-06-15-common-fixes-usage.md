# Usage-Based Common Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record each interactive tool run to a per-technician JSON file and render a top-6 `★ Common Fixes` section at the top of the landing menu, ordered by real usage.

**Architecture:** A new pure-ish persistence module `src/core/06-usage.ps1` (load/save/increment usage, robust to IO failure, test-overridable path); a one-line gated hook in `Complete-ToolRun` (`03-results.ps1`) that records a use only when the sink is interactive; and a render change in `Show-LandingMenu` (`05-ui-console.ps1`) that extracts a `Format-NmmToolCell` helper (shared with the category loop) and draws the Common Fixes section when usage exists.

**Tech Stack:** PowerShell 5.1, Pester 5, PSScriptAnalyzer (via `build.ps1`). Tests dot-source individual `src` files, so they run without building.

**Spec:** `docs/superpowers/specs/2026-06-15-common-fixes-usage-design.md`

**HARD CONSTRAINT - ASCII source:** `tests/encoding.tests.ps1` fails the suite if any `src/**/*.ps1` has a char > 127 (BOM excepted). The `★`/`▲` glyphs are produced with `[char]0x2605` / `[char]0x25B2` at runtime; never paste the literal glyph into a `src` file. Test files are not scanned, but use the `[char]` form there too for consistency.

**KEY GOTCHA - hashtable `.Count`:** the in-memory usage table maps id -> `@{ Count=...; Last=... }`. `$inner.Count` returns the number of keys (always 2), NOT the stored count. Always read the stored count with index syntax `$inner['Count']` (in the module AND the tests). Values read back from `ConvertFrom-Json` are `PSCustomObject`s where `.Count` is a real property - the index rule applies only to the internal hashtables.

---

## File Structure

- **Create** `src/core/06-usage.ps1` — `Get-NmmUsagePath`, `Import-NmmUsage`, `Add-NmmUsage`, `Get-NmmCommonFixes`. Pure data-access; no menu/render knowledge. The free `06` build slot.
- **Modify** `src/core/03-results.ps1` — one gated `Add-NmmUsage` call as the last statement of `Complete-ToolRun`.
- **Modify** `src/core/05-ui-console.ps1` — add `Format-NmmToolCell`; replace the inline category cell loop with it; render the Common Fixes section.
- **Create** `tests/usage.tests.ps1` — unit tests for the module.
- **Modify** `tests/results.tests.ps1` — dot-source `06-usage.ps1`, set a temp usage-path override, add the hook tests.
- **Modify** `tests/ui-console.tests.ps1` — dot-source `06-usage.ps1`, set a non-existent usage-path override (so existing tests see no section), add the render + `Format-NmmToolCell` tests.

Build order: `build.ps1` concatenates `src\core\*.ps1` by name, so `06-usage.ps1` lands between `05` and `07`. `05` calls `Get-NmmCommonFixes` (defined in `06`); functions resolve at call time, so order is fine in the artifact and in tests.

---

## Task 1: Usage store module

**Files:**
- Create: `src/core/06-usage.ps1`
- Create: `tests/usage.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/usage.tests.ps1`:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\06-usage.ps1')
    $script:RegistryData = @{ Tools = @(
        @{ Id='tool-a'; LegacyId='1'; Name='Tool A'; Category='Diagnostics'; Function='Invoke-A'; Description='a'; RequiresAdmin=$false; SilentCapable=$true; Risk='ReadOnly'; Tags=@('a') },
        @{ Id='tool-b'; LegacyId='2'; Name='Tool B'; Category='Diagnostics'; Function='Invoke-B'; Description='b'; RequiresAdmin=$false; SilentCapable=$true; Risk='ReadOnly'; Tags=@('b') },
        @{ Id='tool-c'; LegacyId='3'; Name='Tool C'; Category='Diagnostics'; Function='Invoke-C'; Description='c'; RequiresAdmin=$false; SilentCapable=$true; Risk='ReadOnly'; Tags=@('c') }
    ) }
}

Describe 'Usage store' {
    BeforeEach {
        $script:UsageFilePathOverride = Join-Path $env:TEMP ('nmm-usage-test-{0}.json' -f (Get-Random))
    }
    AfterEach {
        if ($script:UsageFilePathOverride -and (Test-Path $script:UsageFilePathOverride)) {
            Remove-Item $script:UsageFilePathOverride -Force -ErrorAction SilentlyContinue
        }
        $script:UsageFilePathOverride = $null
    }

    It 'records and reads back a count and timestamp' {
        Add-NmmUsage -Id 'tool-a'
        Add-NmmUsage -Id 'tool-a'
        $u = Import-NmmUsage
        $u['tool-a']['Count'] | Should -Be 2
        [string]::IsNullOrWhiteSpace($u['tool-a']['Last']) | Should -BeFalse
    }
    It 'returns an empty hashtable for a missing file' {
        (Import-NmmUsage).Count | Should -Be 0
    }
    It 'returns empty and does not throw on a corrupt file' {
        Set-Content -Path $script:UsageFilePathOverride -Value '{ not json' -Encoding UTF8
        { Import-NmmUsage } | Should -Not -Throw
        (Import-NmmUsage).Count | Should -Be 0
    }
    It 'ranks by count descending' {
        1..5 | ForEach-Object { Add-NmmUsage -Id 'tool-a' }
        1..2 | ForEach-Object { Add-NmmUsage -Id 'tool-b' }
        1..9 | ForEach-Object { Add-NmmUsage -Id 'tool-c' }
        $top = Get-NmmCommonFixes -Max 2
        @($top).Count | Should -Be 2
        $top[0].Id | Should -Be 'tool-c'
        $top[1].Id | Should -Be 'tool-a'
    }
    It 'breaks ties by most recent use' {
        Add-NmmUsage -Id 'tool-a'
        Start-Sleep -Milliseconds 20
        Add-NmmUsage -Id 'tool-b'
        (Get-NmmCommonFixes -Max 2)[0].Id | Should -Be 'tool-b'
    }
    It 'skips ids no longer in the registry' {
        Add-NmmUsage -Id 'ghost-tool'
        Add-NmmUsage -Id 'tool-a'
        @(Get-NmmCommonFixes -Max 6).Id | Should -Not -Contain 'ghost-tool'
        @(Get-NmmCommonFixes -Max 6).Id | Should -Contain 'tool-a'
    }
    It 'returns an empty array when there is no usage' {
        @(Get-NmmCommonFixes -Max 6).Count | Should -Be 0
    }
    It 'respects -Max' {
        foreach ($id in 'tool-a','tool-b','tool-c') { Add-NmmUsage -Id $id }
        @(Get-NmmCommonFixes -Max 2).Count | Should -Be 2
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\usage.tests.ps1 -Output Detailed`
Expected: FAIL — `Get-NmmUsagePath`/`Add-NmmUsage`/etc. not recognized.

- [ ] **Step 3: Write the minimal implementation**

Create `src/core/06-usage.ps1` (ASCII only):

```powershell
# Per-technician usage store (NMMTools\usage.json in %LOCALAPPDATA%). Records interactive tool
# runs and ranks the most-used for the menu's Common Fixes section. All IO failures are swallowed -
# usage tracking must never take down a tool run or the menu.

$script:UsageFilePathOverride = $null   # tests set this to a temp file

function Get-NmmUsagePath {
    if ($script:UsageFilePathOverride) { return $script:UsageFilePathOverride }
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
    return (Join-Path $base 'NMMTools\usage.json')
}

function Import-NmmUsage {
    # Returns @{ <toolId> = @{ Count = <int>; Last = <string 'o'> } }. Missing/corrupt -> @{}. Never throws.
    $path = Get-NmmUsagePath
    $table = @{}
    if (-not (Test-Path $path -PathType Leaf)) { return $table }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($json -and $json.Tools) {
            foreach ($p in $json.Tools.PSObject.Properties) {
                $table[$p.Name] = @{ Count = [int]$p.Value.Count; Last = [string]$p.Value.Last }
            }
        }
    } catch {
        return @{}
    }
    return $table
}

function Add-NmmUsage {
    # Increment a tool's count, stamp Last=now, persist. IO failure swallowed. Callers gate on sink.
    param([Parameter(Mandatory)][string]$Id)
    try {
        $table = Import-NmmUsage
        if ($table.ContainsKey($Id)) {
            $table[$Id]['Count'] = [int]$table[$Id]['Count'] + 1
        } else {
            $table[$Id] = @{ Count = 1; Last = '' }
        }
        $table[$Id]['Last'] = (Get-Date).ToString('o')
        $path = Get-NmmUsagePath
        $dir = Split-Path $path -Parent
        if ($dir -and -not (Test-Path $dir -PathType Container)) {
            New-Item -ItemType Directory -Force $dir -ErrorAction Stop | Out-Null
        }
        $obj = [PSCustomObject]@{ Version = 1; Tools = [PSCustomObject]$table }
        Set-Content -Path $path -Value ($obj | ConvertTo-Json -Depth 4) -Encoding UTF8 -ErrorAction Stop
    } catch {
        # drop the write, keep going
    }
}

function Get-NmmCommonFixes {
    # Top-$Max tools by usage (Count desc, then Last desc). Resolves ids against the live registry,
    # skipping ids no longer present. Returns @() when there is no usage.
    param([int]$Max = 6)
    $table = Import-NmmUsage
    if ($table.Count -eq 0) { return @() }
    $ranked = $table.GetEnumerator() | Sort-Object `
        @{ Expression = { [int]$_.Value['Count'] }; Descending = $true }, `
        @{ Expression = { [string]$_.Value['Last'] }; Descending = $true }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $ranked) {
        if ($out.Count -ge $Max) { break }
        $tool = Resolve-NmmTool -Query $entry.Key
        if ($tool) { [void]$out.Add($tool) }
    }
    return $out.ToArray()
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\usage.tests.ps1 -Output Detailed`
Expected: PASS — all 8 cases green.
Also run `Invoke-Pester .\tests\encoding.tests.ps1 -Output Detailed` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/06-usage.ps1 tests/usage.tests.ps1
git commit -m "feat: add per-technician usage store (06-usage.ps1)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Record a use in Complete-ToolRun

**Files:**
- Modify: `src/core/03-results.ps1` (add the hook at the end of `Complete-ToolRun`)
- Modify: `tests/results.tests.ps1` (dot-source 06, path override, 2 new tests)

- [ ] **Step 1: Write the failing test**

In `tests/results.tests.ps1`, edit the `BeforeAll` block. Change it from:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    Set-OutputSink -Sink Silent
```

to:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\06-usage.ps1')
    Set-OutputSink -Sink Silent
    $script:UsageFilePathOverride = Join-Path $env:TEMP ('nmm-usage-results-{0}.json' -f (Get-Random))
```

And change the `AfterAll` from:

```powershell
AfterAll {
    Set-OutputSink -Sink Console
}
```

to:

```powershell
AfterAll {
    Set-OutputSink -Sink Console
    if ($script:UsageFilePathOverride -and (Test-Path $script:UsageFilePathOverride)) {
        Remove-Item $script:UsageFilePathOverride -Force -ErrorAction SilentlyContinue
    }
    $script:UsageFilePathOverride = $null
}
```

Then append this new `Describe` at the end of the file (after the `Export-TicketSummary` describe):

```powershell
Describe 'Usage recording hook' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
        Mock Add-NmmUsage { }
    }
    It 'records a use when the sink is interactive (not Silent)' {
        Set-OutputSink -Sink Console
        try {
            $run = New-ToolRun -Id 'fake-tool'
            Complete-ToolRun $run -Status Success -Summary 'ok'
        } finally {
            Set-OutputSink -Sink Silent
        }
        Assert-MockCalled Add-NmmUsage -Times 1 -Scope It -ParameterFilter { $Id -eq 'fake-tool' }
    }
    It 'does not record a use under the Silent sink' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'ok'
        Assert-MockCalled Add-NmmUsage -Times 0 -Scope It
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\results.tests.ps1 -Output Detailed`
Expected: the `records a use when the sink is interactive` case FAILS (`Add-NmmUsage` called 0 times — the hook does not exist yet). The Silent case passes vacuously. Existing run-tracking/ticket cases still pass.

- [ ] **Step 3: Write the minimal implementation**

In `src/core/03-results.ps1`, in `Complete-ToolRun`, change the final lines from:

```powershell
    Write-ToolOutput ('[{0}] {1}' -f $Status.ToUpper(), $Summary) -Level $level
}
```

to:

```powershell
    Write-ToolOutput ('[{0}] {1}' -f $Status.ToUpper(), $Summary) -Level $level

    # Record the use for the menu's Common Fixes section - interactive runs only, so PDQ/-Silent
    # endpoint runs leave no usage file. Placed last so the null-run and duplicate-completion
    # early-returns above skip it. Add-NmmUsage swallows IO errors, so this cannot break a run.
    if ($script:OutputSink -ne 'Silent') {
        Add-NmmUsage -Id $Run.Id
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\results.tests.ps1 -Output Detailed`
Expected: PASS — both hook cases green; all pre-existing `results.tests` cases still pass.

- [ ] **Step 5: Commit**

```bash
git add src/core/03-results.ps1 tests/results.tests.ps1
git commit -m "feat: record interactive tool runs to the usage store

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Render the Common Fixes section

**Files:**
- Modify: `src/core/05-ui-console.ps1` (add `Format-NmmToolCell`; refactor the category cell loop; render the section)
- Modify: `tests/ui-console.tests.ps1` (dot-source 06, path override, 3 new tests)

- [ ] **Step 1: Write the failing test**

In `tests/ui-console.tests.ps1`, edit the `BeforeAll` block. Change it from:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\05-ui-console.ps1')
    Set-OutputSink -Sink Silent
```

to:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\05-ui-console.ps1')
    . (Join-Path $repoRoot 'src\core\06-usage.ps1')
    Set-OutputSink -Sink Silent
    # Point usage at a non-existent file so the un-mocked existing tests see no Common Fixes section.
    $script:UsageFilePathOverride = Join-Path $env:TEMP ('nmm-usage-ui-none-{0}.json' -f (Get-Random))
```

And in the `AfterAll` (currently `Set-OutputSink -Sink Console`), change it to:

```powershell
AfterAll {
    Set-OutputSink -Sink Console
    $script:UsageFilePathOverride = $null
}
```

Then append these two new `Describe` blocks at the end of the file:

```powershell
Describe 'Common Fixes section' {
    BeforeEach { $script:ToolRuns = New-Object System.Collections.ArrayList }

    It 'renders a Common Fixes section above the categories when usage exists' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '73' 'Repair' 'System Repair Suite' 'desc' 'Disruptive' $true)
        ) }
        Mock Get-NmmCommonFixes { @( (New-FakeTool '73' 'Repair' 'System Repair Suite' 'desc' 'Disruptive' $true) ) }
        $raw  = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'Common Fixes'
        $text | Should -Match 'System Repair Suite'
        ($text.IndexOf('Common Fixes')) | Should -BeLessThan ($text.IndexOf('Repair (1 tools)'))
    }

    It 'omits the Common Fixes section when there is no usage' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool '1' 'Diagnostics' 'System Information') ) }
        Mock Get-NmmCommonFixes { @() }
        $raw  = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Not -Match 'Common Fixes'
    }
}

Describe 'Format-NmmToolCell' {
    It 'right-aligns the risk/admin badge within the cell width' {
        $tri  = [char]0x25B2
        $cell = Format-NmmToolCell -Tool (New-FakeTool '73' 'Repair' 'SFC' 'd' 'Disruptive' $true) -CellMax 30
        $cell.Length | Should -BeLessOrEqual 30
        $cell | Should -Match '\[!\]'
        $cell | Should -Match ([regex]::Escape($tri))
    }
    It 'has no badge characters for a read-only tool' {
        $cell = Format-NmmToolCell -Tool (New-FakeTool '1' 'Diagnostics' 'System Info') -CellMax 30
        $cell | Should -Not -Match '\[M\]'
        $cell | Should -Not -Match '\[!\]'
    }
    It 'truncates a long name with an ellipsis and stays within the width' {
        $cell = Format-NmmToolCell -Tool (New-FakeTool '1' 'Diagnostics' ('X' * 100)) -CellMax 20
        $cell.Length | Should -BeLessOrEqual 20
        $cell | Should -Match '\.\.\.'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: FAIL on exactly the new cases — the two `Common Fixes section` cases fail (`Show-LandingMenu` does not render a section yet) and the `Format-NmmToolCell` cases fail (function not defined yet). All pre-existing `Show-LandingMenu`/routing cases still PASS, because `Show-LandingMenu` is unmodified at this point and the path override makes the real `Get-NmmCommonFixes` return `@()`.

- [ ] **Step 3: Write the minimal implementation**

In `src/core/05-ui-console.ps1`, FIRST add the `Format-NmmToolCell` function immediately before `function Show-LandingMenu {`. Change:

```powershell
function Show-LandingMenu {
```

to:

```powershell
function Format-NmmToolCell {
    # " <id>. <Name>" with a right-aligned risk/admin badge, fit to $CellMax. Truncates the label first.
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)][int]$CellMax)
    $badge = Get-NmmRiskBadge $Tool
    $label = ' {0,4}. {1}' -f $Tool.LegacyId, $Tool.Name
    if ($badge) {
        $room = $CellMax - $badge.Length - 1
        if ($room -lt 1) { $room = 1 }
        if ($label.Length -gt $room) { $label = $label.Substring(0, [math]::Max(0, $room - 3)) + '...' }
        return $label.PadRight($CellMax - $badge.Length) + $badge
    }
    if ($label.Length -gt $CellMax) { $label = $label.Substring(0, $CellMax - 3) + '...' }
    return $label
}

function Show-LandingMenu {
```

SECOND, replace the inline category cell loop. Change:

```powershell
        $cellMax = $colWidth - 1
        $cells = @()
        foreach ($t in $catTools) {
            $badge = Get-NmmRiskBadge $t
            $label = ' {0,4}. {1}' -f $t.LegacyId, $t.Name
            if ($badge) {
                $room = $cellMax - $badge.Length - 1
                if ($room -lt 1) { $room = 1 }
                if ($label.Length -gt $room) { $label = $label.Substring(0, [math]::Max(0, $room - 3)) + '...' }
                $cell = $label.PadRight($cellMax - $badge.Length) + $badge
            } else {
                $cell = $label
                if ($cell.Length -gt $cellMax) { $cell = $cell.Substring(0, $cellMax - 3) + '...' }
            }
            $cells += $cell
        }
```

to:

```powershell
        $cellMax = $colWidth - 1
        $cells = @()
        foreach ($t in $catTools) {
            $cells += Format-NmmToolCell -Tool $t -CellMax $cellMax
        }
```

THIRD, render the Common Fixes section. Change:

```powershell
    $bannerWidth = $columns * $colWidth

    foreach ($cat in $categories) {
```

to:

```powershell
    $bannerWidth = $columns * $colWidth

    $common = @(Get-NmmCommonFixes -Max 6)
    if ($common.Count -gt 0) {
        $cfColor = 'White'
        $inner = $bannerWidth - 2
        $bar = '+' + ('=' * $inner) + '+'
        $titleText = ('  {0}  Common Fixes' -f [char]0x2605)
        if ($titleText.Length -gt $inner) { $titleText = $titleText.Substring(0, $inner) }
        $titleLine = '|' + $titleText.PadRight($inner) + '|'
        Write-Host ''
        Write-Host $bar -ForegroundColor $cfColor
        Write-Host $titleLine -ForegroundColor $cfColor
        Write-Host $bar -ForegroundColor $cfColor
        $cfCellMax = $bannerWidth - 1
        foreach ($t in $common) {
            Write-Host (Format-NmmToolCell -Tool $t -CellMax $cfCellMax) -ForegroundColor $cfColor
        }
    }

    foreach ($cat in $categories) {
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: PASS — the new Common Fixes + `Format-NmmToolCell` cases are green, and every pre-existing `Show-LandingMenu` case (badges/legend, two-column, routing) still passes (rendered category output is unchanged by the refactor, and the override yields no section in those cases).

- [ ] **Step 5: Commit**

```bash
git add src/core/05-ui-console.ps1 tests/ui-console.tests.ps1
git commit -m "feat: render usage-based Common Fixes section in landing menu

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Full suite + build verification

**Files:** none changed (verification only)

- [ ] **Step 1: Run the full Pester suite**

Run: `Invoke-Pester .\tests -Output Detailed`
Expected: PASS — every test file green. Baseline was 104; this feature adds 8 (usage) + 2 (results hook) + 3 (ui-console) = ~117. Note the new total. Pay attention that NO test wrote to the real `%LOCALAPPDATA%\NMMTools\usage.json` (all usage tests use a temp override).

- [ ] **Step 2: Run the build (parse + analyzer gates)**

Run: `.\build.ps1`
Expected: `Built ...\dist\NMMTools.ps1 (... KB, v9.0.0-dev)` with no error output; PSScriptAnalyzer reports no Error-severity findings. (`Get-`/`Import-`/`Add-` are approved verbs; no `Write-Host` in `06-usage.ps1`.)

- [ ] **Step 3: Manual smoke (optional, on your own machine)**

From the built artifact, interactively run a couple of tools (e.g. `.\dist\NMMTools.ps1`, pick `1` then `20`, exit with `X`), then relaunch the menu. Expected: a `★ Common Fixes` section appears at the top listing the tools you just ran, with their badges; the same tools still appear in their category sections below; typing a number still runs the tool. Then run `.\dist\NMMTools.ps1 -Tool system-uptime -Silent` and confirm it writes NOTHING to `%LOCALAPPDATA%\NMMTools\usage.json` (silent runs are not recorded). NOTE: this writes a real `usage.json` under your `%LOCALAPPDATA%` — harmless, but delete it if you want a clean slate.

- [ ] **Step 4: Commit any artifact (only if dist/ is tracked)**

`dist/` is git-ignored (`.gitignore` contains `dist/`), so there is nothing to commit. Skip.

---

## Notes for the implementer

- **Why the path override exists:** `Get-NmmUsagePath` returns `$script:UsageFilePathOverride` when set. Tests set it to a temp (or non-existent) path so they never read or write the technician's real `%LOCALAPPDATA%` usage file. Always reset it to `$null` in teardown.
- **Hashtable `.Count` trap (again):** in `Add-NmmUsage` and `Get-NmmCommonFixes`, read the stored count via `$table[$Id]['Count']` / `$_.Value['Count']`, never `.Count`. The tests assert `$u['tool-a']['Count']` for the same reason.
- **Existing menu tests stay green** because the refactor produces byte-identical category cells (the logic just moved into `Format-NmmToolCell`) and the override makes the real `Get-NmmCommonFixes` return `@()` in those tests (no section). The new render tests `Mock Get-NmmCommonFixes` to force a section / force empty.
- **Silent safety:** the `Complete-ToolRun` hook is gated on `$script:OutputSink -ne 'Silent'`, so PDQ/`-Silent` endpoint runs never write a usage file. `dispatch.tests` runs under the Silent sink, so it needs no change.
- **ASCII only** in `src` — the `★` and `▲` are emitted via `[char]0x2605` / `[char]0x25B2`. If `encoding.tests` fails, you pasted a literal glyph.
- Tests dot-source `src` directly; only run `build.ps1` in Task 4.
