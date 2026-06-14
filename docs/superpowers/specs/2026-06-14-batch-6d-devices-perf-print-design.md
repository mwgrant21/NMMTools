# Batch 6D: Devices / Performance / Print Tools - Design Spec

**Date:** 2026-06-14
**Scope:** Port v8 tools 52, 53, 56 into v9; consolidate 98 into 52 and 77 into the existing
teams-camera-repair. Sub-batch 6D of batch 6.
**Status:** Approved (brainstormed with Matt 2026-06-14). Next: writing-plans -> 6D implementation plan.

## Batch 6 decomposition (context)

Batch 6 ("Common User Issues") is decomposed into 5 themed sub-batches. Done: 6C Shell/UI, 6B Teams, 6E
Profile/Cred/Network (all merged; 77 tools). This spec is **6D**. After 6D only **6A Outlook/M365** remains.

## Goal

Port the device/performance/print tools, with two consolidations. v8 monolith at
`C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference (functions: `Repair-PrinterIssues` L5925,
`Optimize-Performance` L6242, `Repair-AudioAdvanced` L6990, `Repair-WebcamDriver` L9237,
`Reset-PrintSpooler` L11550).

## Usage model (unchanged)

Interactive technician at the keyboard; toolkit elevates at launch. Optimize the interactive experience;
`-Silent` only needs to be SAFE (report-only / admin-refusal). All three NEW tools are admin (Spooler /
services / page file / audio drivers); the modified camera tool is already admin.

## Decisions made with Matt (do not re-litigate)

1. **Merge tool 98 (Print Spooler Deep Reset) INTO tool 52 (`printer-repair`).** 98's stop-spooler ->
   clear `spool\PRINTERS` -> restart is a subset of 52; it becomes the `ClearSpoolFolder` / `FullReset`
   actions. Mark 98 consolidated -> 52.
2. **Port tool 53 (`perf-optimizer`) FAITHFULLY** (full v8 action set) even though it overlaps shipped
   tools (performance-metrics 7, running-processes 4, temp-cleanup 11, startup-programs 16). The
   description cross-references those tools; it does not pretend to be the only path.
3. **Consolidate tool 77 (Webcam Driver Fix) INTO the EXISTING `teams-camera-repair` (84+97, shipped in
   6B).** Add a `ReinstallDriver` action (the driver-level steps 77 adds over what the tool already does:
   `pnputil /remove-device` + WU driver scan). Kill-apps + PnP-cycle (ResetMediaStack) and privacy
   (FixPermissions) are already present. **Rename** the tool Name `Teams Camera and Mic Repair` ->
   `Camera and Mic Repair` (it now spans general webcam driver repair) and add `webcam`/`driver` tags;
   LegacyId stays 84. Mark 77 consolidated -> 84.
4. **Category 'User'** for the 3 new tools (batch 6). Tool count 77 -> 80 (the 77 fold-in is an action add,
   not a new tool).

## Architecture

```
src\tools\user\Repair-PrinterIssues.ps1     -> printer-repair    (52 + 98)   NEW
src\tools\user\Optimize-Performance.ps1     -> perf-optimizer    (53)        NEW
src\tools\user\Repair-AudioAdvanced.ps1     -> audio-repair      (56)        NEW
src\tools\user\Repair-TeamsCamera.ps1       -> camera-mic-repair (84+97+77)  MODIFIED (add ReinstallDriver)
src\registry\tools.psd1                                                       MODIFIED (3 new entries + edit 84)
```

No new core helper. Destructive sub-actions gated (Yes/No Default No; printer/perf/audio changes are
recoverable so the tools are Modifies, not Disruptive). `Read-Host` is not needed by any 6D tool.

### Tool 1: `printer-repair` (52 + 98) - Modifies, Admin=$true

`Repair-PrinterIssues` / `New-ToolRun -Id 'printer-repair'`.

- **Report (always):** installed printers via `Get-Printer` (Name, PrinterStatus, Type, PortName, Shared);
  Spooler service Status + StartType (`Get-Service Spooler`); stuck-job count via `Get-PrintJob -PrinterName
  *`. Empty printers -> note "no printers found".
- **Actions** (`@('None','RestartSpooler','ClearJobs','ClearSpoolFolder','RemoveGhostPrinters','FullReset')`):
  - `RestartSpooler` - `Restart-Service Spooler -Force`; report new status.
  - `ClearJobs` - confirm; cancel all queued jobs (`Get-PrintJob -PrinterName * | Remove-PrintJob`); report count.
  - `ClearSpoolFolder` (the v8 tool 98 behavior) - confirm; `Stop-Service Spooler -Force` -> remove the
    CONTENTS of `%SystemRoot%\System32\spool\PRINTERS` (Get-ChildItem | Remove-Item, scoped, never the dir)
    -> `Start-Service Spooler`; report new status + files cleared.
  - `RemoveGhostPrinters` - confirm; remove printers whose status is Offline/Error
    (`Get-Printer | Where-Object { $_.PrinterStatus -in 'Offline','Error' } | Remove-Printer`); report count.
  - `FullReset` - confirm; stop Spooler -> clear PRINTERS folder -> start Spooler (the deep reset =
    tool 98's full behavior); report.
- Risk Modifies; RequiresAdmin $true (Spooler service control + system32 spool dir).

### Tool 2: `perf-optimizer` (53) - Modifies, Admin=$true

`Optimize-Performance` / `New-ToolRun -Id 'perf-optimizer'`.

- **Report (always, read-only):** CPU model + load (`Get-Counter '\Processor(_Total)\% Processor Time'`);
  RAM used/total + percent; top-5 CPU processes; top-5 working-set processes; startup program count
  (`Get-CimInstance Win32_StartupCommand`).
- **Actions** (`@('None','OpenStartupManager','ClearTempCaches','SetPerformanceVisualEffects',
  'OptimizeVirtualMemory')`):
  - `OpenStartupManager` - GUI: `Start-Process 'ms-settings:startupapps'` (or Task Manager startup);
    advise disabling unneeded entries.
  - `ClearTempCaches` - confirm; clear CONTENTS of `$env:TEMP` and `C:\Windows\Temp` (scoped, contents-only);
    report MB freed. (Cross-reference temp-cleanup 11.)
  - `SetPerformanceVisualEffects` - confirm; set HKCU VisualFXSetting to "best performance"
    (`HKCU:\...\Explorer\VisualEffects\VisualFXSetting = 2`); note logoff/explorer-restart to apply.
  - `OptimizeVirtualMemory` - confirm; set the page file to system-managed
    (`Win32_ComputerSystem.AutomaticManagedPagefile = $true` via CIM/WMI); note reboot to apply.
- Risk Modifies; RequiresAdmin $true (page file + system-wide settings). Description cross-references
  performance-metrics (7), running-processes (4), temp-cleanup (11), startup-programs (16).

### Tool 3: `audio-repair` (56) - Modifies, Admin=$true

`Repair-AudioAdvanced` / `New-ToolRun -Id 'audio-repair'`.

- **Report (always):** audio devices via `Get-CimInstance Win32_SoundDevice` (Name + Status); the three
  audio services (`Audiosrv`, `AudioEndpointBuilder`, `RpcSs`) status.
- **Actions** (`@('None','RestartAudioServices','ResetAudioSettings','RunAudioTroubleshooter')`):
  - `RestartAudioServices` - restart `AudioEndpointBuilder` then `Audiosrv` (order matters - endpoint
    builder is a dependency), `-Force`; report new status.
  - `ResetAudioSettings` - confirm; cycle the audio stack so Windows re-detects endpoints: stop
    `Audiosrv` + `AudioEndpointBuilder` -> disable then re-enable the audio (MEDIA-class) PnP devices
    (`Get-PnpDevice -Class MEDIA` | Disable/Enable `-Confirm:$false`) -> start the services; report status.
  - `RunAudioTroubleshooter` - GUI: launch the Windows audio troubleshooter
    (`Start-Process 'ms-settings:troubleshoot'` or `msdt.exe -id AudioPlaybackDiagnostic`).
- Risk Modifies; RequiresAdmin $true (audio service control).

### Modification: `camera-mic-repair` (was teams-camera-repair, 84+97; now +77)

Edit `src\tools\user\Repair-TeamsCamera.ps1` (function `Repair-TeamsCamera`, Id `teams-camera-repair`).
**Keep the Id `teams-camera-repair` and Function name unchanged** (changing the Id/Function would break the
New-ToolRun-Id<->registry AST test and existing references); change ONLY the registry Name + Tags +
Description, and ADD one action.

- Registry edit (entry LegacyId 84): Name -> `Camera and Mic Repair`; Tags -> add `'webcam','driver'`
  (e.g. `@('teams','camera','microphone','media','webcam','driver')`); Description -> note it also does a
  general webcam driver reinstall.
- Add `'ReinstallDriver'` to the action menu choices (now `@('None','FixPermissions','ResetMediaStack',
  'ReinstallDriver')`).
- `ReinstallDriver` action (the tool-77 driver-level steps, using the `$cams` already gathered in the
  report): warn it removes the camera driver and **a REBOOT is required** (camera offline until reboot) +
  confirm (Yes/No, Default No). On Yes: close camera-holding apps (reuse the hogs list); for each camera PnP
  device, `& pnputil.exe /remove-device $cam.InstanceId` (Windows reinstalls on reboot); then optionally a
  WU camera-driver scan (`Microsoft.Update.Session` COM, filter Title `camera|webcam|video|imaging`,
  REPORT-ONLY - list pending updates, do not install); Complete Success noting "reboot to finish driver
  reinstall". Wrap pnputil/WU in try/catch (degrade to advice).
- RequiresAdmin stays $true; Risk stays Modifies (ReinstallDriver is gated).

## Registry entries

Append three new entries; edit the existing LegacyId-84 entry.

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable | Tags |
|---|---|---|---|---|---|---|---|---|
| printer-repair | 52 | Printer Troubleshooter | Repair-PrinterIssues | User | $true | Modifies | $true | printer,spooler,print,queue |
| perf-optimizer | 53 | Performance Optimizer | Optimize-Performance | User | $true | Modifies | $true | performance,startup,pagefile,optimize |
| audio-repair | 56 | Audio Troubleshooter | Repair-AudioAdvanced | User | $true | Modifies | $true | audio,sound,playback,services |
| teams-camera-repair (EDIT) | 84 | Camera and Mic Repair | Repair-TeamsCamera | User | $true | Modifies | $true | teams,camera,microphone,media,webcam,driver |

LegacyIds 52/53/56 are free and numeric. All `Category = 'User'`. Tool count 77 -> 80.

## Testing

- Build green + full suite green: ASCII-only encoding gate, template-compliance gates (approved verbs
  Repair/Optimize; `[switch]$Silent`; run-bracketing; `New-ToolRun -Id` <-> registry Id AST test - the
  camera tool's Id stays `teams-camera-repair` so this still passes), registry-mapping for the 3 new tools,
  unique Id/LegacyId.
- No new unit tests (interactive I/O wrappers around services/CIM/pnputil; existing template/registry/
  encoding gates cover them).
- **Smoke (non-elevated dev session):**
  - `printer-repair -Silent`, `perf-optimizer -Silent`, `audio-repair -Silent` -> RequiresAdmin ->
    dispatcher refuses non-elevated (exit 1); quote the refusal.
  - `teams-camera-repair -Silent` -> still refused (RequiresAdmin); the ReinstallDriver action is unreachable
    under -Silent (None default) and admin-refused regardless. Verify the modified tool still builds + the
    suite stays green.
  - NEVER run the destructive actions (any Clear*, Remove*, FullReset, SetVisualEffects, OptimizeVirtualMemory,
    RestartAudioServices, ReinstallDriver) in the dev session. Verify by reading + the admin refusal.

## Conventions carried from prior batches

Faithful BEHAVIOR port (not code); `Write-ToolOutput`/`Read-ToolChoice` only (no `Write-Host`/`Read-Host`;
v8's `Show-GUIConfirm` becomes `Read-ToolChoice`); tight tech-facing summaries; Info headline + Detail rows;
empty-collection early-return Warning; descriptions/tags match actual v8 behavior (perf-optimizer
cross-references the overlapping tools); ASCII-only source (UTF-8 BOM + trailing newline); PS 5.1 (no
ternary/`??`/`&&`; never assign `$input`/`$matches`/`$profile`). Service restarts re-query status and report
honestly (Warning if a service did not come back). Scoped removals only (spool PRINTERS contents, TEMP
contents - never a drive root). Re-query printers/services at action time.

## Out of scope

Tool 98 folded into 52; tool 77 folded into the camera tool. perf-optimizer overlaps but is ported per Matt;
the overlap is cross-referenced. No printer-driver reinstall (only spooler/queue/ghost-printer repair). No
deep audio-driver reinstall beyond service restart + the Windows troubleshooter. Sub-batch 6A (Outlook) is
a separate spec - the last of batch 6.
