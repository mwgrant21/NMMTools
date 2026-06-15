# Console Menu Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the registry's `Risk`/`RequiresAdmin`/`Description` metadata in the interactive console menu via risk/admin badges, a Yes/No confirm gate before tools that change the system run, and a single-hit search shortcut.

**Architecture:** All changes live in `src/core/05-ui-console.ps1` plus its test file. Two new pure-ish helpers (`Get-NmmRiskBadge`, `Invoke-ToolWithGate` with its `Show-ToolBrief`) are added; `Show-LandingMenu` gets a new cell format + legend; `Invoke-MenuSelection` routes every run through the gate and adds the single-hit shortcut. The confirm reuses the existing `Read-ToolChoice` (from `02-output.ps1`), which already degrades safely on non-interactive hosts. No registry, dispatch, tool, or CLI changes.

**Tech Stack:** PowerShell 5.1, Pester 5, PSScriptAnalyzer (via `build.ps1`). Tests dot-source individual `src/core` files, so they run without building.

**Spec:** `docs/superpowers/specs/2026-06-15-console-menu-polish-design.md`

---

## File Structure

- **Modify** `src/core/05-ui-console.ps1`
  - Add `Get-NmmRiskBadge` — tool → badge glyph string. Pure, no I/O.
  - Add `Show-ToolBrief` — prints the pre-confirm brief (the one place risk is colored).
  - Add `Invoke-ToolWithGate` — the single interactive run path (gate + run + pause).
  - Change `Show-LandingMenu` — cell build now appends a right-aligned badge; add a legend line.
  - Change `Invoke-MenuSelection` — route both the direct hit and the search-pick through `Invoke-ToolWithGate`; add the single-hit shortcut.
- **Modify** `tests/ui-console.tests.ps1`
  - Extend the `New-FakeTool` fixture with `Risk`/`Admin` params (backward-compatible).
  - Add `Describe` blocks for `Get-NmmRiskBadge`, `Invoke-ToolWithGate`, `Invoke-MenuSelection routing`.
  - Extend the `Show-LandingMenu` describe with a badges/legend case.

**Conventions to follow (from the existing file):** functions are top-level in the core file; non-ASCII glyphs are produced with `[char]0x25B2` (keeps source ASCII so the analyzer/encoding tests stay clean); tests use the `New-FakeTool` fixture and capture `Write-Host` with `6>&1`.

---

## Task 1: `Get-NmmRiskBadge` helper

**Files:**
- Modify: `src/core/05-ui-console.ps1` (add function near `Get-CategoryColor`)
- Test: `tests/ui-console.tests.ps1` (new `Describe`)

- [ ] **Step 1: Write the failing test**

Add this `Describe` to `tests/ui-console.tests.ps1` after the `Get-CategoryColor` describe (around line 53):

