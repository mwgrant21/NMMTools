# Batch 7 (Part 2): Quick Fixes Q1-Q9 - Design Spec

**Date:** 2026-06-14
**Scope:** Port v8 Quick Fixes Q1-Q9 into v9 as nine new `QuickFix`-category tools. This is the FINAL
sub-batch; it completes v8 parity.
**Status:** Approved (brainstormed with Matt 2026-06-14). Next: writing-plans -> implementation plan.

## Context

Batches 1-6 + batch 7 Part 1 are complete (91 tools, 71/71 tests). v8 monolith at
`C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference. v8 Quick Fix function locations:

| v8 | v8 function | Line |
|---|---|---|
| Q1 Office | `Repair-Office` | 2282 |
| Q2 OneDrive | `Repair-OneDrive` | 2304 |
| Q3 Teams | `Repair-Teams` | 2320 |
| Q4 Login | `Repair-Login` | 2347 |
| Q5 Wi-Fi | `Repair-WiFi` | 3950 |
| Q6 VPN | `Repair-VPN` | 3984 |
| Q7 Audio/Video | `Repair-AudioVideo` | 4018 |
| Q8 Docking | `Repair-Docking` | 4056 |
| Q9 Browser Backup | `Repair-BrowserBackup` | 4087 |

The v8 Quick Fixes are self-contained, deliberately abbreviated, aggressive one-click workflows (force-kill
apps, run a fixed sequence, no menus). They are NOT calls to the full tools - they re-implement shortened
steps. Their value is speed for the common helpdesk scenario.

## Decisions made with Matt (do not re-litigate)

1. **Self-contained v9 ports.** Each Quick Fix is its own tool re-implementing the abbreviated steps with v9
   conventions; no refactor of the 91 merged tools. Each cross-references its full counterpart in the
   description.
2. **One upfront confirm, then run all.** Not report-then-action. Each tool: `New-ToolRun` -> describe the
   steps via `Write-ToolOutput` -> ONE gate `Read-ToolChoice -Choices @('Yes','No') -Default 'No'
   -Silent:$Silent` -> run all steps -> honest `Complete-ToolRun`. Under `-Silent` the gate returns `No` ->
   `Skipped` no-op. Destructive Quick Fixes are `Risk='Disruptive'` (dispatcher also refuses silent-no-force).
3. **New `Category='QuickFix'`** for all 9. Auto-letters alphabetically to **E** (A=Browser B=Cloud
   C=Diagnostics D=Laptop E=QuickFix F=Repair G=Security H=User). `build.ps1` recurses `src\tools`, so a new
   `src\tools\quickfix\` folder builds with no menu/test change (same as Security in Part 1).
4. **Function verb `Invoke-`** (approved; fits a workflow macro). Ids end in `-quick-fix`. LegacyId = `Q1`..`Q9`.

## The nine tools

`New-ToolRun -Id '<id>'` MUST equal the registry `Id`. All `SilentCapable = $true`. `Complete-ToolRun
-Status` accepts only `Success | Failed | Warning | Skipped`. Scoped process lists (never broad `-like`
wildcards); `cmdkey`/`Remove-Item` count only confirmed results; cache clears are contents-only (never a
folder root).

### Q1: office-quick-fix

- **Function** `Invoke-OfficeQuickFix`, **Category** QuickFix, **RequiresAdmin** `$false`, **Risk**
  `Disruptive`.
- **Steps:** close Office apps (SCOPED: `OUTLOOK,WINWORD,EXCEL,POWERPNT,ONENOTE,MSACCESS` - NOT v8's broad
  `*Office*/*Word*/*Excel*` match) -> clear `MicrosoftOffice` cmdkey creds (anchored `^\s*Target:\s*` parse;
  count only `$LASTEXITCODE -eq 0`) -> launch `OfficeC2RClient.exe /update user` if present.
- **Summary:** apps closed, N creds cleared, C2R repair launched. Cross-ref `office-repair` (22).
- **Tags:** `quickfix`,`office`,`m365`,`credentials`.

### Q2: onedrive-quick-fix

- **Function** `Invoke-OneDriveQuickFix`, **RequiresAdmin** `$false`, **Risk** `Modifies`.
- **Steps:** stop OneDrive -> `OneDrive.exe /reset` (resolve exe from
  `%LOCALAPPDATA%\Microsoft\OneDrive\OneDrive.exe` OR `%PROGRAMFILES%`/`%PROGRAMFILES(X86)%` - v8 used only
  LOCALAPPDATA) -> wait -> relaunch OneDrive.
- **Honesty:** if the OneDrive exe is not found, report **Warning** "OneDrive not installed at the expected
  paths" and finish. Cross-ref `onedrive-repair` (23).
- **Tags:** `quickfix`,`onedrive`,`sync`,`reset`.

### Q3: teams-quick-fix

- **Function** `Invoke-TeamsQuickFix`, **RequiresAdmin** `$false`, **Risk** `Modifies`.
- **Steps:** close Teams (classic `Teams` AND New `ms-teams`/`MSTeams`) -> clear cache CONTENTS-only: classic
  `%APPDATA%\Microsoft\Teams\Cache` + `\blob_storage`; New Teams
  `%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache` (contents) -> relaunch (classic Update.exe if
  present, else New Teams via shell). v8 cleared classic only.
- **Summary:** Teams closed, cache cleared, restarted. Cross-ref `teams-cache` (24).
- **Tags:** `quickfix`,`teams`,`cache`.

### Q4: login-quick-fix

- **Function** `Invoke-LoginQuickFix`, **RequiresAdmin** `$false`, **Risk** `Modifies`.
- **Steps:** clear Office/M365 cmdkey creds (matching `MicrosoftOffice|Office`, anchored parse, count
  confirmed) -> report `dsregcmd /status` AzureAd join lines (read-only).
- **Summary:** N creds cleared; advise re-sign-in. Cross-ref `credential-manager` (60), `m365-auth-reset` (79).
- **Tags:** `quickfix`,`login`,`credentials`,`signin`.

### Q5: wifi-quick-fix

- **Function** `Invoke-WiFiQuickFix`, **RequiresAdmin** `$true`, **Risk** `Disruptive`.
- **Steps:** restart the Wi-Fi adapter (`Get-NetAdapter` where Name like `*Wi-Fi*`/`*Wireless*` ->
  `Restart-NetAdapter -Confirm:$false`) -> `ipconfig /release` + `/renew` -> `ipconfig /flushdns`.
- **Honesty:** if no Wi-Fi adapter found, report **Warning** and skip the adapter step but still flush DNS.
  Cross-ref `wifi-diagnostics` (39), `network-stack-reset` (67).
- **Tags:** `quickfix`,`wifi`,`network`,`dns`.

### Q6: vpn-quick-fix

- **Function** `Invoke-VpnQuickFix`, **RequiresAdmin** `$true`, **Risk** `Disruptive`.
- **Steps:** disconnect all VPNs (`Get-VpnConnection` -> `rasdial <name> /disconnect`) -> `ipconfig
  /flushdns` -> `netsh interface ip delete arpcache`. **DROP v8's `Remove-Item
  %APPDATA%\Microsoft\Network\Connections\Pbk\*`** - that deleted VPN connection PROFILES, not cache (data
  loss); v9 does not touch the Pbk.
- **Honesty:** if no VPN connections, report that and still flush DNS/ARP. Cross-ref `vpn-health` (40).
- **Tags:** `quickfix`,`vpn`,`network`,`dns`.

### Q7: av-prep-quick-fix

- **Function** `Invoke-AvPrepQuickFix`, **RequiresAdmin** `$true`, **Risk** `Disruptive`.
- **Steps:** free camera/mic by closing meeting apps + browsers (`Teams,ms-teams,Zoom,Skype,msedge,chrome,
  firefox`) -> restart `Audiosrv` -> open the Camera app (`microsoft.windows.camera:`).
- **Summary:** N apps closed, audio restarted, camera opened. The upfront confirm warns the browser/app
  closure. Cross-ref `webcam-audio-test` (41), `teams-camera-repair` (84).
- **Tags:** `quickfix`,`audio`,`camera`,`meeting`.

### Q8: docking-quick-fix

- **Function** `Invoke-DockingQuickFix`, **RequiresAdmin** `$false`, **Risk** `Modifies`.
- **Steps:** `DisplaySwitch.exe /detect` -> `DisplaySwitch.exe /extend`. **DROP v8's `Remove-Item
  HKCU:\Software\Microsoft\Windows\DWM -Recurse`** - that deleted the entire DWM settings key (risky, can
  break desktop composition settings); v9 does display detect/extend only and advises Win+P.
- **Summary:** displays detected and extended. Cross-ref `docking-displays` (44).
- **Tags:** `quickfix`,`docking`,`display`,`monitor`.

### Q9: browser-backup-quick-fix

- **Function** `Invoke-BrowserBackupQuickFix`, **RequiresAdmin** `$false`, **Risk** `Disruptive`.
- **Steps:** close browsers via `Close-Browsers` (core helper) -> resolve dest via `Get-BrowserBackupRoot`
  (M:\BrowserBackups\<user> or Desktop fallback) -> for each browser in `Get-BrowserCatalog`, for each
  `Get-BrowserProfiles`, copy that browser's `BackupFiles` into a timestamped
  `QuickBackup_<yyyyMMdd_HHmmss>` dir -> `Compress-Archive` to a .zip.
- **DRY:** reuses the existing browser core helpers (`src\core\08-browser-helpers.ps1`) so the quick backup's
  file-set can never drift from `browser-backup-restore` (48). v8 hand-coded a Chrome/Edge-only abbreviated
  copy.
- **Honesty:** count browsers/profiles actually backed up; if the dest root is unwritable, report **Warning**
  with the attempted path. Cross-ref `browser-backup-restore` (48).
- **Tags:** `quickfix`,`browser`,`backup`,`bookmarks`.

## Registry entries

Nine new entries appended to `src/registry/tools.psd1`, each
`@{ Id; LegacyId; Name; Category='QuickFix'; Function; Description; RequiresAdmin; SilentCapable=$true;
Risk; Tags }`. LegacyId = `Q1`..`Q9`.

## Testing

- Existing template/registry/encoding AST suite auto-covers the 9 new tools (Id<->New-ToolRun match, approved
  verbs, `[switch]$Silent`, ASCII-only, UTF-8 BOM + trailing newline, registry completeness). Suite 71 -> 80.
- New `Category='QuickFix'` flows through the dynamic landing menu with no code change (precedent: Browser,
  User, Security categories added the same way).
- Q9 reuses the browser core helpers; `browser-helpers.tests.ps1` already locks their invariants - no new
  helper tests needed.
- Per-tool: PSScriptAnalyzer clean; `build.ps1` compiles; the confirm gate under `-Silent` returns `No` ->
  `Skipped` with no side effect.

## Parity impact

- Quick Fixes Q1-Q9 -> **ported**. Tool count 91 -> **100**. Checklist header -> "100 of ~111 items ported;
  v8 parity COMPLETE."
- After this sub-batch, **every v8 menu item is ported or consciously consolidated** - v9 reaches full parity
  with the v8 monolith.

## Out of scope

- Re-implementing the full tools' careful per-step flows inside Quick Fixes (Quick Fixes are intentionally
  abbreviated; the full tools remain the thorough path).
- v8's two dangerous behaviors are intentionally dropped: Q6 Pbk-profile deletion and Q8 DWM-key deletion.
