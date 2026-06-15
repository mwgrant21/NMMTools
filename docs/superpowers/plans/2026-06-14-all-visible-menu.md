# All-Visible Landing Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the v9 category-letter drill-in landing menu with a single all-visible listing that shows every tool grouped under category headers with its full wrapped description; run a tool by typing its number/`Q#`/Id, or type text to search.

**Architecture:** Self-contained rewrite of `src/core/05-ui-console.ps1` (new `Show-LandingMenu`, two new top-level core helpers, simplified `Start-ConsoleMenu`, `Show-CategoryTools` removed) plus a rewrite of `tests/ui-console.tests.ps1`. No registry, tool, dispatch, or `-Tool`/`-Silent` changes.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs/superpowers/specs/2026-06-14-all-visible-menu-design.md`

---

## Conventions

- PS 5.1 only; approved verbs only (`Get-`/`Show-`/`Start-`/`Invoke-` are approved). The two new helpers are **top-level core functions** (like `Get-BrowserProfiles`/`Get-NmmTools`), not nested - so the unit tests can call them directly. Core functions are exempt from the registry-mapping test (it scans `src\tools` only).
- ASCII-only source, UTF-8 **with BOM**, trailing newline (encoding test covers all of `src`).
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

### Task 1: Rewrite the ui-console tests for the new contract (TDD)

**Files:**
- Modify: `tests/ui-console.tests.ps1`

- [ ] **Step 1: Replace the entire file** `tests/ui-console.tests.ps1` with exactly this content:

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

Describe 'Show-LandingMenu all-visible layout' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
    }

    It 'lists every tool name and its description, grouped by category header with counts' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '1'  'Diagnostics' 'System Information'      'os hardware summary'),
            (New-FakeTool '2'  'Diagnostics' 'Disk Space Analysis'    'per volume capacity'),
            (New-FakeTool '54' 'User'        'Windows Search Rebuild'  'restart wsearch rebuild index')
        ) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'System Information'
        $text | Should -Match 'os hardware summary'
        $text | Should -Match 'Disk Space Analysis'
        $text | Should -Match 'Windows Search Rebuild'
        $text | Should -Match 'restart wsearch rebuild index'
        $text | Should -Match '-- Diagnostics \(2 tools\) --'
        $text | Should -Match '-- User \(1 tools\) --'
    }

    It 'returns no value (no category-letter map)' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool '1' 'Diagnostics' 'A'), (New-FakeTool '2' 'Cloud' 'B') ) }
        $result = Show-LandingMenu 6>$null
        $result | Should -BeNullOrEmpty
    }

    It 'orders tools within a category by LegacyId, numeric before Q#, without throwing on Q ids' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool 'Q3' 'QuickFix' 'QF Three'),
            (New-FakeTool 'Q1' 'QuickFix' 'QF One'),
            (New-FakeTool '10' 'QuickFix' 'Ten'),
            (New-FakeTool '2'  'QuickFix' 'Two')
        ) }
        $raw = $null
        { $raw = Show-LandingMenu 6>&1 } | Should -Not -Throw
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text.IndexOf('Two')    | Should -BeLessThan $text.IndexOf('Ten')
        $text.IndexOf('Ten')    | Should -BeLessThan $text.IndexOf('QF One')
        $text.IndexOf('QF One') | Should -BeLessThan $text.IndexOf('QF Three')
    }

    It 'flags admin tools and shows the run/search/exit hint' {
        $admin = New-FakeTool '93' 'Security' 'Defender Status'
        $admin.RequiresAdmin = $true
        $script:RegistryData = @{ Tools = @($admin) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'Defender Status \[admin\]'
        $text | Should -Match 'Q3'
        $text | Should -Match 'X = exit'
    }
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

Describe 'Get-WrappedLines' {
    It 'wraps text to the given width without exceeding it' {
        $lines = Get-WrappedLines -Text 'the quick brown fox jumps over the lazy dog' -Width 15
        @($lines).Count | Should -BeGreaterThan 1
        foreach ($l in $lines) { $l.Length | Should -BeLessOrEqual 15 }
    }
    It 'returns an empty array for blank text' {
        @(Get-WrappedLines -Text '   ' -Width 40).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the new tests against the CURRENT code to confirm they fail.** Run:

```powershell
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests\ui-console.tests.ps1" -Output Minimal
```

Expected: FAILURES (the current `Show-LandingMenu` returns a `$map` and uses category/flat modes; `Get-NmmLegacyIdSortKey`/`Get-WrappedLines` don't exist yet). This proves the tests exercise the new behavior. Do NOT commit yet.

---

### Task 2: Rewrite `src/core/05-ui-console.ps1`

**Files:**
- Modify: `src/core/05-ui-console.ps1`

- [ ] **Step 1: Replace the entire file** `src/core/05-ui-console.ps1` with exactly this content:

```powershell
# Console UI. Landing screen lists EVERY tool grouped under category headers with
# full (wrapped) descriptions; everything is driven by the registry, so new tools
# appear automatically. Run a tool by typing its number/Q#/Id, or type text to search.