```powershell
Describe 'Get-NmmRiskBadge' {
    It 'returns empty for a read-only non-admin tool' {
        Get-NmmRiskBadge @{ Risk = 'ReadOnly'; RequiresAdmin = $false } | Should -Be ''
    }
    It 'returns [M] for a Modifies tool and [!] for a Disruptive tool' {
        Get-NmmRiskBadge @{ Risk = 'Modifies';   RequiresAdmin = $false } | Should -Be '[M]'
        Get-NmmRiskBadge @{ Risk = 'Disruptive'; RequiresAdmin = $false } | Should -Be '[!]'
    }
    It 'appends the admin marker when RequiresAdmin' {
        $tri = [char]0x25B2
        Get-NmmRiskBadge @{ Risk = 'Modifies';   RequiresAdmin = $true } | Should -Be ('[M]' + $tri)
        Get-NmmRiskBadge @{ Risk = 'Disruptive'; RequiresAdmin = $true } | Should -Be ('[!]' + $tri)
    }
    It 'shows only the admin marker for a read-only admin tool' {
        $tri = [char]0x25B2
        Get-NmmRiskBadge @{ Risk = 'ReadOnly'; RequiresAdmin = $true } | Should -Be ([string]$tri)
    }
    It 'returns empty for unknown/missing risk and does not throw' {
        { Get-NmmRiskBadge @{ RequiresAdmin = $false } } | Should -Not -Throw
        Get-NmmRiskBadge @{ Risk = 'Weird'; RequiresAdmin = $false } | Should -Be ''
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: FAIL — `The term 'Get-NmmRiskBadge' is not recognized`.

- [ ] **Step 3: Write the minimal implementation**

Add to `src/core/05-ui-console.ps1` immediately after `Get-CategoryColor` (after line 28):

```powershell
function Get-NmmRiskBadge {
    # Short glyph badge for a tool in the landing list. ReadOnly/unknown risk -> no risk glyph;
    # Modifies -> [M]; Disruptive -> [!]. Appends a U+25B2 admin marker when RequiresAdmin.
    # Pure string output (no console I/O); never throws.
    param([Parameter(Mandatory)]$Tool)
    $badge = switch ("$($Tool.Risk)") {
        'Modifies'   { '[M]' }
        'Disruptive' { '[!]' }
        default      { '' }
    }
    if ($Tool.RequiresAdmin) { $badge += [char]0x25B2 }
    return $badge
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: PASS — the `Get-NmmRiskBadge` describe is green; all pre-existing describes still pass.

- [ ] **Step 5: Commit**

```bash
git add src/core/05-ui-console.ps1 tests/ui-console.tests.ps1
git commit -m "feat: add Get-NmmRiskBadge for menu risk/admin badges

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `Show-ToolBrief` + `Invoke-ToolWithGate` (the gated run path)

**Files:**
- Modify: `src/core/05-ui-console.ps1` (add both functions before `Invoke-MenuSelection`)
- Test: `tests/ui-console.tests.ps1` (new `Describe`)

- [ ] **Step 1: Write the failing test**

Add this `Describe` to `tests/ui-console.tests.ps1` after the `Get-NmmRiskBadge` describe:

```powershell
Describe 'Invoke-ToolWithGate' {
    BeforeEach {
        $script:RegistryData = @{ Tools = @() }
        Mock Invoke-NmmTool { 'Success' }
        Mock Read-Host { '' }
    }
    It 'runs a read-only tool without prompting' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='RO'; Category='Diagnostics'; Risk='ReadOnly'; RequiresAdmin=$false; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Read-ToolChoice -Times 0 -Scope It
        Assert-MockCalled Invoke-NmmTool  -Times 1 -Scope It
    }
    It 'does not run a disruptive tool when the user answers No' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='Boom'; Category='Repair'; Risk='Disruptive'; RequiresAdmin=$true; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Read-ToolChoice -Times 1 -Scope It
        Assert-MockCalled Invoke-NmmTool  -Times 0 -Scope It
    }
    It 'runs a disruptive tool when the user answers Yes' {
        Mock Read-ToolChoice { 'Yes' }
        $tool = @{ Id='t'; Name='Boom'; Category='Repair'; Risk='Disruptive'; RequiresAdmin=$true; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Invoke-NmmTool -Times 1 -Scope It
    }
    It 'prompts risky tools with a default of No' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='Mod'; Category='Repair'; Risk='Modifies'; RequiresAdmin=$false; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Read-ToolChoice -Times 1 -Scope It -ParameterFilter { $Default -eq 'No' }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: FAIL — `The term 'Invoke-ToolWithGate' is not recognized` (or CommandNotFound during mock setup).

- [ ] **Step 3: Write the minimal implementation**

Add to `src/core/05-ui-console.ps1` immediately before `function Invoke-MenuSelection` (before line 122):

```powershell
function Show-ToolBrief {
    # Pre-confirm brief for a risky tool. The Risk word is the one colored element:
    # Yellow for Modifies, Red for Disruptive.
    param([Parameter(Mandatory)]$Tool)
    $riskColor = switch ("$($Tool.Risk)") {
        'Disruptive' { 'Red' }
        'Modifies'   { 'Yellow' }
        default      { 'Gray' }
    }
    $dashes = [math]::Max(3, 44 - $Tool.Name.Length)
    Write-Host ''
    Write-Host (' -- {0} {1}' -f $Tool.Name, ('-' * $dashes)) -ForegroundColor Cyan
    $adminText = ''
    if ($Tool.RequiresAdmin) { $adminText = '   (admin)' }
    Write-Host ('   Category : {0}      Risk: ' -f $Tool.Category) -ForegroundColor Gray -NoNewline
    Write-Host ('{0}{1}' -f $Tool.Risk, $adminText) -ForegroundColor $riskColor
    if (-not [string]::IsNullOrWhiteSpace($Tool.Description)) {
        Write-Host ('   {0}' -f $Tool.Description) -ForegroundColor Gray
    }
}

function Invoke-ToolWithGate {
    # Single interactive run path. Read-only tools run immediately; Modifies/Disruptive tools
    # show a brief and require a Yes/No confirm (default No) before running. Returns nothing.
    param([Parameter(Mandatory)]$Tool)
    if ($Tool.Risk -eq 'Modifies' -or $Tool.Risk -eq 'Disruptive') {
        Show-ToolBrief -Tool $Tool
        $answer = Read-ToolChoice -Prompt 'Run this tool?' -Choices @('Yes','No') -Default 'No'
        if ($answer -ne 'Yes') {
            Write-ToolOutput ' Cancelled.' -Level Detail
            return
        }
    }
    Invoke-NmmTool -Tool $Tool | Out-Null
    Read-Host 'Press Enter to continue' | Out-Null
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: PASS — the four `Invoke-ToolWithGate` cases are green; earlier describes still pass.

- [ ] **Step 5: Commit**

```bash
git add src/core/05-ui-console.ps1 tests/ui-console.tests.ps1
git commit -m "feat: add Invoke-ToolWithGate risk-confirm run path

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Badges + legend in `Show-LandingMenu`

**Files:**
- Modify: `src/core/05-ui-console.ps1` (`Show-LandingMenu` cell loop, lines ~104-119)
- Test: `tests/ui-console.tests.ps1` (extend `New-FakeTool` + add a case)

- [ ] **Step 1: Extend the fixture and write the failing test**

First, replace the `New-FakeTool` fixture in the `BeforeAll` block (lines 9-14) with this backward-compatible version (adds `$Risk`/`$Admin`, defaults preserve every existing test):

```powershell
    function New-FakeTool {
        param([string]$Legacy, [string]$Category, [string]$Name, [string]$Desc = 'fake description',
              [string]$Risk = 'ReadOnly', [bool]$Admin = $false)
        @{ Id = "fake-$Legacy"; LegacyId = "$Legacy"; Name = $Name; Category = $Category
           Function = "Invoke-Fake$Legacy"; Description = $Desc; RequiresAdmin = $Admin
           SilentCapable = $true; Risk = $Risk; Tags = @('fake') }
    }
```

Then add this `It` inside the existing `Describe 'Show-LandingMenu two-column layout'` block (after the last `It`, before its closing brace at line 119):

```powershell
    It 'shows risk/admin badges and a legend, and no badge for read-only tools' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '73' 'Repair'      'System Repair Suite' 'desc' 'Disruptive' $true),
            (New-FakeTool '1'  'Diagnostics' 'System Information'   'desc' 'ReadOnly'   $false)
        ) }
        $raw  = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $tri  = [char]0x25B2

        $repairRow = ($text -split "`n" | Where-Object { $_ -match 'System Repair Suite' }) -join ''
        $repairRow | Should -Match '\[!\]'
        $repairRow | Should -Match ([regex]::Escape($tri))

        $roRow = ($text -split "`n" | Where-Object { $_ -match 'System Information' }) -join ''
        $roRow | Should -Not -Match '\[M\]'
        $roRow | Should -Not -Match '\[!\]'
        $roRow | Should -Not -Match ([regex]::Escape($tri))

        $text | Should -Match 'Legend:'
        $text | Should -Match '\[!\] disruptive'
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: FAIL — the new case fails because `$repairRow` does not contain `[!]` and the text has no `Legend:` line yet.

- [ ] **Step 3: Write the minimal implementation**

In `src/core/05-ui-console.ps1`, replace the cell-building loop in `Show-LandingMenu` (lines 104-111):

```powershell
        # One cell per tool: " <id>. <Name>", truncated to fit a column.
        $cellMax = $colWidth - 1
        $cells = @()
        foreach ($t in $catTools) {
            $cell = ' {0,4}. {1}' -f $t.LegacyId, $t.Name
            if ($cell.Length -gt $cellMax) { $cell = $cell.Substring(0, $cellMax - 3) + '...' }
            $cells += $cell
        }
```

with this badge-aware version:

```powershell
        # One cell per tool: " <id>. <Name>" plus a right-aligned risk/admin badge, fit to a column.
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

Then replace the footer hint block (lines 117-119):

```powershell
    Write-Host ''
    Write-Host ' Enter: tool number (e.g. 54 or Q3) | search text' -ForegroundColor Gray
    Write-Host '        T = save session summary (for tickets)   X = exit' -ForegroundColor Gray
```

with one that adds the legend line:

```powershell
    Write-Host ''
    Write-Host ' Enter: tool number (e.g. 54 or Q3) | search text' -ForegroundColor Gray
    Write-Host '        T = save session summary (for tickets)   X = exit' -ForegroundColor Gray
    Write-Host ('        Legend: [M] modifies  [!] disruptive  {0} needs admin' -f [char]0x25B2) -ForegroundColor DarkGray
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: PASS — the new badges/legend case is green, and the existing `Show-LandingMenu` cases (titles present, descriptions absent, `Q#` ids, hint line) still pass.

- [ ] **Step 5: Commit**

```bash
git add src/core/05-ui-console.ps1 tests/ui-console.tests.ps1
git commit -m "feat: render risk/admin badges and legend in landing menu

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Route `Invoke-MenuSelection` through the gate + single-hit shortcut

**Files:**
- Modify: `src/core/05-ui-console.ps1` (`Invoke-MenuSelection`, lines ~122-151)
- Test: `tests/ui-console.tests.ps1` (new `Describe`)

- [ ] **Step 1: Write the failing test**

Add this `Describe` to `tests/ui-console.tests.ps1` after the `Show-LandingMenu` describe:

```powershell
Describe 'Invoke-MenuSelection routing' {
    BeforeEach {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '1'  'Diagnostics' 'System Information'),
            (New-FakeTool '2'  'Diagnostics' 'Disk Space Analysis'),
            (New-FakeTool '54' 'User'        'Windows Search Rebuild')
        ) }
        Mock Invoke-ToolWithGate { }
        Mock Read-Host { '' }
    }
    It 'routes a direct number through the gate' {
        Invoke-MenuSelection -Selection '1'
        Assert-MockCalled Invoke-ToolWithGate -Times 1 -Scope It
    }
    It 'runs the single search hit through the gate without a pick prompt' {
        Invoke-MenuSelection -Selection 'Disk Space'
        Assert-MockCalled Invoke-ToolWithGate -Times 1 -Scope It
        Assert-MockCalled Read-Host -Times 0 -Scope It
    }
    It 'lists multiple matches and routes the chosen pick through the gate' {
        Mock Read-Host { '1' }
        Invoke-MenuSelection -Selection 'fake'
        Assert-MockCalled Invoke-ToolWithGate -Times 1 -Scope It
    }
    It 'shows a match list when several tools match' {
        $out = Invoke-MenuSelection -Selection 'fake' 6>&1
        ($out | ForEach-Object { "$_" }) -join "`n" | Should -Match 'Matches for'
    }
    It 'prints a not-found message for no matches' {
        $out = Invoke-MenuSelection -Selection 'zzzzz' 6>&1
        ($out | ForEach-Object { "$_" }) -join "`n" | Should -Match 'Nothing matches'
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: FAIL — the single-hit case fails (current code lists the one match and waits on `Read-Host` instead of calling `Invoke-ToolWithGate`), and the direct-number case fails (current code calls `Invoke-NmmTool`, not `Invoke-ToolWithGate`).

- [ ] **Step 3: Write the minimal implementation**

In `src/core/05-ui-console.ps1`, replace the whole `Invoke-MenuSelection` function (lines 122-151) with:

```powershell
function Invoke-MenuSelection {
    param([Parameter(Mandatory)][string]$Selection)
    $tool = Resolve-NmmTool -Query $Selection
    if ($tool) { Invoke-ToolWithGate -Tool $tool; return }

    $found = @(Search-NmmTools -Term $Selection)
    if ($found.Count -eq 0) {
        Write-Host (" Nothing matches '{0}'." -f $Selection) -ForegroundColor Yellow
        return
    }
    if ($found.Count -eq 1) { Invoke-ToolWithGate -Tool $found[0]; return }

    Write-Host ''
    Write-Host (' Matches for "{0}":' -f $Selection) -ForegroundColor Cyan
    foreach ($t in $found) {
        Write-Host (' {0,4}. {1}  ({2})' -f $t.LegacyId, $t.Name, $t.Category)
    }
    $pick = Read-Host ' Tool number to run (Enter to cancel)'
    if (-not [string]::IsNullOrWhiteSpace($pick)) {
        $tool = Resolve-NmmTool -Query $pick.Trim()
        if ($tool) {
            Invoke-ToolWithGate -Tool $tool
        } else {
            Write-Host (" '{0}' did not match any tool number. Enter the number shown in the list." -f $pick.Trim()) -ForegroundColor Yellow
            Read-Host ' Press Enter to go back' | Out-Null
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\ui-console.tests.ps1 -Output Detailed`
Expected: PASS — all five routing cases are green; every earlier describe still passes.

- [ ] **Step 5: Commit**

```bash
git add src/core/05-ui-console.ps1 tests/ui-console.tests.ps1
git commit -m "feat: route menu selection through gate; single-hit search shortcut

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Full build + suite verification

**Files:** none changed (verification only)

- [ ] **Step 1: Run the full Pester suite**

Run: `Invoke-Pester .\tests -Output Detailed`
Expected: PASS — every test file green (the 8 untouched files plus the extended `ui-console.tests.ps1`). Note the new total passing count.

- [ ] **Step 2: Run the build (parse gate + analyzer gate)**

Run: `.\build.ps1`
Expected: build succeeds, `dist\NMMTools.ps1` is regenerated, PSScriptAnalyzer reports no errors. If the analyzer flags the new functions, fix the finding and re-run before continuing.

- [ ] **Step 3: Manual smoke (optional but recommended)**

Run: `.\dist\NMMTools.ps1`
Expected: landing menu shows badges (e.g. Repair tools end with `[M]`/`[!]` and `▲`), the legend line appears under the hint; selecting a `ReadOnly` tool runs immediately; selecting a `Disruptive` tool shows the brief and a `Run this tool? [Yes/No] (default: No)` prompt; pressing Enter (default No) returns to the menu without running. Press `X` to exit.

- [ ] **Step 4: Commit the rebuilt artifact**

```bash
git add dist/NMMTools.ps1
git commit -m "build: regenerate dist artifact with menu polish

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

(If `dist/` is git-ignored — check `.gitignore` — skip this commit; the build output is not tracked.)

---

## Notes for the implementer

- **Why `[char]0x25B2` instead of a literal `▲`:** the repo has an encoding test and an analyzer gate; keeping source ASCII avoids codepage/BOM surprises in the concatenated `dist`. The character is produced at runtime for both the badge and the legend.
- **Why the gate reuses `Read-ToolChoice`:** it already handles a non-interactive host by returning the `-Default` (here `No`), so the confirm can never hang or accidentally run a destructive tool in a headless context.
- **Tests dot-source `src/core/*` directly** (see the `BeforeAll`), so you do not need to run `build.ps1` between test iterations — only in Task 5 for the parse/analyzer gates.
- **Mocking note:** `Invoke-ToolWithGate`, `Invoke-NmmTool`, `Read-ToolChoice`, and `Read-Host` are all in session scope after the dot-sourcing, so Pester `Mock` works against them directly. Always pass `-Scope It` to `Assert-MockCalled`.
