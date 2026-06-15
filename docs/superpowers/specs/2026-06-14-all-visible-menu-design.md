# All-Visible Landing Menu - Design Spec

**Date:** 2026-06-14
**Scope:** Replace the v9 adaptive category-letter landing menu (drill-in) with a single all-visible
listing that shows every tool grouped under category headers, each with its full description. Interactive
console only; the `-Tool`/`-Silent` CLI path is unchanged.
**Status:** Approved (brainstormed with Matt 2026-06-14). Next: writing-plans -> implementation plan.

## Context

v9 is at full v8 parity (100 tools, 8 categories, 71/71 tests). The current landing
(`Show-LandingMenu` in `src/core/05-ui-console.ps1`) is adaptive: a flat list when small, but with 100
tools across 8 categories it shows a **category-letter list** (A=Browser ... H=User) and the technician
must drill into a category to see its tools. Matt prefers v8's layout where **every tool is visible at
once** (v8 used color-coded section banners with tools listed under each, type the number to run).

This change is almost entirely subtractive: the existing `Show-CategoryTools` already renders name +
description for one category; the new landing runs that rendering over ALL categories and deletes the
letter/`$map` machinery.

## Decisions made with Matt (do not re-litigate)

1. **All tools visible on the landing**, grouped under plain category headers. No drill-in.
2. **Single column, full descriptions.** Each tool: number/`Q#` + name (+ ` [admin]`), then its full
   description word-wrapped in grey underneath. (Two-column + per-tool descriptions are mutually
   exclusive; descriptions won.)
3. **Drop the category-letter drill-in.** Category names are plain visual headers, not selectable. Run a
   tool by typing its number/`Q#`/Id; search by typing text.
4. **Alphabetical category order** (unchanged from today). A curated order is a later option, not now.

## Current behavior (to be replaced)

`Show-LandingMenu` returns a `$map` (letter -> category) and either lists tools flat (<=15 tools or <=1
category) or lists category letters with counts. `Start-ConsoleMenu` reads input and, if it matches a
letter in `$map`, calls `Show-CategoryTools` (which lists that category's tools WITH descriptions, sorted
by `[int]$_.LegacyId`). `Resolve-NmmTool` matches a tool by `Id` then `LegacyId` (string `-eq`, so `54`
and `Q3` both resolve correctly today).

**Latent bug being fixed:** `Show-CategoryTools` sorts with `Sort-Object { [int]$_.LegacyId }`. `[int]'Q1'`
throws in PS 5.1, so drilling into the QuickFix category today would error. The new robust sort key
removes this.

## New behavior

### `Show-LandingMenu` (rewritten)

1. **Clear the screen first**, guarded so it never runs in tests or non-interactive contexts: only call
   `Clear-Host` when `$script:OutputSink -ne 'Silent'` AND `[Environment]::UserInteractive`. (Keeps the
   long list redrawing from the top after each tool run, without breaking Pester output capture.)
2. Banner line `NMM System Toolkit v9      <COMPUTERNAME>\<USERNAME>` between two `=` rules (as today).
3. The existing `Recent: ...` line when `$script:ToolRuns.Count -gt 0`.
4. For each category in `@($tools | ForEach-Object { $_.Category } | Sort-Object -Unique)`:
   - A cyan header line: ` -- <Category> (<count>) --`.
   - The category's tools, sorted by the **robust LegacyId key** (see below), each rendered as:
     ```
       54. Windows Search Rebuild [admin]
            Restart the Windows Search service, rebuild the
            search index, or open Indexing Options
     ```
     - Tool line: ` {0,4}. {1}{2}` with `{0}`=LegacyId, `{1}`=Name, `{2}`=` [admin]` when
       `RequiresAdmin`, default colour.
     - Description: word-wrapped (see wrapping rule) to the console width, indented under the name in grey.
5. A blank line, then the prompt hint:
   `Enter tool number (e.g. 54 or Q3), search text` / `T = save session summary (for tickets)   X = exit`.
