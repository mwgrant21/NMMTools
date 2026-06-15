# Two-Column Color-Coded Landing Menu - Design Spec

**Date:** 2026-06-14
**Scope:** Change the landing menu (just merged as all-visible single-column with descriptions) to a v8-style
**two-column, title-only, color-coded-by-category** layout. Interactive console only; no tool/registry/CLI
changes.
**Status:** Approved (brainstormed with Matt 2026-06-14). Next: writing-plans -> implementation plan.

## Context

v9 is at full v8 parity (100 tools, 8 categories, 76/76 tests). The landing menu (`Show-LandingMenu` in
`src/core/05-ui-console.ps1`) currently lists every tool single-column with its full wrapped description.
Matt field-tested it and prefers the **v8 layout**: every tool visible, but **two columns, title only
(no descriptions), color-coded per category** like v8.0.

## Decisions made with Matt (do not re-litigate)

1. **Two columns, title only.** Each tool shows `{LegacyId}. {Name}` - no description, no `[admin]` tag.
2. **Color-coded per category**, mirroring v8's section colors (1:1 mapping below).
3. **v8-style boxed banner** per category (3-line `+===+` box) in the category color.
4. **Column-major fill** (v8 behavior): the left column is the first half of the category's tools, the
   right column the second half (e.g. `1..10` down the left, `11..20` down the right).
5. **Width-adaptive:** two columns when the console is wide enough, one column on a narrow terminal.

## Category -> color map (1:1 with v8 sections)

| v9 Category | v8 Section | ConsoleColor |
|---|---|---|
| Browser     | Browser & Data Tools      | White |
| Cloud       | Cloud & Collaboration     | Yellow |
| Diagnostics | System Diagnostics        | Cyan |
| Laptop      | Laptop & Mobile Computing | Green |
| QuickFix    | Quick Fixes               | Magenta |
| Repair      | Advanced System Repair    | Red |
| Security    | Security & Domain         | DarkYellow |
| User        | Common User Issues        | Blue |

Unknown/future categories fall back to `Gray`.

## New behavior

### `Show-LandingMenu` (rewritten render body)

1. **Guarded `Clear-Host`** (unchanged): only when `$script:OutputSink -ne 'Silent'` AND
   `[Environment]::UserInteractive`, wrapped in try/catch.
2. Banner rule + `NMM System Toolkit v9  <HOST>\<USER>` + the existing `Recent:` line (unchanged).
3. Compute layout width: `[Console]::WindowWidth` when available and `> 0`, else `80` (try/catch -> 80).
   - `columns = 2` when width `>= 72`, else `1`.
   - `colWidth = [int][math]::Floor(width / columns)` (clamped to a sane minimum, ~30).
4. For each category (alphabetical, `Sort-Object -Unique`):
   - `color = Get-CategoryColor $category`.
   - A 3-line boxed banner sized to `columns * colWidth`, printed in `color`:
     ```
      +================================================================+
      |  Diagnostics (23 tools)                                        |
      +================================================================+
     ```
     (The title is left-padded to the inner width; truncated if it would overflow.)
   - Build a cell per tool (sorted by `Get-NmmLegacyIdSortKey`): `'{0,4}. {1}' -f LegacyId, Name`,
     **truncated** to `colWidth - 1` with a trailing `...` if it would overflow (ASCII, no Unicode
     ellipsis).
   - `Format-MenuColumns -Cells $cells -Columns $columns -ColumnWidth $colWidth` returns the row strings
     (column-major); print each row in `color`.
5. Blank line, then the prompt hint (default color):
   `Enter: tool number (e.g. 54 or Q3) | search text` / `T = save session summary (for tickets)   X = exit`.
6. Returns nothing (no map).

### Helpers (top-level core functions in `05-ui-console.ps1`)