function Get-NmmLegacyIdSortKey {
    # Sortable key for a LegacyId: numeric ids first (as integers), then Q# ids in
    # Q1..Q9 order, then anything unexpected. Never throws on a non-numeric id.
    param([Parameter(Mandatory)][string]$LegacyId)
    if ($LegacyId -match '^\d+$') { return [int]$LegacyId }
    if ($LegacyId -match '^Q(\d+)$') { return 1000 + [int]$Matches[1] }
    return 100000
}

function Get-WrappedLines {
    # Greedily word-wrap $Text to lines no wider than $Width. Returns a string[]
    # (possibly empty); blank/whitespace input yields an empty array.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$Width
    )
    if ($Width -lt 1) { $Width = 1 }
    $words = @($Text -split '\s+' | Where-Object { $_ -ne '' })
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($w in $words) {
        if ($current -eq '') {
            $current = $w
        } elseif (($current.Length + 1 + $w.Length) -le $Width) {
            $current = $current + ' ' + $w
        } else {
            $lines.Add($current)
            $current = $w
        }
    }
    if ($current -ne '') { $lines.Add($current) }
    return $lines.ToArray()
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

    # Width for description wrapping; falls back to 80 in a redirected/headless host.
    $width = 80
    try { $cw = [Console]::WindowWidth; if ($cw -and $cw -gt 0) { $width = [int]$cw } } catch { $width = 80 }
    $descIndent = '       '   # 7 spaces: aligns the wrapped description under the tool name
    $descWidth = $width - $descIndent.Length - 1
    if ($descWidth -lt 30) { $descWidth = 30 }

    foreach ($c in $categories) {
        $catTools = @($tools | Where-Object { $_.Category -eq $c } | Sort-Object { Get-NmmLegacyIdSortKey $_.LegacyId })
        Write-Host ''
        Write-Host (' -- {0} ({1} tools) --' -f $c, $catTools.Count) -ForegroundColor Cyan
        foreach ($t in $catTools) {
            $admin = ''
            if ($t.RequiresAdmin) { $admin = ' [admin]' }
            Write-Host (' {0,4}. {1}{2}' -f $t.LegacyId, $t.Name, $admin)
            foreach ($line in (Get-WrappedLines -Text $t.Description -Width $descWidth)) {
                Write-Host ($descIndent + $line) -ForegroundColor DarkGray
            }
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

Note vs the old file: `Show-LandingMenu` no longer returns a `$map` or branches flat/category; `Show-CategoryTools` is removed; `Start-ConsoleMenu` drops the `$map.ContainsKey`/letter branch; `Invoke-MenuSelection` is unchanged.

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

Expected: build succeeds (Parser + PSScriptAnalyzer errors clean); ALL tests pass (the rewritten ui-console cases now pass; the other 8 files unchanged). Note the new total test count.

- [ ] **Step 3: (Optional manual smoke - not gating)** Build then run the artifact interactively and eyeball the landing screen:

```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\dist\NMMTools.ps1"
```

Expect: a single screen listing all categories with every tool + wrapped description; typing `54` runs Windows Search Rebuild, `Q3` runs the Teams quick fix, a search term lists matches, `X` exits. (This needs an interactive elevated console; skip in headless runs and rely on the green suite.)

- [ ] **Step 4: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(ui): all-visible landing menu (every tool + description; drop category drill-in)"
```

---

## Self-Review (controller, after all tasks)

- **Spec coverage:** all-visible grouped listing with full wrapped descriptions (Task 2 `Show-LandingMenu`); robust LegacyId sort fixing the `[int]'Q1'` crash (`Get-NmmLegacyIdSortKey`); guarded `Clear-Host`; width-aware wrapping with 80 fallback (`Get-WrappedLines` + inline width); simplified loop with no letter branch (`Start-ConsoleMenu`); `Show-CategoryTools` removed; tests rewritten (Task 1).
- **Name consistency:** `Get-NmmLegacyIdSortKey` and `Get-WrappedLines` are referenced identically in the test file and the implementation.
- **No tool/registry/CLI change:** only `05-ui-console.ps1` and `ui-console.tests.ps1` are touched.
- **Encoding:** both files re-encoded UTF-8 BOM + trailing newline before the build.

## Final review + finish

After Task 3, dispatch a reviewer (constrained `general-purpose`: "output ONLY your review; do not modify files/memory/commit") over the `05-ui-console.ps1` diff + the new tests (focus: `-Silent`/test-safety of the guarded `Clear-Host`, the sort key never throwing, wrap-width fallback, and that search/ticket/`-Tool` paths are unaffected), fix anything it flags, then use **superpowers:finishing-a-development-branch** to merge `all-visible-menu` to master locally (single-line `-m`).
