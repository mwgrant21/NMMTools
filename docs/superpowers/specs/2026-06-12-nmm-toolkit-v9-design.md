# NMM Toolkit v9 — Design Specification

**Date:** 2026-06-12
**Status:** Approved by Matt (brainstorming session)
**Supersedes:** NMMTools.ps1 v8.0 (monolith, ~12,000 lines, 106 tools)

## Goal

Rebuild the NMM System Toolkit as a modular source repository that compiles to a
single-file `NMMTools.ps1` artifact, with consistent hardening across all tools, a
data-driven console menu + optional GUI, a non-interactive CLI/PDQ mode, and
session transcript / ticket export.

## Approach (locked in)

**Hybrid "rewrite behind a stable frontier":**

- v8.0 remains the production toolkit, **feature-frozen**, while v9 is built.
  No pressure to ship intermediate v9 builds.
- Inside the rewrite, tools are ported **one category per batch** (7 batches),
  with a build + smoke test after each batch — big-bang project, incremental work.
- After cutover, all future development is incremental: drop a tool file in,
  add a registry entry, rebuild.

### Constraints

- **PowerShell 5.1 baseline** (`#Requires -Version 5.1`) — target machines are arbitrary.
- **Delivery is mixed** (manual copy, network share, PDQ/Intune) — the shipped
  artifact must remain a single self-contained `.ps1`.
- v8.0 behavior is the functional reference: all 106 tools must be accounted for
  at cutover (ported, consolidated, or deliberately retired — no silent drops).

## 1. Source layout

```
NMMToolkit/
├── build.ps1                    # compiles dist\NMMTools.ps1
├── src/
│   ├── core/
│   │   ├── 01-bootstrap.ps1     # exec-policy handling, UAC elevation (ported as-is)
│   │   ├── 02-output.ps1        # Write-ToolOutput + pluggable sinks (console/GUI/log)
│   │   ├── 03-results.ps1       # tool-run tracking, session transcript, ticket export
│   │   ├── 04-dispatch.ps1      # registry-driven dispatch + CLI mode
│   │   ├── 05-ui-console.ps1    # menu renderer, search, category submenus
│   │   └── 06-ui-gui.ps1        # GUI launcher (same registry, same sinks)
│   ├── registry/
│   │   └── tools.psd1           # THE tool registry — pure data
│   └── tools/
│       ├── diagnostics/         # one .ps1 per tool, named after its function
│       ├── cloud/
│       ├── repair/
│       ├── laptop/
│       ├── browser/
│       ├── user-issues/
│       └── security/
├── tests/                       # Pester: registry consistency, artifact smoke test
├── dist/
│   └── NMMTools.ps1             # build output — the only file techs ever see
└── docs/
```

## 2. Tool registry

Single `tools.psd1` data file; one entry per tool:

```powershell
@{
    Id            = 'teams-deep-repair'      # stable slug — CLI uses this
    LegacyId      = '85'                     # v8 menu number still works (muscle memory)
    Name          = 'Teams Deep Diagnostic & Repair'
    Category      = 'UserIssues'
    Function      = 'Invoke-TeamsDeepRepair'
    Description   = 'Targets WAM/MSAL token corruption causing silent Teams failures'
    RequiresAdmin = $true
    SilentCapable = $true                    # safe to run with -Silent (no prompts needed)
    Risk          = 'Modifies'               # ReadOnly | Modifies | Disruptive
    Tags          = @('teams','auth','token','azuread')
}
```

Four consumers, all views over this data: console menu, GUI tree, CLI dispatcher,
ticket export. `Risk` drives UI color-coding; `-Silent` refuses `Disruptive` tools
unless `-Force` is passed.

## 3. Standard tool template (hardening applied at port time)

