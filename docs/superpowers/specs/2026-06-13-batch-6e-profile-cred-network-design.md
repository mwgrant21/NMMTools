# Batch 6E: Profile / Credentials / Network Tools - Design Spec

**Date:** 2026-06-13
**Scope:** Port v8 tools 58, 60, 66, 95 (+ fold retired tool 26) into v9 (sub-batch 6E of batch 6).
**Status:** Approved (brainstormed with Matt 2026-06-13). Next: writing-plans -> 6E implementation plan.

## Batch 6 decomposition (context)

Batch 6 ("Common User Issues") is decomposed into 5 themed sub-batches (decided WITH Matt). Done so far:
6C Shell/UI + 6B Teams (both merged 2026-06-13, 73 tools). This spec is **6E**. Remaining after 6E:
6A Outlook/M365, 6D Devices/Perf/Print.

## Goal

Port the four v8 tools into v9 as four report-then-action tools, folding retired tool 26 (Office 365
credential clear) into the credential tool. v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY
reference (functions: `Repair-NetworkDrives` L7479, `Clear-SavedCredentials` L8132, `Clear-ProfileCache`
L8935, `Repair-TemporaryProfile` L11175, retired `Clear-CredentialManager` L1345).

## Usage model (unchanged)

Interactive technician at the keyboard; toolkit elevates at launch. Optimize the interactive experience;
`-Silent` only needs to be SAFE (report-only via None default; admin tool refuses non-elevated silent).
Per-tool admin: only temp-profile-repair needs admin (HKLM ProfileList).

## Decisions made with Matt (do not re-litigate)

1. **Four separate tools; no merges among them.** Only retired tool 26 folds into the credential tool.
2. **Retired tool 26 -> `credential-manager` as a `ClearOffice365` action** (deletes cmdkey entries matching
   `MicrosoftOffice*`). Mark 26 consolidated -> 60 in parity (already noted there).
3. **`profile-cache` never deletes Downloads.** v8 reports the Downloads folder size but never offers to
   clean it. v9 keeps Downloads in the read-only size report only - it is user data, not cache.
4. **`temp-profile-repair`: auto-repair, gated, with a `reg export` backup FIRST** (hardening over v8,
   which had no backup). Typed CONFIRM + "affected user must be logged off" warning, then export the
   ProfileList key to `%TEMP%\ProfileList_backup_<ts>.reg` before any surgery. Admin, Disruptive.
5. **`network-drives` does not duplicate credential clearing.** Its v8 "clear cached credentials" option is
   dropped; the description cross-references `credential-manager` (60) for clearing stale share creds.
6. **`credential-manager` drops v8's free-text "remove specific" action** (the GUI launch covers one-offs);
   keeps the typed `CLEAR` gate on ClearAll.
7. **Category 'User'** (batch 6), consistent with 6C/6B. Tool count 73 -> 77.

## Architecture

```
src\tools\user\Repair-NetworkDrives.ps1     -> network-drives        (58)
src\tools\user\Clear-SavedCredentials.ps1   -> credential-manager    (60 + 26)
src\tools\user\Clear-ProfileCache.ps1       -> profile-cache         (66)
src\tools\user\Repair-TemporaryProfile.ps1  -> temp-profile-repair   (95)
```

No new core helper - each tool is self-contained (uses the existing `Write-ToolOutput`/`Read-ToolChoice`/
`New-ToolRun`/`Complete-ToolRun` interface). `RemapDrive` and `RemoveSpecific`-style inputs use `Read-Host`
ONLY where reached after an interactive action choice (never under -Silent), consistent with the BitLocker
save-path precedent.

### Tool 1: `network-drives` (58) - Modifies, Admin=$false

`Repair-NetworkDrives` / `New-ToolRun -Id 'network-drives'`.

- **Report (always):** mapped network drives via `Get-PSDrive -PSProvider FileSystem | Where-Object
  { $_.DisplayRoot -like '\\*' }` with a connected/disconnected flag (`Test-Path $_.Root`); plus a `net use`
  summary line. Empty-collection -> "no mapped network drives found".
