# Two-Column Color-Coded Landing Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the landing menu to a v8-style two-column, title-only, color-coded-by-category layout (boxed colored banner per category, tools in two column-major columns).

**Architecture:** Rewrite the `Show-LandingMenu` render body in `src/core/05-ui-console.ps1`; remove the now-unused `Get-WrappedLines`; add two small testable helpers (`Get-CategoryColor`, `Format-MenuColumns`); keep `Get-NmmLegacyIdSortKey`, `Start-ConsoleMenu`, `Invoke-MenuSelection`, search, and ticket export unchanged. Rewrite `tests/ui-console.tests.ps1` to match.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs/superpowers/specs/2026-06-14-two-column-color-menu-design.md`

---

## Conventions

- PS 5.1 only; approved verbs (`Get-`/`Format-`/`Show-`/`Start-`/`Invoke-` are approved). The helpers are top-level core functions (core is exempt from the `src\tools`-only registry test, like `Get-BrowserProfiles`).
- ASCII-only source, UTF-8 **with BOM**, trailing newline.
- Colour is a `Write-Host -ForegroundColor` argument and is NOT in captured text - so it is tested via `Get-CategoryColor` (returns the mapped colour name), not via rendered output. The two-column packing is tested via `Format-MenuColumns` directly (deterministic), not via `Show-LandingMenu` (its column count depends on console width).
- Build + test:
  ```powershell
  Import-Module Pester -MinimumVersion 5.0
  & "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
  Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
  ```
- Single-line `-m` commits.

## File Structure

- Modify (full rewrite): `src/core/05-ui-console.ps1`
- Modify (full rewrite): `tests/ui-console.tests.ps1`

---

### Task 1: Rewrite the ui-console tests for the two-column layout (TDD)

**Files:**
- Modify: `tests/ui-console.tests.ps1`

- [ ] **Step 1: Replace the ENTIRE file** `tests/ui-console.tests.ps1` with exactly this content:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\05-ui-console.ps1')
    Set-OutputSink -Sink Silent

    function New-FakeTool {
        param([string]$Legacy, [string]$Category, [string]$Name, [string]$Desc = 'fake description')
        @{ Id = "fake-$Legacy"; LegacyId = "$Legacy"; Name = $Name; Category = $Category
           Function = "Invoke-Fake$Legacy"; Description = $Desc; RequiresAdmin = $false
           SilentCapable = $true; Risk = 'ReadOnly'; Tags = @('fake') }
    }
}

AfterAll {
    Set-OutputSink -Sink Console
}

Describe 'Get-NmmLegacyIdSortKey' {
    It 'sorts numeric ids as integers' {
        (Get-NmmLegacyIdSortKey '9') | Should -BeLessThan (Get-NmmLegacyIdSortKey '10')
    }
    It 'sorts Q ids after numeric ids and in Q order' {
        (Get-NmmLegacyIdSortKey '106') | Should -BeLessThan (Get-NmmLegacyIdSortKey 'Q1')
        (Get-NmmLegacyIdSortKey 'Q1')  | Should -BeLessThan (Get-NmmLegacyIdSortKey 'Q9')
    }
    It 'does not throw on an unexpected id' {
        { Get-NmmLegacyIdSortKey 'weird' } | Should -Not -Throw
    }
}

Describe 'Get-CategoryColor' {
    It 'maps each category to its v8 color' {
        (Get-CategoryColor 'Diagnostics') | Should -Be 'Cyan'
        (Get-CategoryColor 'Cloud')       | Should -Be 'Yellow'
        (Get-CategoryColor 'Repair')      | Should -Be 'Red'
        (Get-CategoryColor 'Laptop')      | Should -Be 'Green'
        (Get-CategoryColor 'Browser')     | Should -Be 'White'
        (Get-CategoryColor 'User')        | Should -Be 'Blue'
        (Get-CategoryColor 'Security')    | Should -Be 'DarkYellow'
        (Get-CategoryColor 'QuickFix')    | Should -Be 'Magenta'
    }
    It 'falls back to Gray for an unknown category' {
        (Get-CategoryColor 'Nope') | Should -Be 'Gray'
    }
    It 'returns valid ConsoleColor names' {
        foreach ($cat in @('Browser','Cloud','Diagnostics','Laptop','QuickFix','Repair','Security','User','Nope')) {
            { [System.ConsoleColor](Get-CategoryColor $cat) } | Should -Not -Throw
        }
    }
}

Describe 'Format-MenuColumns' {
    It 'packs cells column-major' {
        $rows = Format-MenuColumns -Cells @('A','B','C','D','E') -Columns 2 -ColumnWidth 5
        @($rows).Count | Should -Be 3
        $rows[0] | Should -Match 'A'
        $rows[0] | Should -Match 'D'
        $rows[1] | Should -Match 'B'
        $rows[1] | Should -Match 'E'
        $rows[2] | Should -Match 'C'
        $rows[2] | Should -Not -Match 'D'
    }
    It 'puts the left half in column 1 and the right half in column 2' {
        $rows = Format-MenuColumns -Cells @('one','two','three','four') -Columns 2 -ColumnWidth 8
        $rows[0] | Should -Match 'one'
        $rows[0] | Should -Match 'three'
        $rows[1] | Should -Match 'two'
        $rows[1] | Should -Match 'four'
    }
    It 'returns an empty array for no cells' {
        @(Format-MenuColumns -Cells @() -Columns 2 -ColumnWidth 10).Count | Should -Be 0
    }
    It 'uses one cell per row with a single column' {
        @(Format-MenuColumns -Cells @('a','b','c') -Columns 1 -ColumnWidth 10).Count | Should -Be 3
    }
}

Describe 'Show-LandingMenu two-column layout' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
    }

    It 'lists every tool title under a category banner with a count, without descriptions' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '1'  'Diagnostics' 'System Information'      'UNIQUEDESCTOKEN'),
            (New-FakeTool '2'  'Diagnostics' 'Disk Space Analysis'    'another desc'),
            (New-FakeTool '54' 'User'        'Windows Search Rebuild'  'yet another')
        ) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'System Information'
        $text | Should -Match 'Disk Space Analysis'
        $text | Should -Match 'Windows Search Rebuild'
        $text | Should -Match 'Diagnostics \(2 tools\)'
        $text | Should -Match 'User \(1 tools\)'
        $text | Should -Not -Match 'UNIQUEDESCTOKEN'
    }

    It 'renders Q-prefixed QuickFix ids without throwing and returns nothing' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool 'Q1' 'QuickFix' 'Office Quick Fix'),
            (New-FakeTool 'Q9' 'QuickFix' 'Browser Backup Quick Fix')
        ) }
        $script:result = 'sentinel'
        { $script:result = Show-LandingMenu 6>$null } | Should -Not -Throw
        $script:result | Should -BeNullOrEmpty
    }

    It 'shows the run/search/exit hint' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool '1' 'Diagnostics' 'System Information') ) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'Q3'
        $text | Should -Match 'X = exit'
    }
}
```

