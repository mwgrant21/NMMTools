# Batch 6B: Teams Tools - Design Spec

**Date:** 2026-06-13
**Scope:** Port v8 Teams tools 83, 84, 85, 97 into v9 (sub-batch 6B of batch 6).
**Status:** Approved (brainstormed with Matt 2026-06-13). Next: writing-plans -> 6B implementation plan.

## Batch 6 decomposition (context)

Batch 6 ("Common User Issues") is decomposed into 5 themed sub-batches (decided WITH Matt). Done so far:
6C Shell/UI (merged 2026-06-13, 70 tools). This spec is **6B Teams**. Remaining after 6B: 6A Outlook/M365,
6D Devices/Perf/Print, 6E Profile/Cred/Network.

## Goal

Port the four v8 Teams tools into v9 as three report-then-action tools (84 and 97 are merged). v8 monolith
at `C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference (functions: `Repair-TeamsAddin` L9643,
`Reset-TeamsPermissions` L9721, `Diagnose-TeamsDeep` L9830, `Reset-TeamsCameraMediaStack` L11423).

## Usage model (unchanged)

Interactive technician at the keyboard; toolkit elevates at launch. Optimize the interactive experience;
`-Silent` only needs to be SAFE (report-only via None default; admin tool refuses non-elevated silent).
These are per-user Teams repairs; admin is per-tool (see classifications).

## Decisions made with Matt (do not re-litigate)

1. **Merge 84 (camera/mic permissions) + 97 (camera media-stack reset) into ONE `teams-camera-repair`
   tool** with actions FixPermissions (84) and ResetMediaStack (97). They target the same area (Teams
   camera) and v8 cross-references them. 6B is therefore 3 tools: `teams-addin-repair` (83),
   `teams-deep-diagnostic` (85), `teams-camera-repair` (84+97). Mark 84 and 97 consolidated in parity.
2. **v8 -> report-then-action.** Each tool runs a read-only report first, then
   `Read-ToolChoice -Choices @('None', <actions>) -Default 'None' -Silent:$Silent`. Under `-Silent` -> None
   -> report only.
3. **Process-kill gating.** Any action that closes Outlook (unsaved drafts) or browsers/meeting apps must
   warn + LIST what it will close + confirm (Yes/No, Default No) first - the batch-4 webcam-audio
   convention. Closing Teams itself is benign/expected and needs no separate confirm.
4. **`teams-deep-diagnostic` RequiresAdmin=$false** so the read-only 11-check diagnostic is runnable any
   time. The repair's admin-only steps (TokenBroker service restart, AAD/Operational event-log read)
   degrade gracefully with try/catch warnings (faithful to v8). The toolkit launches elevated anyway, so
   the full repair still works in practice. `teams-camera-repair` is RequiresAdmin=$true (FrameServer
   service + PnP device cycle genuinely require it).
5. **Category 'User'** (batch 6), consistent with 6C. Tool count 70 -> 73.

## Architecture

```
src\tools\user\Repair-TeamsAddin.ps1        -> teams-addin-repair     (83)
src\tools\user\Repair-TeamsDeep.ps1         -> teams-deep-diagnostic  (85)
src\tools\user\Repair-TeamsCamera.ps1       -> teams-camera-repair    (84+97)
```

No new core helper - each tool is self-contained (uses the existing `Write-ToolOutput`/`Read-ToolChoice`/
`New-ToolRun`/`Complete-ToolRun` interface). The shared bits (Teams process-name list, `Start-Process
'ms-teams:'` relaunch) are small and inlined per tool, consistent with 6C. The "warn + list + confirm
before closing apps" gate is inlined in each tool that needs it.

### Tool 1: `teams-addin-repair` (83) - Modifies, Admin=$false

`Repair-TeamsAddin` / `New-ToolRun -Id 'teams-addin-repair'`.

- **Report (always):** New Teams installed? (`Get-AppxPackage -Name MSTeams`); AddinLoader DLL present?
  (newest `Microsoft.Teams.AddinLoader.dll` under `%LOCALAPPDATA%\Microsoft\TeamsMeetingAddin`); current
  Outlook add-in LoadBehavior (`HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect`);
  DisabledItems key present?
- **Actions** (`@('None','RepairAddin')`):
  - `RepairAddin` - warn it will CLOSE OUTLOOK (save work first) + confirm (Yes/No, Default No). Then:
    stop OUTLOOK/ms-teams/MSTeams/Teams; locate the newest AddinLoader DLL (if missing -> Warning, advise
    reinstall Teams); `regsvr32 /s` the DLL (report exit code, continue on non-zero - 32/64-bit mismatch
    is non-fatal); set `LoadBehavior=3` DWord (create key if absent); remove the Outlook `DisabledItems`
    key if present; clear `%LOCALAPPDATA%\Microsoft\TeamsMeetingAddin\Cache` contents; relaunch Teams
    (`Start-Process 'ms-teams:'`). Success summary.
- Risk Modifies; RequiresAdmin $false (HKCU + per-user DLL regsvr32).

### Tool 2: `teams-deep-diagnostic` (85) - Modifies, Admin=$false

`Repair-TeamsDeep` / `New-ToolRun -Id 'teams-deep-diagnostic'`.

- **Report (always, read-only - the 11 v8 checks):** (1) MSTeams AppX registration; (2) MSIX package
  folder + size (`%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe`); (3) `dsregcmd /status` AzureAdJoined /
  WamDefaultSet / AzureAdPrt; (4) `Microsoft-Windows-AAD/Operational` recent errors (try/catch - needs
  elevation, degrade to "could not read"); (5) Credential Manager Teams/M365 entries (`cmdkey /list`);
  (6) network reachability to teams.microsoft.com:443, login.microsoftonline.com:443, graph.microsoft.com:443,
  teams.microsoft.com:3478 (use the timeout-bounded `Test-TcpEndpoint` helper pattern, NOT bare
  Test-NetConnection which can hang); (7) TLS issuer of login.microsoftonline.com (proxy-intercept hint);
  (8) proxy config (WinHTTP + IE settings); (9) Teams firewall BLOCK rules; (10) Teams scheduled tasks;
  (11) newest Teams log tail for auth errors. Tally issue codes; write a report file to
  `%TEMP%\TeamsDeepDiag_<ts>.txt`; summarize "N issues found".
- **Action** (`@('None','ApplyRepairs')`):
  - `ApplyRepairs` - warn it CLOSES TEAMS and CLEARS credentials/WAM/cache (you will be signed out and
    must sign in again) + confirm (Yes/No, Default No). Then: stop ms-teams/MSTeams/Teams/TeamsMeetingAddin;
    delete matching Credential Manager entries via `cmdkey /delete` (Teams/M365 targets only); clear WAM
    token state (`...\MSTeams_8wekyb3d8bbwe\Settings` and `...\AC\TokenBroker` contents); clear MSIX
    `LocalCache` contents; re-register the MSTeams AppX (`Add-AppxPackage -Register <manifest>
    -DisableDevelopmentMode`, try/catch -> advise reinstall on failure); restart `TokenBroker` service
    (try/catch -> "reboot recommended" if not elevated/fails); relaunch Teams. Report what was done.
- Risk Modifies; RequiresAdmin $false (diagnostic needs none; repair admin-steps degrade gracefully).
  The action is gated behind a confirm; under `-Silent` -> None -> diagnostic report only.

### Tool 3: `teams-camera-repair` (84+97) - Modifies, Admin=$true

`Repair-TeamsCamera` / `New-ToolRun -Id 'teams-camera-repair'`.

- **Report (always, read-only):** camera devices via `Get-PnpDevice -Class Camera` (FriendlyName +
  Status; fall back to FriendlyName "*camera*"); webcam + microphone ConsentStore `Value`
  (`HKCU:\...\CapabilityAccessManager\ConsentStore\webcam` and `\microphone`); GPO/MDM policy-block status
  (`HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy` LetAppsAccessCamera/LetAppsAccessMicrophone == 2).
- **Actions** (`@('None','FixPermissions','ResetMediaStack')`):
  - `FixPermissions` (v8 tool 84) - set webcam + microphone ConsentStore `Value=Allow` (and the
    `NonPackaged` subkey); flip any Teams-specific (`ms-teams|MSTeams|Teams`) `Deny` entries under
    `NonPackaged` to `Allow`; report (do NOT silently fix) any GPO/MDM policy block; restart Teams. Success
    (or Warning if a policy block is detected - cannot override IT policy).
  - `ResetMediaStack` (v8 tool 97) - warn + LIST the camera-using apps it will close (Teams, Webex, Zoom,
    Cisco, Lync, browsers, Camera app) + confirm (Yes/No, Default No). Then: stop those processes; clear
    Teams media cache (classic `%APPDATA%\Microsoft\Teams\{Cache,blob_storage,databases,GPUCache,IndexedDB,
    Local Storage,tmp}` and new `...\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\{Cache,EBWebView}`);
    set webcam ConsentStore `Value=Allow`; restart the `FrameServer` service (try/catch); cycle the camera
    PnP device (Disable then Enable; re-enable any errored device) via `Disable-PnpDevice`/`Enable-PnpDevice
    -Confirm:$false`. Report what was reset.
- Risk Modifies; RequiresAdmin $true (FrameServer service + PnP device operations). Dispatcher refuses
  non-elevated `-Silent`.

## Registry entries (appended to tools.psd1)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable | Tags |
|---|---|---|---|---|---|---|---|---|
| teams-addin-repair | 83 | Teams Meeting Add-in Repair | Repair-TeamsAddin | User | $false | Modifies | $true | teams,outlook,addin,meeting |
| teams-deep-diagnostic | 85 | Teams Deep Diagnostic and Repair | Repair-TeamsDeep | User | $false | Modifies | $true | teams,wam,msal,auth,diagnostic |
| teams-camera-repair | 84 | Teams Camera and Mic Repair | Repair-TeamsCamera | User | $true | Modifies | $true | teams,camera,microphone,media |

LegacyId 84 for the merged camera tool (97 folds in - typing `97` will not dispatch, consistent with prior
consolidations). LegacyIds 83/85/84 are free and numeric. All `Category = 'User'`, `SilentCapable = $true`.

## Testing

- Build green + full suite green: ASCII-only encoding gate, template-compliance gates (approved verb
  `Repair`; `[switch]$Silent`; run-bracketing; `New-ToolRun -Id` <-> registry Id AST test), registry-mapping
  for the 3 new tools, unique Id/LegacyId.
- No new unit tests (these are interactive I/O wrappers around OS/registry operations; existing
  template/registry/encoding gates cover them, consistent with prior batches). The `teams-deep-diagnostic`
  network check REUSES the nested timeout-bounded `Test-TcpEndpoint` TcpClient helper pattern (from
  `Test-VPNHealth.ps1` / `Test-M365Connectivity.ps1`) rather than a hang-prone bare Test-NetConnection.
- **Smoke (non-elevated dev session):**
  - `teams-addin-repair -Silent` -> report only (None default), exit 0; quote summary.
  - `teams-deep-diagnostic -Silent` -> runs the read-only 11-check diagnostic + None default (no repair),
    exit 0; quote the "N issues found" summary.
  - `teams-camera-repair -Silent` -> RequiresAdmin -> dispatcher refuses non-elevated (exit 1); quote.
  - NEVER run the destructive actions (RepairAddin, ApplyRepairs, FixPermissions, ResetMediaStack) in the
    dev session - they close apps, clear credentials, and cycle devices. Verify by reading + silent report.

## Conventions carried from prior batches

Faithful BEHAVIOR port (not code); `Write-ToolOutput`/`Read-ToolChoice` only (no `Write-Host`/`Read-Host`);
tight tech-facing summaries; Info headline + Detail rows; empty-collection / absent-package early-return
Warning; descriptions/tags match actual v8 behavior; ASCII-only source (UTF-8 BOM + trailing newline); PS
5.1 (no ternary/`??`/`&&`; never assign `$input`/`$matches`/`$profile`). Destructive removals scoped to
explicit Teams per-user paths (never a drive root); the merged camera tool's ResetMediaStack and the
add-in/deep-repair app-closing steps are gated (warn + list + confirm Default No). Network reachability uses
the timeout-bounded TcpClient helper. Report counts/outcomes reflect reality (e.g. policy-block detection ->
Warning, not false Success).

## Out of scope

Tools 84/97 are merged (97 consolidated -> 84). teams-cache (24, batch 2) already covers basic Teams cache
clearing and is cross-referenced, not duplicated. Credential clearing in teams-deep-diagnostic is scoped to
Teams/M365 entries only (the general Credential Manager tool is 60, batch 6E). No Teams reinstall automation
(the tools advise reinstall when the package is unrecoverable). Sub-batches 6A/6D/6E are separate specs.
