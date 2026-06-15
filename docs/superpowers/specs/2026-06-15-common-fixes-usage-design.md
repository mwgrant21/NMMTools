# Usage-Based Common Fixes - Design Spec

**Date:** 2026-06-15
**Scope:** Add a per-technician usage store and surface a `★ Common Fixes` section at the top of the
interactive landing menu, listing the tech's most-used tools (by real usage, not a curated list).
Interactive menu only; PDQ/`-Silent` endpoint runs are unaffected and leave no artifacts.
**Status:** Approved (brainstormed with Matt 2026-06-15). Next: writing-plans -> implementation plan.

## Context

The toolkit menu (`Show-LandingMenu` in `src/core/05-ui-console.ps1`) lists every tool by category. There is
no fast path to the handful of tools a technician actually reaches for every day. Session run tracking
exists (`$script:ToolRuns` in `src/core/03-results.ps1`) but is in-memory and per-session - it is lost on
exit, so it cannot drive a "most-used" list.

We add a small persistence layer that records each interactive tool run to a JSON file in the technician's
local profile, and a ranked read that the menu renders as a pinned section. The curation is fully derived
from real usage - there is no hand-maintained list (options "registry flag" and "curated seed" were
considered and declined in brainstorming).

The core files are numbered `01,02,03,04,05,07,08`; the free `06` slot holds the new usage module.

## Decisions made with Matt (do not re-litigate)

1. **Usage-derived, not curated.** The list is the top-N tools by recorded usage count.
2. **Local per-technician store.** `%LOCALAPPDATA%\NMMToolkit\usage.json`. "What WE use" = what THIS tech
   runs most. No network share, no shared/aggregated store.
3. **Pure usage, grows organically.** Show up to N most-used; show fewer if fewer have been used; if none
   have been used, **omit the section entirely** (menu looks exactly like today).
4. **Interactive runs only.** Record a use only when `$script:OutputSink -ne 'Silent'`. PDQ/`-Silent`
   endpoint runs do NOT write a usage file (no new artifacts in SYSTEM context).
5. **N = 6**, **single-column** section, ranked **count desc, then most-recent-use (Last) desc**.
6. **Marker `★` (U+2605)** in the banner, produced via `[char]0x2605` (source stays ASCII; Windows Terminal
   renders it). Badge `▲` (U+25B2) convention from the prior menu work is reused unchanged.
7. **Common Fixes is an additional shortcut, not a move** - listed tools still appear in their real category
   section below; ids are unchanged so typing `45` runs the same tool.

## New behavior

### Component 1 - Usage store: new `src/core/06-usage.ps1`

Pure data-access; no menu/registry-rendering knowledge. Path is overridable for tests.

**PowerShell gotcha (must follow):** the internal in-memory representation is a hashtable whose values are
themselves hashtables `@{ Count=...; Last=... }`. `$hashtable.Count` returns the *number of keys*, not a
`Count` entry - so the stored count MUST be read with index syntax `['Count']` (never `.Count`). This applies
in the module AND in the tests. Values read back from `ConvertFrom-Json` are `PSCustomObject`s, where
`.Count`/`.Last` are unambiguous real properties.

```
$script:UsageFilePathOverride = $null   # tests set this to a temp file

function Get-NmmUsagePath {
    # %LOCALAPPDATA%\NMMToolkit\usage.json, or the test override, or %TEMP% if LOCALAPPDATA is unavailable.
    if ($script:UsageFilePathOverride) { return $script:UsageFilePathOverride }
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
    return (Join-Path $base 'NMMTools\usage.json')
}

function Import-NmmUsage {
    # Returns a hashtable @{ <toolId> = @{ Count = <int>; Last = <string 'o'> } }.
    # Missing / corrupt / unreadable file -> empty hashtable. NEVER throws.
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
        # Corrupt/locked file must never break the menu; treat as no history.
        return @{}
    }
    return $table
}

function Add-NmmUsage {
    # Increment a tool's count and stamp Last=now, then persist. Any IO failure is swallowed
    # (usage tracking must never take down a run). Callers gate on the output sink (see Component 2).
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
    # Top-$Max tools by usage. Sorted Count desc, then Last desc (recency tiebreak). Resolves each id
    # against the live registry and SKIPS ids no longer present. Returns @() when there is no usage.
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

`[PSCustomObject]$table` where `$table` is a hashtable produces an object whose properties are the tool ids -
the exact shape `Import-NmmUsage` reads back via `$json.Tools.PSObject.Properties`. Round-trips cleanly.

### Component 2 - Record a use: hook in `src/core/03-results.ps1`

As the LAST statement of `Complete-ToolRun` (after the final `Write-ToolOutput` completion line), add:

```powershell
    if ($script:OutputSink -ne 'Silent') {
        Add-NmmUsage -Id $Run.Id
    }