- [ ] **Step 2: Run the new tests against the CURRENT code to confirm they fail.** Run:

```powershell
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests\ui-console.tests.ps1" -Output Minimal
```

Expected: FAILURES (`Get-CategoryColor` and `Format-MenuColumns` don't exist yet; the current menu still prints descriptions, so the `UNIQUEDESCTOKEN` "not match" assertion fails). Do NOT commit yet.

---

### Task 2: Rewrite `src/core/05-ui-console.ps1`

**Files:**
- Modify: `src/core/05-ui-console.ps1`

- [ ] **Step 1: Replace the ENTIRE file** `src/core/05-ui-console.ps1` with exactly this content:

```powershell
# Console UI. Landing screen lists EVERY tool in two color-coded columns grouped under
# a v8-style banner per category; everything is driven by the registry, so new tools
# appear automatically. Run a tool by typing its number/Q#/Id, or type text to search.

function Get-NmmLegacyIdSortKey {
    # Sortable key for a LegacyId: numeric ids first (as integers), then Q# ids in
    # Q1..Q9 order, then anything unexpected. Never throws on a non-numeric id.
    param([Parameter(Mandatory)][string]$LegacyId)
    if ($LegacyId -match '^\d+$') { return [int]$LegacyId }
    if ($LegacyId -match '^Q(\d+)$') { return 1000 + [int]$Matches[1] }
    return 100000
}

function Get-CategoryColor {
    # Map a category to its v8 section colour (a valid [ConsoleColor] name). Gray for unknown.
    param([Parameter(Mandatory)][string]$Category)
    switch ($Category) {
        'Browser'     { 'White' }
        'Cloud'       { 'Yellow' }
        'Diagnostics' { 'Cyan' }
        'Laptop'      { 'Green' }
        'QuickFix'    { 'Magenta' }
        'Repair'      { 'Red' }
        'Security'    { 'DarkYellow' }
        'User'        { 'Blue' }
        default       { 'Gray' }
    }
}

function Format-MenuColumns {
    # Pack pre-formatted cell strings into $Columns column-major columns.
    # rows = ceil(N / Columns); row r, column c -> Cells[c*rows + r]. Non-last columns
    # are PadRight($ColumnWidth); each row is TrimEnd()'d. Returns string[] (empty when no cells).
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Cells,
        [Parameter(Mandatory)][int]$Columns,
        [Parameter(Mandatory)][int]$ColumnWidth
    )
    if ($Columns -lt 1) { $Columns = 1 }
    $out = New-Object System.Collections.Generic.List[string]
    $n = $Cells.Count
    if ($n -eq 0) { return $out.ToArray() }
    $rows = [int][math]::Ceiling($n / [double]$Columns)
    for ($r = 0; $r -lt $rows; $r++) {
        $line = ''
        for ($c = 0; $c -lt $Columns; $c++) {
            $idx = $c * $rows + $r
            if ($idx -lt $n) {
                if ($c -lt ($Columns - 1)) {
                    $line += $Cells[$idx].PadRight($ColumnWidth)
                } else {
                    $line += $Cells[$idx]
                }
            }
        }
        $out.Add($line.TrimEnd())
    }
    return $out.ToArray()
}

function Show-LandingMenu {
    # Clear only in a real interactive console - never during tests (Silent sink) or headless runs.
    if ($script:OutputSink -ne 'Silent' -and [Environment]::UserInteractive) {
        try { Clear-Host } catch { }
    }
    $tools = Get-NmmTools
    $categories = @($tools | ForEach-Object { $_.Category } | Sort-Object -Unique)

    Write-Host ''
    Write-Host ('=' * 66) -ForegroundColor Cyan
    Write-Host (' NMM System Toolkit v9      {0}\{1}' -f $env:COMPUTERNAME, $env:USERNAME) -ForegroundColor Cyan
    Write-Host ('=' * 66) -ForegroundColor Cyan
    if ($script:ToolRuns.Count -gt 0) {
        $recent = @($script:ToolRuns | Select-Object -Last 3 | ForEach-Object { $_.Name })
        Write-Host (' Recent: {0}' -f ($recent -join ' | ')) -ForegroundColor DarkGray
    }

    # Layout width; falls back to 80 in a redirected/headless host. Two columns when wide enough.
    $width = 80
    try { $cw = [Console]::WindowWidth; if ($cw -and $cw -gt 0) { $width = [int]$cw } } catch { $width = 80 }
    $usable = $width - 1
    if ($usable -lt 40) { $usable = 40 }
    $columns = 2
    if ($usable -lt 72) { $columns = 1 }
    $colWidth = [int][math]::Floor($usable / $columns)
    if ($colWidth -lt 30) { $colWidth = 30 }
    $bannerWidth = $columns * $colWidth

    foreach ($cat in $categories) {
        $color = Get-CategoryColor $cat
        $catTools = @($tools | Where-Object { $_.Category -eq $cat } | Sort-Object { Get-NmmLegacyIdSortKey $_.LegacyId })

        # v8-style boxed banner in the category colour.
        $inner = $bannerWidth - 2
        $bar = '+' + ('=' * $inner) + '+'
        $titleText = ('  {0} ({1} tools)' -f $cat, $catTools.Count)
        if ($titleText.Length -gt $inner) { $titleText = $titleText.Substring(0, $inner) }
        $titleLine = '|' + $titleText.PadRight($inner) + '|'
        Write-Host ''
        Write-Host $bar -ForegroundColor $color
        Write-Host $titleLine -ForegroundColor $color
        Write-Host $bar -ForegroundColor $color

        # One cell per tool: " <id>. <Name>", truncated to fit a column.
        $cellMax = $colWidth - 1
        $cells = @()
        foreach ($t in $catTools) {
            $cell = ' {0,4}. {1}' -f $t.LegacyId, $t.Name
            if ($cell.Length -gt $cellMax) { $cell = $cell.Substring(0, $cellMax - 3) + '...' }
            $cells += $cell
        }
        foreach ($row in (Format-MenuColumns -Cells $cells -Columns $columns -ColumnWidth $colWidth)) {
            Write-Host $row -ForegroundColor $color
        }
    }

    Write-Host ''
    Write-Host ' Enter: tool number (e.g. 54 or Q3) | search text' -ForegroundColor Gray
    Write-Host '        T = save session summary (for tickets)   X = exit' -ForegroundColor Gray
}

function Invoke-MenuSelection {
    param([Parameter(Mandatory)][string]$Selection)
    $tool = Resolve-NmmTool -Query $Selection
    if ($tool) {
        Invoke-NmmTool -Tool $tool | Out-Null
        Read-Host 'Press Enter to continue' | Out-Null
        return
    }
    $found = @(Search-NmmTools -Term $Selection)
    if ($found.Count -eq 0) {
        Write-Host (" Nothing matches '{0}'." -f $Selection) -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host (' Matches for "{0}":' -f $Selection) -ForegroundColor Cyan
    foreach ($t in $found) {
        Write-Host (' {0,4}. {1}  ({2})' -f $t.LegacyId, $t.Name, $t.Category)
    }
    $pick = Read-Host ' Tool number to run (Enter to cancel)'
    if (-not [string]::IsNullOrWhiteSpace($pick)) {
        $tool = Resolve-NmmTool -Query $pick.Trim()
        if ($tool) {
            Invoke-NmmTool -Tool $tool | Out-Null
            Read-Host 'Press Enter to continue' | Out-Null
        } else {
            Write-Host (" '{0}' did not match any tool number. Enter the number shown in the list." -f $pick.Trim()) -ForegroundColor Yellow
            Read-Host ' Press Enter to go back' | Out-Null
        }
    }
}

function Start-ConsoleMenu {
    if (-not [Environment]::UserInteractive) {
        Write-Host 'ERROR: the menu requires an interactive console. Use -Tool <id> [-Silent] for unattended use.' -ForegroundColor Red
        return
    }
    while ($true) {
        Show-LandingMenu
        $selection = Read-Host ' Select tool number/Q#, search text, or X to exit'
        if ([string]::IsNullOrWhiteSpace($selection)) { continue }
        $selection = $selection.Trim()
        if ($selection -match '^[Xx]$') { return }
        if ($selection -match '^[Tt]$') {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $desktop = [Environment]::GetFolderPath('Desktop')   # KFM/OneDrive-redirect aware
            $path = Join-Path $desktop ('NMM-TicketSummary-{0}.txt' -f $stamp)
            $text = Export-TicketSummary
            Write-Host $text
            try {
                Set-Content -Path $path -Value $text -Encoding UTF8 -ErrorAction Stop
                Write-Host (' Saved to {0}' -f $path) -ForegroundColor Green
            } catch {
                Write-Host (' Warning: could not save to {0} - {1}' -f $path, $_) -ForegroundColor Yellow
            }
            Read-Host ' Press Enter to continue' | Out-Null
            continue
        }
        Invoke-MenuSelection -Selection $selection
    }
}
```

Note vs the just-merged file: `Get-WrappedLines` is gone; `Get-CategoryColor` and `Format-MenuColumns` are added; `Show-LandingMenu`'s tool listing is now a colored boxed banner + two column-major columns of titles (no descriptions, no `[admin]`). `Get-NmmLegacyIdSortKey`, `Invoke-MenuSelection`, and `Start-ConsoleMenu` are unchanged.

---

### Task 3: Encoding, build, full suite, commit

- [ ] **Step 1: Fix encoding on both edited files** (UTF-8 BOM + CRLF + trailing newline):

```powershell
foreach ($f in @(
    "$env:USERPROFILE\Desktop\NMMToolkit\src\core\05-ui-console.ps1",
    "$env:USERPROFILE\Desktop\NMMToolkit\tests\ui-console.tests.ps1"
)) {
    $txt = (Get-Content -LiteralPath $f -Raw) -replace "`r`n","`n" -replace "`n","`r`n"
    if ($txt[-1] -ne "`n") { $txt += "`r`n" }
    [System.IO.File]::WriteAllText($f, $txt, (New-Object System.Text.UTF8Encoding($true)))
}
```

- [ ] **Step 2: Build and run the full suite.** Run:

```powershell
Import-Module Pester -MinimumVersion 5.0
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```

Expected: build succeeds (Parser + PSScriptAnalyzer errors clean); ALL tests pass. Note the new total count.

- [ ] **Step 3: (Optional manual smoke - not gating)** Build then run the artifact interactively and eyeball the colors/columns:

```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\dist\NMMTools.ps1"
```

Expect: each category as a colored boxed banner (Diagnostics cyan, Cloud yellow, Repair red, Laptop green, Browser white, User blue, Security dark-yellow, QuickFix magenta) with its tools in two columns, titles only; typing `54` runs Windows Search Rebuild, `Q3` runs the Teams quick fix, search and `X` work. (Needs an interactive elevated console; skip headless.)

- [ ] **Step 4: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(ui): two-column color-coded landing menu (v8 style, titles only)"
```