```powershell
function Invoke-TeamsDeepRepair {
    [CmdletBinding()]
    param([switch]$Silent)

    $result = New-ToolRun -Id 'teams-deep-repair'   # starts timer, transcript section
    try {
        Write-ToolOutput "Checking Teams installation..." -Level Info
        # ... work ...
        $choice = Read-ToolChoice -Prompt "Rebuild token cache?" -Default 'No' -Silent:$Silent
        # ... work ...
        Complete-ToolRun $result -Status Success -Summary "Token cache rebuilt"
    }
    catch {
        Complete-ToolRun $result -Status Failed -Summary $_.Exception.Message
    }
}
```

Template rules:

- **No `Write-Host`/`Read-Host` shadowing.** `Write-ToolOutput` routes to the
  active sink — colored console, GUI textbox, or log file. The v8 GUI's
  runspace function-override hack is eliminated; the GUI swaps the sink instead.
- **`Read-ToolChoice`** centralizes prompting; in `-Silent` mode it returns the
  declared default instead of blocking. This makes every tool PDQ-safe by construction.
- **Every run ends in `Complete-ToolRun`** (success or failure), so transcript and
  report are complete even when a tool throws.
- PSScriptAnalyzer clean; approved verbs (e.g. `Fix-SharedMailbox` →
  `Repair-SharedMailbox`; old names remain searchable via registry tags).

## 4. Console UX

- Landing screen: 7 categories + search prompt + recent-tools row (no 106-line wall).
- Type-to-search: text filters by name/tag; a number runs that tool directly.
- Legacy v8 numbers preserved via `LegacyId`.

## 5. CLI / PDQ mode

```powershell
NMMTools.ps1 -Tool teams-deep-repair -Silent          # by slug
NMMTools.ps1 -Tool 85 -Silent                         # by legacy number
NMMTools.ps1 -ListTools                               # machine-readable inventory
NMMTools.ps1 -Tool disk-cleanup -Silent -LogPath C:\Logs
```

- No `-Tool` argument → interactive menu (today's behavior).
- Exit code 0/1 reflects tool status for PDQ Deploy reporting.
- `SilentCapable = $false` tools refuse `-Silent` with a clear message.

## 6. Session transcript / ticket export

- Every tool run appends a structured entry (timestamp, tool, status, summary,
  duration) — mandatory via the template, not opt-in.
- Menu option **T — Copy ticket summary**: renders the session as paste-ready plain
  text (machine, user, tools run, findings, fixes applied).
- Also written to disk alongside the existing report export.

## 7. Build process (`build.ps1`)

1. Concatenate `core/` (ordered) + registry + all `tools/**/*.ps1` + entry point
   into `dist/NMMTools.ps1`.
2. Stamp version + build date into the header.
3. PSScriptAnalyzer on the artifact — failure blocks the build.
4. Pester tests: every registry entry resolves to a real function; every tool
   function has a registry entry; artifact parses under PS 5.1.
5. Output: one self-contained `.ps1`.

## 8. Migration & cutover

- v8.0 feature-frozen the day porting starts.
- 7 category batches; build + smoke test after each.
- Parity checklist tracks all 106 v8 tools: **ported / consolidated / retired**.
  Known consolidation candidates: duplicate credential-manager tools (26 / 60 / 92-area),
  overlapping Office repair entries (22 / 99), Outlook search (76 / 106).
  Each consolidation or retirement is an explicit decision with Matt, not a silent drop.
- Cutover: v9 becomes the copy on the share/PDQ; v8 kept as
  `NMMTools-v8-fallback.ps1` for a two-week parallel-run window.

## 9. Error handling & testing

- Tool-level: template try/catch guarantees a recorded outcome per run.
- Build-level: PSScriptAnalyzer gate + Pester registry-consistency tests +
  PS 5.1 parse smoke test of the artifact.
- Cutover-level: per-batch smoke tests during porting; parallel-run fallback window.

## Out of scope (this project)

- Self-update mechanism (explicitly declined).
- New repair/diagnostic tools — specced separately after cutover (phase: post-v9).
- PowerShell 7 migration.
