# Console Menu Polish - Risk Badges & Gated Run - Design Spec

**Date:** 2026-06-15
**Scope:** Surface registry metadata already present (`Risk`, `RequiresAdmin`, `Description`) in the
interactive console menu via **risk/admin badges**, a **risk-gated run confirm** for tools that change the
system, and a **single-hit search shortcut**. Interactive console only; no registry/tool/dispatch/CLI
changes. All edits in `src/core/05-ui-console.ps1`, reusing `Read-ToolChoice` from `02-output.ps1`.
**Status:** Approved (brainstormed with Matt 2026-06-15). Next: writing-plans -> implementation plan.

## Context

v9 is at full v8 parity (100 tools, 8 categories). The landing menu (`Show-LandingMenu` in
`src/core/05-ui-console.ps1`) renders every tool as `{LegacyId}. {Name}` in two color-coded columns
(see `2026-06-14-two-column-color-menu-design.md`). The registry (`src/registry/tools.psd1`) already
carries `Risk` (`ReadOnly`/`Modifies`/`Disruptive`), `RequiresAdmin`, `Description`, and `Tags` per tool,
but the menu surfaces none of it: a disruptive repair looks identical to a read-only check, and typing a
number runs the tool immediately with no preview. `Search-NmmTools` (dispatch) **already** matches Name +
Description + Tags, so symptom search works; the gap is purely in how results and risk are presented.