- **Actions** (`@('None','ReconnectAll','RemapDrive')`):
  - `ReconnectAll` - parse `net use` for Disconnected/Unavailable drives and reconnect each
    (`net use <letter>: /persistent:yes` or `net use <letter>:` with the stored path); report how many
    reconnected.
  - `RemapDrive` - interactive (Read-Host): prompt for a drive letter and a UNC path; `net use <letter>:
    /delete` (ignore errors) then `net use <letter>: <unc> /persistent:yes`; report success/failure.
- Risk Modifies; RequiresAdmin $false (mapped drives are per-user).

### Tool 2: `credential-manager` (60 + 26) - Modifies, Admin=$false

`Clear-SavedCredentials` / `New-ToolRun -Id 'credential-manager'`.

- **Report (always):** parse `cmdkey /list` and list each credential's Target (with Type/User detail);
  report the total count.
- **Actions** (`@('None','ClearNetwork','ClearWeb','ClearOffice365','ClearAll','OpenCredManager')`):
  - `ClearNetwork` - delete cmdkey targets matching network/share patterns (`*\\*`, `Domain:*`, `*smb*`,
    `*cifs*`); report count.
  - `ClearWeb` - delete cmdkey targets matching web patterns (`*http*`, `*.com`, `*.net`, `*.org`,
    `WindowsLive:*`); report count.
  - `ClearOffice365` - (folded retired tool 26) delete cmdkey targets matching `MicrosoftOffice`;
    report count. Stops the Office "enter your credentials" loop.
  - `ClearAll` - DESTRUCTIVE. Typed CONFIRM (`@('CLEAR','Cancel') -Default 'Cancel'`); warns that ALL saved
    credentials (shares, RDP, web, services) will be removed and must be re-entered. Then delete every
    `cmdkey /list` Target; report count.
  - `OpenCredManager` - interactive GUI: `Start-Process control.exe -ArgumentList '/name
    Microsoft.CredentialManager'`.
- Risk Modifies (ClearAll typed-gated); RequiresAdmin $false (per-user vault). Each clear re-queries
  `cmdkey /list` at action time so the targets are current.

### Tool 3: `profile-cache` (66) - Modifies, Admin=$false

`Clear-ProfileCache` / `New-ToolRun -Id 'profile-cache'`.

- **Report (always, read-only):** size of each cache folder under `%USERPROFILE%`:
  Teams (`...\AppData\Local\Microsoft\Teams`), OneDrive (`...\AppData\Local\Microsoft\OneDrive`),
  Office (`...\AppData\Local\Microsoft\Office\16.0\OfficeFileCache`),
  Chrome (`...\AppData\Local\Google\Chrome\User Data\Default\Cache`),
  Edge (`...\AppData\Local\Microsoft\Edge\User Data\Default\Cache`), Temp (`$env:TEMP`),
  and Downloads (`...\Downloads`) - **Downloads is REPORT-ONLY (never cleaned)**. Report each size + total;
  highlight folders over ~500 MB.
- **Actions** (`@('None','CleanCaches')`):
  - `CleanCaches` - confirm (Yes/No, Default No). Clear the CONTENTS of the six cache folders ONLY
    (Teams, OneDrive, Office, Chrome, Edge, Temp) - never Downloads. Report MB reclaimed.
- Risk Modifies; RequiresAdmin $false (per-user profile). Description cross-references `browser-clear` (50),
  `temp-cleanup` (11), and `teams-cache` (24) - profile-cache's value is the one-screen bloat overview.

### Tool 4: `temp-profile-repair` (95) - Disruptive, Admin=$true

`Repair-TemporaryProfile` / `New-ToolRun -Id 'temp-profile-repair'`.

- **Report (always, read-only):** scan `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList`;
  for each `<SID>.bak` subkey determine whether the real `<SID>` key also exists (the classic temp-profile
  pattern) vs an orphaned `.bak` with no real SID. Report each finding (SID, ProfileImagePath, pattern).
  If no `.bak` entries -> Complete Success "no temporary profile issues detected" and return.