6. **Returns nothing** (no `$map`).

### Robust LegacyId sort key

A nested helper inside the render (not registry-scanned; the registry test only scans `src\tools`):

```
Get-LegacyIdSortKey($legacyId):
  if $legacyId matches '^\d+$'      -> [int]$legacyId
  elseif $legacyId matches '^Q(\d+)$' -> 1000 + [int]$Matches[1]
  else                               -> 100000   # unknown formats sort last, never throws
```

Within a single category this orders numeric tools ascending and `Q#` tools after them in `Q1..Q9` order.
Used by the landing render (and would have fixed the old `Show-CategoryTools`).

### Description word-wrapping

A nested helper that wraps a description to the available width:

- Width = `[Console]::WindowWidth` when available and `> 0`, else `80`. Subtract the indent (10 chars: a
  9-space indent + margin) and a small safety margin; floor the usable width at ~30 so very narrow
  consoles still produce something.
- Split the description on spaces and greedily pack words into lines no wider than the usable width;
  emit each wrapped line indented to align under the tool name, in grey (`-Level`/colour Detail-grey
  consistent with the current `Show-CategoryTools` description colour).
- `[Console]::WindowWidth` access is wrapped so a redirected/headless host (no console buffer) falls back
  to 80 without throwing.

### `Start-ConsoleMenu` (simplified)

The interactive loop drops the category-letter branch:

```
while ($true):
  Show-LandingMenu
  read $selection (prompt: 'Select tool number/Q#, search text, or X to exit')
  blank -> continue
  X -> return
  T -> export ticket summary to Desktop (UNCHANGED block)
  otherwise -> Invoke-MenuSelection -Selection $selection   # resolves number/Q#/Id, else search
```

The `$map.ContainsKey(...)` / `Show-CategoryTools` branch is removed. `Invoke-MenuSelection` and the
search-results path are UNCHANGED.

### Removed

- `Show-CategoryTools` (only reachable via the dropped drill-in).
- The `$map`/letter-assignment logic and the flat-vs-category adaptive branch in `Show-LandingMenu`.

## Files

- Modify: `src/core/05-ui-console.ps1` - rewrite `Show-LandingMenu`, simplify `Start-ConsoleMenu`, remove
  `Show-CategoryTools`, add the two nested helpers (sort key, wrap).
- Modify: `tests/ui-console.tests.ps1` - rewrite for the new contract.

No registry, tool, dispatch, or `-Tool`/`-Silent` changes.

## Testing

Rewrite `tests/ui-console.tests.ps1` (using the existing `New-FakeTool` fixture + `6>&1` capture):

1. **Every tool name and its description appear** on the landing (e.g. build a small multi-category
   registry; assert each Name and each Description substring is present).
2. **Category headers with counts render** (e.g. ` -- Diagnostics (2 tools) --` style; assert the header
   text and count).
3. **Within-category ordering** is by LegacyId with numeric before `Q#`: seed a category containing
   `2`, `10`, `Q3`, `Q1` (or split across categories) and assert `2` before `10` before `Q1` before `Q3`,
   AND that rendering a QuickFix-style `Q#` registry **does not throw** (the `[int]'Q1'` regression guard).
4. **No letter map returned:** `Show-LandingMenu` returns `$null`/nothing (no hashtable in the output
   stream) - replaces the old `$map.Count` assertions.
5. Optionally: the prompt hint text mentions `Q3` and `X` (smoke check of the new hint).

The other 8 test files are untouched. `build.ps1` must still compile and PSScriptAnalyzer stay clean.
Final suite count is recomputed after the ui-console rewrite (the 4 old adaptive-layout cases are replaced
by the new cases).

## Out of scope

- Tool behavior, categories, registry, the `-Tool`/`-Silent`/`-ListTools` CLI paths.
- A curated (non-alphabetical) category order, two-column layout, or paging - explicitly deferred.
