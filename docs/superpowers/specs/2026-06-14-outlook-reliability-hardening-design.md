# Outlook Reliability Hardening - Design Spec

**Date:** 2026-06-14
**Scope:** Enhance two existing v9 tools with durable/preventive fixes for two recurring field problems:
(1) the OnBase/Hyland Outlook add-in being repeatedly disabled by Outlook's "this add-in slows down
Outlook" load-time disabling, and (2) Outlook search repeatedly breaking. No new tools.
**Status:** Approved (brainstormed with Matt 2026-06-14). Next: writing-plans -> implementation plan.

## Context

v9 ships `outlook-addin-repair` (tool 96) and `outlook-search-repair` (tool 76). Both are currently
**reactive** - they un-stick the problem once, but it recurs. Matt confirmed:

- **OnBase add-in:** Outlook shows *"This add-in slows down Outlook"* and disables it (load-time /
  performance disabling). OnBase is **business-critical**; the goal is to stop it from being disabled
  permanently, not to keep re-enabling it. The current tool only writes the SOFT
  `...\Outlook\Resiliency\DoNotDisableAddinList`, which Outlook overrides.
- **Outlook search:** clearing/rebuilding the index keeps working only temporarily - the index is rebuilt
  back into a still-broken configuration.

## Decisions made with Matt (do not re-litigate)

1. **Enhance the two existing tools** (`outlook-addin-repair`, `outlook-search-repair`) - no new tools.
   Registry stays 100 tools.
2. **Add-in fix is targeted to OnBase/Hyland only** via the policy-level managed-add-in pin.
3. **Search fix adds a Diagnose-in-report + a `FixConfig` action** before the existing nuclear rebuild.
4. **Office version is 16.0** (2016/2019/2021/M365), consistent with every other Outlook tool.

## Tool 1: `outlook-addin-repair` (Repair-OutlookAddins) - add `PinOnBase`

### Root cause / durable lever

"This add-in slows down Outlook" is Outlook's **load-time performance disabling**. The soft
`HKCU\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList` does NOT reliably stop it.
The durable levers live in the **policy** Resiliency hive,
`HKCU\Software\Policies\Microsoft\Office\16.0\Outlook\Resiliency`:

- **`DisablePromptOnLoadTimeDisable` = `1`** (DWORD) - suppresses the slow-add-in prompt/auto-disable.
- **`AddinList\<ProgID>` = `"1"`** (REG_SZ; the "List of Managed Add-ins" GPO; `1` = always enabled) -
  Outlook treats the add-in as managed and will not disable it.

These are per-user (HKCU) and need NO admin; the managed-add-in policy forces the add-in on regardless of
whether OnBase is registered under HKCU or HKLM, so the tool never needs to touch HKLM.

### Report (enhanced)

Keep the current add-in/LoadBehavior/DisabledItems/CrashingAddinList/OnBase-detection report, and ADD a
policy-state line: read `HKCU\Software\Policies\Microsoft\Office\16.0\Outlook\Resiliency` and report whether
`DisablePromptOnLoadTimeDisable` is set and whether the detected OnBase ProgID(s) are present in `AddinList`
with value `1` - i.e. "OnBase pinned: yes/no".

### Action menu

`Read-ToolChoice -Choices @('None','ReEnable','PinOnBase') -Default 'None' -Silent:$Silent`.
`ReEnable` is the existing behavior (unchanged). **New `PinOnBase`** (offered always; if no OnBase add-in is
detected it reports Warning and does nothing):

1. **Identify OnBase add-ins:** the add-ins whose registry key Name or FriendlyName matches `OnBase|Hyland`
   (already computed in the report). The pin targets each one's **registry key Name (= ProgID)**.
2. **Un-stick now** (non-policy root `HKCU\Software\Microsoft\Office\16.0\Outlook\Resiliency`): clear
   `DisabledItems` and `CrashingAddinList`; for any OnBase add-in registered under HKCU, set its
   `LoadBehavior = 3`.
3. **Pin durably** (policy root `HKCU\Software\Policies\Microsoft\Office\16.0\Outlook\Resiliency`): set
   `DisablePromptOnLoadTimeDisable = 1` (DWORD); create the `AddinList` subkey; for each OnBase ProgID set
   value `<ProgID> = "1"` (String).
4. **Verify:** re-read the policy values; report **Success** listing the pinned ProgID(s), or **Warning**
   if the write did not take.

