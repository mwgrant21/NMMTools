# Batch 6A: Outlook / M365 Tools - Design Spec

**Date:** 2026-06-14
**Scope:** Port v8 tools 76, 79, 80, 81, 82, 96 into v9; consolidate 106 into the merged search tool
and 78 into the merged M365 auth tool. Sub-batch 6A of batch 6 - the LAST sub-batch.
**Status:** Approved (brainstormed with Matt 2026-06-14). Next: writing-plans -> 6A implementation plan.

## Batch 6 decomposition (context)

Batch 6 ("Common User Issues") is decomposed into 5 themed sub-batches. Done: 6C Shell/UI, 6B Teams,
6E Profile/Cred/Network, 6D Devices/Perf/Print (all merged; 80 tools, suite 71/71). This spec is **6A**.
After 6A, batch 6 is complete and only **batch 7** (Security/Domain 51/91/92/93/101 + Quick Fixes Q1-Q9)
remains.

## Goal

Port the Outlook/M365 repair tools, with two consolidations. v8 monolith at
`C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference. v8 function locations:

| v8 # | v8 function | Line |
|-----:|---|---|
| 76 | `Repair-OutlookSearch` | 9058 |
| 78 | `Fix-SharedMailbox` | 9455 |
| 79 | `Clear-M365Tokens` | 9488 |
| 80 | `Fix-AutoDiscover` | 9530 |
| 81 | `Rebuild-OutlookOST` | 9567 |
| 82 | `Repair-OutlookProfile` | 9606 |
| 96 | `Repair-OutlookAddins` | 11282 |
| 106 | `Repair-OutlookSearchIndex` | 11742 |

## Usage model (unchanged)

Interactive technician at the keyboard; toolkit elevates at launch. Optimize the interactive experience;
`-Silent` only needs to be SAFE (report-only). Every tool follows the **report-then-action** pattern: the
read-only report runs always, then `Read-ToolChoice -Choices @('None', <actions>) -Default 'None' -Silent`
gates the destructive arm, so under `-Silent` the tool reports and does nothing. Only
`outlook-search-repair` is admin (WSearch service + `%ProgramData%` index DB); the rest operate in HKCU +
user-profile cache + `cmdkey`, so they run unelevated.

## Decisions made with Matt (do not re-litigate)

1. **Merge tool 106 (Repair Outlook Search Index) INTO tool 76 -> `outlook-search-repair`.** 76 and 106
   are near-duplicates (close Outlook -> WSearch restart -> rebuild index). The merged tool keeps 76's
   service-restart and 106's full index rebuild (delete `Windows.edb` + logs) plus 106's Outlook
   `Search\Catalog` registry reset. Mark 106 consolidated -> the merged tool.
2. **Fold tool 78 (Shared Mailbox Access Fix) INTO tool 79 -> `m365-auth-reset`.** 78's clear-Office-creds
   + clear-AutoDiscover-cache + remove-`OutlookSecurityMode` is the same auth/cred reset 79 performs, with
   a shared-mailbox slant. It becomes the `ClearTokensAndSharedMailbox` action arm. Mark 78 consolidated
   -> 79.
3. **Keep tool 80 (`autodiscover-fix`) separate.** Its DNS-flush + AutoDiscover-endpoint-test angle is a
   distinct symptom (AutoDiscover misconfiguration, not auth). Cross-references `m365-auth-reset` in its
   description; does not duplicate the cred clear.
4. **Category 'User'** for all 6 new tools (batch 6). Tool count 80 -> 86.

## Approved-verb renames

v8 uses non-approved verbs; v9 functions must use approved PS verbs (`Get-Verb`):

| v8 function | v9 function | Reason |
|---|---|---|
| `Fix-SharedMailbox` (78) | folded into `Reset-M365Auth` | `Fix` not approved; consolidated anyway |
| `Clear-M365Tokens` (79) | `Reset-M365Auth` | `Clear` is approved, but `Reset` better fits the merged 78+79 scope and the `m365-auth-reset` Id |
| `Fix-AutoDiscover` (80) | `Repair-AutoDiscover` | `Fix` not approved |
| `Rebuild-OutlookOST` (81) | `Reset-OutlookOst` | `Rebuild` not approved; `Reset` is approved and accurate (rename forces re-sync) |
| `Repair-OutlookSearch` (76) | `Repair-OutlookSearch` | `Repair` approved - unchanged |
| `Repair-OutlookProfile` (82) | `Repair-OutlookProfile` | `Repair` approved - unchanged |
| `Repair-OutlookAddins` (96) | `Repair-OutlookAddins` | `Repair` approved - unchanged |

## The six tools

`New-ToolRun -Id` literal MUST equal the registry `Id` (AST template test enforces top-level-only). All are
`SilentCapable = $true` (report arm runs under `-Silent`).

### 1. outlook-search-repair (76 + 106)

- **Function** `Repair-OutlookSearch`, **Category** User, **RequiresAdmin** `$true`, **Risk** `Modifies`
  (mirrors `windows-search-rebuild` 54 - index rebuild is self-healing, not `Disruptive`).
- **Report (always):** WSearch service status + StartType; `Windows.edb` path + size; whether Outlook is
  running; Outlook `Search\Catalog` reg presence.
- **Actions:** `Read-ToolChoice -Choices @('None','RestartService','RebuildIndex') -Default 'None' -Silent`.
  - `RestartService`: close Outlook (graceful then force), `Restart-Service WSearch -Force`.
  - `RebuildIndex`: close Outlook, `Stop-Service WSearch -Force`, delete
    `%ProgramData%\Microsoft\Search\Data\Applications\Windows\Windows.edb` + `*.log`, `Start-Service
    WSearch`, remove HKCU `...\Outlook\16.0\Search` `Catalog` value.
- **Honesty:** re-query WSearch after start; report **Warning** (not Success) if status != Running. Only
  claim `.edb` removed if `Test-Path` confirms it is gone (it is locked until WSearch stops - verify the
  stop first).
- **Tags:** `outlook`,`search`,`wsearch`,`index`.
- **Tags cross-ref:** description notes overlap with `windows-search-rebuild` (54, whole-OS search).

### 2. m365-auth-reset (79 + 78)

- **Function** `Reset-M365Auth`, **Category** User, **RequiresAdmin** `$false`, **Risk** `Modifies`
  (mirrors `credential-manager` 60 / `teams-deep-diagnostic` 85).
- **Report (always):** count of Office/M365 `cmdkey /list` entries (matching
  `MicrosoftOffice|office|microsoftonline|sharepoint|outlook`); presence of MSAL caches
  (`%LOCALAPPDATA%\Microsoft\OneAuth`, `...\IdentityCache`), WAM TokenBroker cache
  (`...\Microsoft\TokenBroker\Cache`); count of AutoDiscover cache files
  (`%LOCALAPPDATA%\Microsoft\Outlook\*autodiscover*`).
- **Actions:** `Read-ToolChoice -Choices @('None','ClearTokens','ClearTokensAndSharedMailbox') -Default
  'None' -Silent`.
  - `ClearTokens` (79): close Office apps (`OUTLOOK,TEAMS,WINWORD,EXCEL,ONENOTE,MSTEAMS,ms-teams`), delete
    matching `cmdkey` creds, clear OneAuth + IdentityCache + TokenBroker\Cache (**contents-only**, never
    the parent profile root).
  - `ClearTokensAndSharedMailbox` (78 fold-in): everything in `ClearTokens` plus delete AutoDiscover cache
    files and remove HKCU `...\Outlook\16.0\Outlook` `OutlookSecurityMode` value.
- **Honesty:** parse `cmdkey /list` with an anchored `^\s*Target:\s*` regex (6E credential-manager
  precedent); count only deletions where `$LASTEXITCODE -eq 0`. Clear cache folder **contents**, not the
  folder root.
- **Tags:** `outlook`,`m365`,`auth`,`token`,`wam`,`credential`.
- **Cross-ref:** description notes overlap with `credential-manager` (60) and `teams-deep-diagnostic` (85).

### 3. autodiscover-fix (80)

- **Function** `Repair-AutoDiscover`, **Category** User, **RequiresAdmin** `$false`, **Risk** `Modifies`.
- **Report (always):** AutoDiscover endpoint reachability (HEAD to
  `https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml`, 10s timeout); AutoDiscover cache file
  count; HKCU `...\Outlook\16.0\Outlook\AutoDiscover` reg-key presence.
- **Actions:** `Read-ToolChoice -Choices @('None','Fix') -Default 'None' -Silent`.
  - `Fix`: `ipconfig /flushdns`, delete `%LOCALAPPDATA%\Microsoft\Outlook\*autodiscover*`, remove the
    `AutoDiscover` reg key (recurse), re-test the endpoint and report the result.
- **Honesty:** report the endpoint test as **Warning** on failure (it is a network condition, not a tool
  failure); count actual files removed.
- **Tags:** `outlook`,`autodiscover`,`dns`,`exchange`.
- **Cross-ref:** notes `m365-auth-reset` also clears AutoDiscover cache (for auth/shared-mailbox cases).

### 4. outlook-ost-rebuild (81)

- **Function** `Reset-OutlookOst`, **Category** User, **RequiresAdmin** `$false`, **Risk** `Modifies`
  (rename keeps a `.bak` - recoverable).
- **Report (always):** list `%LOCALAPPDATA%\Microsoft\Outlook\*.ost` files with sizes; note if none
  (IMAP/online mode).
- **Actions:** `Read-ToolChoice -Choices @('None','RenameOst') -Default 'None' -Silent`.
  - `RenameOst`: close Outlook (graceful then force), **verify Outlook actually exited** before touching
    files, rename each `*.ost` -> `<name>.ost.bak_<yyyyMMdd_HHmmss>`.
- **Honesty:** if Outlook is still running after the close attempt, **abort with Warning** (the OST is
  locked - renaming would silently fail); report the actual renamed count, not the file count.
- **Tags:** `outlook`,`ost`,`cache`,`exchange`,`resync`.

### 5. outlook-profile-repair (82)

- **Function** `Repair-OutlookProfile`, **Category** User, **RequiresAdmin** `$false`, **Risk**
  `Disruptive` (wipes ALL profile settings/accounts; user must reconfigure - matches `browser-clear` /
  `temp-profile-repair` blast radius).
- **Report (always):** list HKCU `...\Outlook\16.0\Outlook\Profiles` subkeys (profile names) and the
  current `DefaultProfile`.
- **Actions:** `Read-ToolChoice -Choices @('None','RecreateProfile') -Default 'None' -Silent`. Because this
  is the nuclear option, selecting `RecreateProfile` interactively then requires a typed `REBUILD`
  confirmation via `Read-Host` before proceeding (the sanctioned "free-text after an interactive action"
  case - the v8 network-stack-reset `RESET` precedent). Under `-Silent` the choice defaults to `None`, so
  neither the action nor the `Read-Host` is ever reached.
  - `RecreateProfile`: close Outlook, **`reg export` the Profiles key to a timestamped backup first**,
    delete the Profiles key, recreate `Profiles\Outlook`, set `DefaultProfile = Outlook`.
- **Honesty:** after recreation, re-query the key; if the fresh profile key is absent, report **Error**
  with the path to the reg-export backup so it can be restored. Never delete anything beyond the Profiles
  subtree.
- **Tags:** `outlook`,`profile`,`registry`,`nuclear`.

### 6. outlook-addin-repair (96)

- **Function** `Repair-OutlookAddins`, **Category** User, **RequiresAdmin** `$false`, **Risk** `Modifies`.
- **Report (always):** enumerate add-ins under HKCU + HKLM `...\Outlook\Addins\*` (FriendlyName,
  LoadBehavior); list Resiliency `DisabledItems` / `CrashingAddinList` entries; flag any OnBase/Hyland
  add-in.
- **Actions:** `Read-ToolChoice -Choices @('None','ReEnable') -Default 'None' -Silent`.
  - `ReEnable`: clear `DisabledItems` and `CrashingAddinList` resiliency keys; for each add-in with
    `LoadBehavior = 0`, set `LoadBehavior = 3`; add each add-in to `DoNotDisableAddinList`; OnBase-specific
    re-enable as in v8.
- **Honesty:** HKLM add-in keys are **read-only** in the report (machine-wide; unelevated context cannot
  reliably write them) - only HKCU LoadBehavior/Resiliency/DoNotDisable values are modified. Report which
  add-ins were actually re-enabled (LoadBehavior was 0), not the full scanned list.
- **Tags:** `outlook`,`addin`,`onbase`,`loadbehavior`,`resiliency`.

## Registry entries

Six new entries appended to `src/registry/tools.psd1`, each
`@{ Id; LegacyId; Name; Category='User'; Function; Description; RequiresAdmin; SilentCapable=$true; Risk;
Tags }`. LegacyId = the primary v8 number (76, 79, 80, 81, 82, 96).

## Testing

- Existing template/registry AST suite auto-covers the 6 new tools (Id<->New-ToolRun match, approved
  verbs, `[switch]$Silent`, ASCII-only, UTF-8 BOM + trailing newline, registry completeness). Suite count
  71 -> 77.
- Nested helper functions (e.g. an AutoDiscover-cache-clear helper shared by `Reset-M365Auth` and
  `Repair-AutoDiscover`, if extracted) are NOT registry-scanned (top-level `FindAll(..., $false)`
  precedent: `Invoke-SpoolerFolderReset`, `Get-CredTargets`).
- Per-tool: PSScriptAnalyzer clean; `build.ps1` compiles; spot-run report arm under `-Silent` returns
  report-only with no state change.

## Parity impact

- Items 76, 79, 80, 81, 82, 96 -> **ported**; 78, 106 -> **consolidated**.
- Tool count 80 -> **86**. Checklist header -> "86 of ~111 items ported".
- After 6A, **batch 6 is complete**; only batch 7 remains.

## Out of scope

- Quick Fixes Q1-Q9 (batch 7) - several will compose these Outlook tools as macros; not built here.
- Office Click-to-Run repair (22, already shipped) - `outlook-profile-repair` is profile-only, not an
  Office binary repair; cross-reference 22 in its description.