- **Action** (`@('None','RepairProfile')`):
  - `RepairProfile` - typed CONFIRM (`@('CONFIRM','Cancel') -Default 'Cancel'`) preceded by a warning that
    the AFFECTED USER MUST BE LOGGED OFF and that this edits HKLM ProfileList. On CONFIRM:
    1. `reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
       "%TEMP%\ProfileList_backup_<ts>.reg" /y` - capture the path; if export fails, ABORT (do not edit).
    2. For each temp-profile-pattern entry (real SID + `.bak`): remove the corrupt real `<SID>` key;
       recreate `<SID>` from the `.bak` key's values (preserving property types); remove the `.bak` key.
    3. Report the backup path and "have the user log in again to get their real profile".
- Risk Disruptive (HKLM registry surgery that can break login; typed CONFIRM; dispatcher refuses
  silent-no-force); RequiresAdmin $true. Report surfaces the backup path so a tech can `reg import` it if
  needed.

## Registry entries (appended to tools.psd1)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable | Tags |
|---|---|---|---|---|---|---|---|---|
| network-drives | 58 | Mapped Network Drive Repair | Repair-NetworkDrives | User | $false | Modifies | $true | network,drive,mapped,unc |
| credential-manager | 60 | Credential Manager Cleanup | Clear-SavedCredentials | User | $false | Modifies | $true | credential,cmdkey,password,office365 |
| profile-cache | 66 | Profile Size and Cache Cleanup | Clear-ProfileCache | User | $false | Modifies | $true | profile,cache,cleanup,roaming |
| temp-profile-repair | 95 | Temporary Profile Repair | Repair-TemporaryProfile | User | $true | Disruptive | $true | profile,temporary,profilelist,registry |

LegacyIds 58/60/66/95 are free and numeric. All `Category = 'User'`, `SilentCapable = $true` (under
`-Silent` the action menu returns None -> report only; temp-profile-repair additionally refuses non-elevated
silent at the dispatcher, and refuses silent-no-force as a Disruptive tool).

## Testing

- Build green + full suite green: ASCII-only encoding gate, template-compliance gates (approved verbs
  Repair/Clear; `[switch]$Silent`; run-bracketing; `New-ToolRun -Id` <-> registry Id AST test),
  registry-mapping for the 4 new tools, unique Id/LegacyId.
- No new unit tests (interactive I/O wrappers around cmdkey / net use / registry; existing
  template/registry/encoding gates cover them, consistent with prior batches).
- **Smoke (non-elevated dev session):**
  - `network-drives -Silent`, `credential-manager -Silent`, `profile-cache -Silent` -> report only (None
    default), exit 0; quote the summary. (credential-manager lists creds read-only; profile-cache reports
    sizes read-only.)
  - `temp-profile-repair -Silent` -> RequiresAdmin -> dispatcher refuses non-elevated (exit 1); quote.
  - NEVER run the destructive actions (RemapDrive, any Clear*, CleanCaches, RepairProfile) in the dev
    session - they delete credentials/cache and edit HKLM. Verify by reading + the silent report.

## Conventions carried from prior batches

Faithful BEHAVIOR port (not code); `Write-ToolOutput`/`Read-ToolChoice` only (no `Write-Host`; `Read-Host`
only for the interactive RemapDrive input, reached only after an action choice); tight tech-facing
summaries; Info headline + Detail rows; empty-collection early-return Warning/Success; descriptions/tags
match actual v8 behavior (profile-cache cross-references the dedicated cache tools; credential-manager notes
the Office 365 loop fix); ASCII-only source (UTF-8 BOM + trailing newline); PS 5.1 (no ternary/`??`/`&&`;
never assign `$input`/`$matches`/`$profile` - reading `$matches[n]` after `-match` is allowed). Destructive
removals scoped to explicit per-user paths / cmdkey targets (never a drive root); HKLM ProfileList surgery
double-gated (Disruptive dispatcher-refusal + typed CONFIRM) and preceded by a registry export backup.
Each credential clear re-queries `cmdkey /list` at action time.

## Out of scope

Retired tool 26 is folded in (not a separate tool). profile-cache deliberately does NOT clean Downloads
(user data). network-drives does not duplicate credential clearing (use credential-manager / tool 60).
The browser/temp/teams cache overlaps are cross-referenced, not re-implemented. Sub-batches 6A (Outlook) and
6D (Devices/Print) are separate specs. No roaming-profile / FSLogix container handling (out of scope for a
local interactive tool).