```

Placing it last means the two early `return`s already in `Complete-ToolRun` - the null-run guard and the
duplicate-completion guard - skip it, so neither a null run nor a double-completion records a use.
`Complete-ToolRun` is the single choke point every run passes through, and `$Run.Id` is the registry id the
tool passed to `New-ToolRun` (verified: tools call e.g. `New-ToolRun -Id 'system-uptime'`). The `Silent`
gate keeps PDQ/`-Silent` endpoint runs from writing usage files. `Add-NmmUsage` itself swallows IO errors,
so this line cannot break a run.

### Component 3 - Render: `Show-LandingMenu` in `src/core/05-ui-console.ps1`

**Refactor (removes duplication that this feature would otherwise double):** extract the existing
badge-aware cell builder from the category loop into a helper, used by BOTH the category cells and the new
Common Fixes cells:

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
```

The category loop's inline cell construction (current lines ~121-134) is replaced by
`$cells += Format-NmmToolCell -Tool $t -CellMax $cellMax`. Rendered output is byte-for-byte unchanged, so the
existing `Show-LandingMenu` tests keep passing.

Then, in `Show-LandingMenu`, AFTER `$bannerWidth` is computed (current line ~101) and BEFORE the category
`foreach` (current line ~103), render the Common Fixes section when it is non-empty:

```powershell
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
```

Single column at full banner width, in `White` (a neutral "pinned" highlight distinct from the category
colors; the `★` label disambiguates it from any category). When `$common` is empty the block emits nothing -
the menu is identical to today.

Visual:

```
+================================================================+
|  ★  Common Fixes                                               |
+================================================================+
   45. Outlook Profile Repair  [M]▲
   Q2. Teams Quick Fix
   11. Temp Files Cleanup       [M]▲
+================================================================+
|  Diagnostics (23 tools)                                        |
...
```

### Unchanged

`Get-NmmRiskBadge`, `Get-CategoryColor`, `Get-NmmLegacyIdSortKey`, `Format-MenuColumns`, the banner/width/
two-column category layout, `Invoke-ToolWithGate`, `Invoke-MenuSelection`, the `Recent:` line (session
recency, complementary to all-time frequency), `T`/`X`, and every `-Tool`/`-Silent`/`-ListTools`/PDQ path.

## Files

- Create: `src/core/06-usage.ps1` - `Get-NmmUsagePath`, `Import-NmmUsage`, `Add-NmmUsage`,
  `Get-NmmCommonFixes`.
- Modify: `src/core/03-results.ps1` - one gated `Add-NmmUsage` call in `Complete-ToolRun`.
- Modify: `src/core/05-ui-console.ps1` - add `Format-NmmToolCell`; replace the inline category cell build
  with it; render the Common Fixes section in `Show-LandingMenu`.
- Create: `tests/usage.tests.ps1`.
- Modify: `tests/results.tests.ps1` - dot-source `06-usage.ps1`; add the usage-hook cases.
- Modify: `tests/ui-console.tests.ps1` - dot-source `06-usage.ps1`; add Common Fixes render cases (mocking
  `Get-NmmCommonFixes`); add a `Format-NmmToolCell` describe.