---

## Self-Review (controller, after all tasks)

- **Spec coverage:** two-column title-only render (`Show-LandingMenu`); category->color map (`Get-CategoryColor`, all 8 + Gray default); column-major packing (`Format-MenuColumns`); v8 boxed banner with count; width-adaptive 1/2 columns; descriptions + `[admin]` dropped; `Get-WrappedLines` removed; sort key + selection loop + search + ticket unchanged.
- **Name consistency:** `Get-CategoryColor`, `Format-MenuColumns`, `Get-NmmLegacyIdSortKey` referenced identically in tests and implementation; `Format-MenuColumns` params (`-Cells`/`-Columns`/`-ColumnWidth`) match between call site and definition.
- **Test design:** colour verified via `Get-CategoryColor`; column-major via `Format-MenuColumns`; `Show-LandingMenu` asserts width-independent facts (names present, banner count, description token absent, returns nothing). The `$script:result` pattern escapes the `Should -Not -Throw` child scope.
- **No tool/registry/CLI change;** both edited files re-encoded before build.

## Final review + finish

After Task 3, dispatch a reviewer (constrained `general-purpose`: "output ONLY your review; do not modify files/memory/commit") over the `05-ui-console.ps1` diff + new tests (focus: `Format-MenuColumns` column-major correctness + no out-of-range index, `Get-CategoryColor` values all castable to `[ConsoleColor]`, width fallback + 1-column path, banner truncation safe, and that search/ticket/`-Tool` paths are unaffected), fix anything it flags, then use **superpowers:finishing-a-development-branch** to merge `two-column-color-menu` to master locally (single-line `-m`).