- **Keep** `Get-NmmLegacyIdSortKey` (unchanged).
- **Remove** `Get-WrappedLines` (no descriptions to wrap) and its unit tests.
- **Add** `Get-CategoryColor`:
  ```
  param([Parameter(Mandatory)][string]$Category)
  switch ($Category) {
    'Browser' { 'White' } 'Cloud' { 'Yellow' } 'Diagnostics' { 'Cyan' } 'Laptop' { 'Green' }
    'QuickFix' { 'Magenta' } 'Repair' { 'Red' } 'Security' { 'DarkYellow' } 'User' { 'Blue' }
    default { 'Gray' }
  }
  ```
  Returns a string that is a valid `[ConsoleColor]` name (used as `Write-Host -ForegroundColor`).
- **Add** `Format-MenuColumns`:
  ```
  param([string[]]$Cells, [int]$Columns, [int]$ColumnWidth)
  # Column-major packing. rows = ceil(N / Columns). Row r, column c -> Cells[c*rows + r].
  # Non-last columns are PadRight($ColumnWidth); the row is emitted TrimEnd()'d.
  # Returns string[] (empty array when $Cells is empty); never throws; $Columns < 1 treated as 1.
  ```
  Pure string layout (no color), so it is unit-testable.

### Unchanged

`Start-ConsoleMenu` (loop: render -> read -> `X` exit / `T` ticket / else `Invoke-MenuSelection`),
`Invoke-MenuSelection` (number/`Q#`/Id resolve, else search), the search-results path, and ticket export
are all untouched. No `Show-CategoryTools` (already removed).

## Files

- Modify: `src/core/05-ui-console.ps1` - rewrite `Show-LandingMenu` render body; remove `Get-WrappedLines`;
  add `Get-CategoryColor` and `Format-MenuColumns`; keep everything else.
- Modify: `tests/ui-console.tests.ps1` - drop the `Get-WrappedLines` describe; add `Get-CategoryColor` and
  `Format-MenuColumns` describes; update the `Show-LandingMenu` cases for the two-column, title-only,
  banner-with-count layout.

No registry, tool, dispatch, or `-Tool`/`-Silent` changes.

## Testing

Rewrite `tests/ui-console.tests.ps1` (existing `New-FakeTool` fixture + `6>&1` capture). Color is a
`Write-Host -ForegroundColor` argument and does not appear in captured text, so it is verified indirectly
through `Get-CategoryColor` unit tests, not the rendered output.

1. **`Get-CategoryColor`**: returns the mapped color for each of the 8 categories (e.g. Diagnostics ->
   `Cyan`, QuickFix -> `Magenta`, User -> `Blue`) and `Gray` for an unknown category. Every returned value
   is castable to `[ConsoleColor]`.
2. **`Format-MenuColumns`**: column-major packing - `@('A','B','C','D','E')` with `-Columns 2` yields 3
   rows where row 0 contains `A` and `D`, row 1 `B` and `E`, row 2 `C` (and no second cell); empty input
   yields an empty array; `-Columns 1` yields one cell per row; does not throw.
3. **`Show-LandingMenu` two-column layout**: with a category of several tools, both halves appear and a
   later-numbered tool from the second half shares a rendered row with an earlier one (i.e. two cells on a
   line); the banner shows `Diagnostics (N tools)` style text; **descriptions do NOT appear** (seed a tool
   whose Description is a unique token and assert that token is absent); the QuickFix `Q#` ids render
   without throwing; `Show-LandingMenu` returns nothing.
4. **Hint line**: still mentions `Q3` and `X = exit`.

The other 8 test files are untouched. `build.ps1` must compile and PSScriptAnalyzer stay clean (errors
gate). Final suite count is recomputed after the rewrite.

## Out of scope

- Tool behavior, categories, registry, the `-Tool`/`-Silent`/`-ListTools` paths.
- A curated (non-alphabetical) category order, 3+ columns, paging, or restoring per-tool descriptions.
- Re-adding the `[admin]` marker (dropped per "just the title"; trivially restorable later if wanted).