`build.ps1` concatenates `src\core\*.ps1` in name order, so `06-usage.ps1` lands between `05` and `07`
automatically; `05` calls `Get-NmmCommonFixes` (defined in `06`) but functions resolve at call time, so
order is fine in the built artifact and in tests (which dot-source the needed files).

## Testing

### `tests/usage.tests.ps1` (new)
Set `$script:UsageFilePathOverride` to a unique `$env:TEMP` file in `BeforeEach`; remove it and reset the
override to `$null` in `AfterEach`. Dot-source `04-dispatch.ps1` (for `Resolve-NmmTool`) and `06-usage.ps1`,
and seed `$script:RegistryData` with a few fake tools.

1. **Add/Import round-trip:** `Add-NmmUsage 'system-uptime'` twice then `$u = Import-NmmUsage` ->
   `$u['system-uptime']['Count'] | Should -Be 2` and `$u['system-uptime']['Last']` is non-empty. (Use index
   access `['Count']`, not `.Count` - see the gotcha note above.)
2. **Missing file:** with the override pointed at a non-existent path, `Import-NmmUsage` returns an empty
   hashtable and does not throw.
3. **Corrupt file:** write `'{ not json'` to the override path; `Import-NmmUsage` returns empty, no throw.
4. **Ranking:** seed counts (e.g. A=5, B=2, C=9 via repeated `Add-NmmUsage`); `Get-NmmCommonFixes -Max 2`
   returns C then A (count desc).
5. **Recency tiebreak:** two ids with equal counts but different `Last` -> the more recent one ranks first.
6. **Skips unknown ids:** record a use for an id absent from the registry; `Get-NmmCommonFixes` does not
   include it (resolves to `$null` and is skipped).
7. **Empty:** no usage -> `Get-NmmCommonFixes` returns an empty array.
8. **Max respected:** record 8 distinct used tools; `Get-NmmCommonFixes -Max 6` returns 6.

### `tests/results.tests.ps1` (modified)
Dot-source `06-usage.ps1` in `BeforeAll` and set `$script:UsageFilePathOverride` to a temp file (reset in
`AfterAll`) so no test can touch the real `%LOCALAPPDATA%`.

9. **Records when interactive:** `Mock Add-NmmUsage`; within the test set `Set-OutputSink -Sink Console`,
   run `New-ToolRun`/`Complete-ToolRun`, assert `Add-NmmUsage` called once with the run's id; restore
   `Set-OutputSink -Sink Silent`.
10. **Does not record when Silent:** under the default Silent sink, `Complete-ToolRun` does not call the
    mocked `Add-NmmUsage` (Times 0).
    (Existing run-tracking tests are unaffected because they run under the Silent sink.)

### `tests/ui-console.tests.ps1` (modified)
Dot-source `06-usage.ps1` in `BeforeAll`.

11. **Section renders:** `Mock Get-NmmCommonFixes { @( <a Disruptive admin fake tool> ) }`; `Show-LandingMenu`
    output contains `Common Fixes`, the tool's name, and its `[!]`/`▲` badge, and the section appears before
    the first category banner.
12. **Section omitted when empty:** `Mock Get-NmmCommonFixes { @() }`; output does NOT contain `Common Fixes`.
13. **`Format-NmmToolCell`:** a Disruptive admin tool yields a cell containing `[!]` and `▲` within `$CellMax`;
    a ReadOnly tool yields a cell with no badge chars; long names are truncated with `...`.

`build.ps1` must compile and PSScriptAnalyzer stay error-clean. Full suite (currently 97) is recomputed.

## Out of scope

- Shared/team-aggregated usage, network stores, or roaming sync (decided: local per-tech).
- A curated/seed list, manual pinning, or a `Common` registry flag (decided: pure usage).
- Counting `-Silent`/PDQ endpoint runs; usage decay/half-life; showing run counts next to entries.
- Configurable N or section color via CLI (hard-coded 6 / White; trivially changed later).
- Any change to dispatch, the registry schema, tool behavior, or the `-Tool`/`-Silent`/`-ListTools` paths.