The prior two-column spec deliberately dropped the `[admin]` marker ("just the title; trivially restorable
later"). This spec restores a richer version of that idea (risk + admin), now driven by `Risk`.

## Decisions made with Matt (do not re-litigate)

1. **Risk-gated run (selection flow = "confirm only risky tools").** Selecting a `ReadOnly` tool runs it
   immediately (today's behavior). Selecting a `Modifies` or `Disruptive` tool shows a brief and a
   Yes/No confirm first. No confirm is added for read-only tools.
2. **Confirm default is `No`** for risky tools (safe default).
3. **ReadOnly shows no badge** (keeps the safe majority clean so a badge means "caution").
   `Modifies` -> `[M]`, `Disruptive` -> `[!]`, and `RequiresAdmin` appends `▲` (filled up-triangle, U+25B2).
4. **Badges are same-color glyphs** (rendered in the category color, not a separate risk color). The single
   place color emphasizes risk is the standalone confirm screen. This keeps meaning non-color-dependent
   (accessibility) and avoids splitting each menu row into per-segment `Write-Host` calls.
5. **Search single-hit shortcut.** When `Search-NmmTools` returns exactly one tool, route it straight to
   the gated-run path (read-only runs, risky confirms) instead of forcing a re-typed number.
6. **No registry, dispatch, tool, or `-Tool`/`-Silent`/`-ListTools` changes.** The unattended/PDQ paths
   keep their existing `-Silent`/`-Force` gating in `Invoke-NmmTool`; the new confirm is an interactive-only
   layer on top.

## New behavior

### `Get-NmmRiskBadge` (new pure helper)

```
param([Parameter(Mandatory)]$Tool)
# Returns a short ASCII+triangle badge string for the landing list. Never throws.
#   Risk 'Modifies'   -> '[M]'
#   Risk 'Disruptive' -> '[!]'
#   Risk 'ReadOnly' / unknown / missing -> ''   (no badge)
#   then, if $Tool.RequiresAdmin -eq $true, append the admin marker (up-triangle).
# Examples: ReadOnly+nonadmin -> ''            Modifies+admin -> '[M]▲'
#           Disruptive+admin  -> '[!]▲'         Disruptive+nonadmin -> '[!]'
```

Pure string output (no `Write-Host`), so it is unit-testable. The admin marker `▲` is a single char so badge
width is predictable (`''`, `[M]`, `[M]▲`, `[!]`, `[!]▲`).

### `Show-LandingMenu` (cell formatting change only)

The banner, layout-width logic, column packing (`Format-MenuColumns`), `Recent:` line, and per-category
color loop are **unchanged**. Only the per-tool cell string changes:

- Today: `$cell = ' {0,4}. {1}' -f $t.LegacyId, $t.Name`, truncated to `colWidth - 1`.
- New: compute `$badge = Get-NmmRiskBadge $t`. Build the label `' {0,4}. {1}' -f LegacyId, Name`, then
  **right-align the badge within the cell**:
  - `cellMax = colWidth - 1` (unchanged).
  - If `$badge` is empty: behave exactly as today (truncate label to `cellMax` with trailing `...`).
  - Else: truncate the label so `label.Length <= cellMax - $badge.Length - 1`, `PadRight` it to
    `cellMax - $badge.Length`, then append `$badge`. Result length `<= cellMax`. The badge sits flush near
    the right edge of the column, e.g. `   73. System Repair Suite  [!]▲`.
- The legend footer gains one line:
  `Legend: [M] modifies system  [!] disruptive  ▲ needs admin` (default/Gray color).

Rendering still writes each row in a single `-ForegroundColor` (the category color), so badges inherit that
color. No change to `Format-MenuColumns`.

### `Invoke-ToolWithGate` (new helper - the one run path)

```
param([Parameter(Mandatory)]$Tool)
# Interactive run with a risk gate. Returns nothing.
# 1. If $Tool.Risk is 'Modifies' or 'Disruptive':
#      - Print a brief block (see below).
#      - $answer = Read-ToolChoice -Prompt 'Run this tool?' -Choices @('Yes','No') -Default 'No'
#      - If $answer -ne 'Yes': print ' Cancelled.' (Detail) and return WITHOUT running.
# 2. Run it: Invoke-NmmTool -Tool $Tool | Out-Null
# 3. Read-Host 'Press Enter to continue' | Out-Null   (matches existing post-run pause)
```

ReadOnly tools skip step 1 entirely (no prompt, immediate run), preserving today's fast path. The brief:

```
 -- System Repair Suite -------------------------
   Category : Repair      Risk: Disruptive   (admin)
   Runs SFC + DISM + CHKDSK scheduling in sequence.
```

- The `Risk:` value is the one colored element: `Write-ToolOutput` is line-based, so print the brief lines
  with `Write-Host` directly in this UI function and color only the risk word - **Yellow** for `Modifies`,
  **Red** for `Disruptive`. `(admin)` appears only when `RequiresAdmin`.
- Description comes from `$Tool.Description`; if empty, omit that line.
- `Read-ToolChoice` already falls back to its `-Default` on a non-interactive host, so the gate degrades
  safely (defaults to `No` = does not run) if somehow reached headless.

### `Invoke-MenuSelection` (route through the gate; add single-hit shortcut)

```
$tool = Resolve-NmmTool -Query $Selection
if ($tool) { Invoke-ToolWithGate -Tool $tool; return }      # was: Invoke-NmmTool + pause inline

$found = @(Search-NmmTools -Term $Selection)
if ($found.Count -eq 0) { <unchanged 'Nothing matches' message>; return }
if ($found.Count -eq 1) { Invoke-ToolWithGate -Tool $found[0]; return }   # NEW single-hit shortcut

# 2+ matches: list as today (number. Name (Category)), Read-Host a pick, then:
$tool = Resolve-NmmTool -Query $pick.Trim()
if ($tool) { Invoke-ToolWithGate -Tool $tool } else { <unchanged 'did not match' message> }
```

The inline `Invoke-NmmTool ... ; Read-Host 'Press Enter'` blocks (both the direct path and the search-pick
path) are replaced by `Invoke-ToolWithGate`, so the gate + post-run pause live in exactly one place.

### Unchanged

`Start-ConsoleMenu` loop (`X` exit, `T` ticket export), `Show-LandingMenu`'s banner/width/column logic,
`Get-NmmLegacyIdSortKey`, `Get-CategoryColor`, `Format-MenuColumns`, `Resolve-NmmTool`, `Search-NmmTools`,
`Invoke-NmmTool`, and all `-Tool`/`-Silent`/`-ListTools`/PDQ semantics.

## Files

- Modify: `src/core/05-ui-console.ps1` - add `Get-NmmRiskBadge` and `Invoke-ToolWithGate`; change the cell
  build + legend in `Show-LandingMenu`; route `Invoke-MenuSelection` through `Invoke-ToolWithGate` and add
  the single-hit shortcut. Everything else unchanged.
- Modify: `tests/ui-console.tests.ps1` - add `Get-NmmRiskBadge` and `Invoke-ToolWithGate` describes;
  extend the `Show-LandingMenu` cases for badges/legend. Existing `New-FakeTool` fixture + `6>&1` capture
  reused.

No registry, dispatch, tool, or CLI file changes.

## Testing

Reuse the existing `New-FakeTool` fixture and `6>&1` capture pattern. Color is a `Write-Host` argument and
does not appear in captured text, so risk coloring is verified indirectly (via `Get-NmmRiskBadge` for the
glyph and by asserting the brief prints the risk word), not by inspecting color.

1. **`Get-NmmRiskBadge`**: `ReadOnly`+nonadmin -> `''`; `ReadOnly`+admin -> admin marker only;
   `Modifies` -> `[M]` (+ `▲` when admin); `Disruptive` -> `[!]` (+ `▲` when admin); unknown/missing
   Risk -> `''` (+ `▲` when admin); never throws.
2. **`Invoke-ToolWithGate` decision logic** (mock `Read-ToolChoice` and `Invoke-NmmTool`):
   - ReadOnly tool: `Read-ToolChoice` is **never** called; `Invoke-NmmTool` **is** called once.
   - Disruptive tool, mock answer `No`: `Invoke-NmmTool` is **never** called.
   - Disruptive tool, mock answer `Yes`: `Invoke-NmmTool` is called once.
   - Confirms `Read-ToolChoice` is invoked with `-Default 'No'` for risky tools.
   - The post-run `Read-Host` pause is mocked so tests do not block.
3. **`Show-LandingMenu` badges**: seed a `Disruptive` admin tool and assert its rendered row contains `[!]`
   and `▲`; seed a `ReadOnly` nonadmin tool and assert its row contains **neither** `[M]`,
   `[!]`, nor `▲`; assert every rendered cell width `<= colWidth`; assert the legend line
   (`[M] modifies`, `[!] disruptive`) is present; `Show-LandingMenu` returns nothing.
4. **`Invoke-MenuSelection` single-hit**: with a search term matching exactly one tool, `Invoke-ToolWithGate`
   is reached for that tool without a `Read-Host` pick prompt; with a term matching 2+, the list is shown
   and a pick still routes through the gate; with 0, the unchanged "Nothing matches" message prints.

The other 8 test files are untouched. `build.ps1` must compile and PSScriptAnalyzer stay clean (errors
gate). Final suite count is recomputed after the change.

## Out of scope

- Per-badge coloring inside a menu row (would require segmented `Write-Host`); category color is retained.
- An explicit `[R]` badge for read-only tools (decided against - blank = safe).
- Drill-into-category navigation, a pinned "common fixes" section, arrow-key/type-ahead TUI, or a GUI
  (separate future directions; not this spec).
- Any change to `Search-NmmTools` scope (it already matches Name + Description + Tags), the registry, tool
  behavior, or the `-Tool`/`-Silent`/`-ListTools` paths.