- **RequiresAdmin** stays `$false`; **Risk** stays `Modifies`.
- **Honesty:** if `$onbase.Count -eq 0`, `PinOnBase` -> Warning "no OnBase/Hyland add-in found to pin"; pin
  only confirmed after read-back.
- Registry **Description** updated to mention "...permanently pin the OnBase/Hyland add-in so Outlook stops
  disabling it (policy-level managed add-in)".

## Tool 2: `outlook-search-repair` (Repair-OutlookSearch) - deeper report + `FixConfig`

### Root cause / preventive levers

A rebuild re-indexes into the same broken config. The recurring config causes:

- **WSearch StartType** left Disabled/Manual (index never maintained).
- **`PreventIndexingOutlook` = 1** at `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search` - silently
  disables Outlook indexing.
- Windows Search setup state (`HKLM\SOFTWARE\Microsoft\Windows Search\SetupCompletedSuccessfully`).

### Report (enhanced)

Keep the current WSearch status / `Windows.edb` size / Outlook-running / catalog-registered report, and ADD:

- WSearch **StartType** flagged: Detail when `Automatic*`, **Warning** otherwise.
- **`PreventIndexingOutlook`** (DWORD at `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search`):
  **Warning** when `= 1` ("Outlook indexing is disabled by policy"), Detail otherwise.
- `SetupCompletedSuccessfully` reported as Detail.

### Action menu

`Read-ToolChoice -Choices @('None','FixConfig','RestartService','RebuildIndex') -Default 'None'
-Silent:$Silent`. `RestartService` and `RebuildIndex` are unchanged. **New `FixConfig`** (the preventive
fix, meant to run before a rebuild):

1. If WSearch `StartType` is `Disabled` or `Manual` -> `Set-Service -Name WSearch -StartupType Automatic`
   and `Start-Service WSearch`.
2. If `PreventIndexingOutlook = 1` -> set it to `0`
   (`Set-ItemProperty ... -Name PreventIndexingOutlook -Value 0`), then **warn**: "if this returns after a
   gpupdate it is set by Group Policy - fix the GPO; the toolkit cannot override a domain policy."
3. **Re-query** WSearch StartType/Status and `PreventIndexingOutlook`; report what changed. Note that a
   `RebuildIndex` may still be needed for the change to take full effect.
4. Status: **Success** if the corrected settings now read healthy, **Warning** if something could not be set
   (e.g. the policy immediately reads back as 1 -> GPO-managed).

- **RequiresAdmin** stays `$true` (WSearch + HKLM); **Risk** stays `Modifies`.
- Registry **Description** updated to mention "...diagnose and fix the search configuration (WSearch
  startup, PreventIndexingOutlook policy) before rebuilding the index".

## Files

- Modify: `src/tools/user/Repair-OutlookAddins.ps1` - enhanced report + `PinOnBase` action.
- Modify: `src/tools/user/Repair-OutlookSearch.ps1` - enhanced report + `FixConfig` action.
- Modify: `src/registry/tools.psd1` - update the two Descriptions only (no new entries; Ids/Functions/Risk/
  RequiresAdmin unchanged; tool count stays 100).

No new tools, no helper-file or dispatch changes.

## Testing

- These are behavior edits to two existing tool functions (the same pattern every tool was built with);
  the project has no per-tool unit tests, so correctness is verified by the existing
  template/registry/encoding suite staying green (the `New-ToolRun -Id` literals, approved verbs, ASCII +
  BOM, and registry completeness are all unchanged), the build compiling, PSScriptAnalyzer clean, and the
  two-stage review.
- **Reviewers must specifically check:** the registry paths and value types (REG_SZ `"1"` for
  `AddinList\<ProgID>`; DWORD `1` for `DisablePromptOnLoadTimeDisable` and `PreventIndexingOutlook=0`); that
  `PinOnBase`/`FixConfig` are gated behind `Read-ToolChoice` and do nothing under `-Silent`; the
  no-OnBase-found and GPO-revert honesty paths; that the existing `ReEnable`/`RestartService`/`RebuildIndex`
  arms are unchanged; and that nested helpers stay function-local (not registry-scanned).
- Suite count unchanged (no new tests; no new tools).

## Out of scope

- Pinning add-ins other than OnBase/Hyland (targeted by decision; the existing `ReEnable` still re-enables
  all disabled add-ins generally).
- Pushing a fleet-wide GPO/Intune policy (the toolkit applies the per-user/per-machine registry fix and
  reports the ProgID + the GPO-revert caveat so a fleet policy can be set separately if desired).
- Office versions other than 16.0; the `-Tool`/`-Silent`/menu paths; any other Outlook tool.
