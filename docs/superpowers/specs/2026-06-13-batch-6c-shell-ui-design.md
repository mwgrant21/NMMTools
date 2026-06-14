# Batch 6C: Shell & UI Tools - Design Spec

**Date:** 2026-06-13
**Scope:** Port v8 "Common User Issues" shell/UI tools 54, 55, 57, 59 into v9 (sub-batch 6C of batch 6).
**Status:** Approved (brainstormed with Matt 2026-06-13). Next: writing-plans -> 6C implementation plan.

## Batch 6 decomposition (context)

Batch 6 ("Common User Issues", ~26 v8 tools: 52-61, 66, 76-85, 95-98, 106) is the largest remaining
batch. Decided WITH Matt to DECOMPOSE into 5 themed sub-batches, each its own spec -> plan -> execute cycle:
- **6A** Outlook & M365 (76, 78, 79, 80, 81, 82, 96, 106)
- **6B** Teams (83, 84, 85, 97)
- **6C** Shell & UI (54, 55, 57, 59) - THIS SPEC
- **6D** Devices, Perf & Print (52, 53, 56, 77, 98)
- **6E** Profile, Credentials & Network (58, 60, 66, 95)

6C is the starting sub-batch. The remaining sub-batches get their own brainstorm/spec/plan when reached.

## Goal

Port the four v8 shell/UI repair tools into v9, converting each v8 numbered sub-menu into the standard
v9 report-then-action shape. v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference
(functions: `Reset-WindowsSearch` L6517, `Repair-StartMenuTaskbar` L6733, `Reset-WindowsExplorer` L7254,
`Reset-FileAssociations` L7933).

## Usage model (unchanged)

Interactive technician at the keyboard; toolkit elevates at launch. Optimize the interactive experience;
`-Silent` only needs to be SAFE (report-only via the None default; admin tool refuses non-elevated silent).
These are per-user shell repairs except search (service + ProgramData), so RequiresAdmin is per-tool.

## Decisions made with Matt (do not re-litigate)

1. **Decompose batch 6 into 5 sub-batches; start with 6C** (4 tools after the tool-61 consolidation below).
2. **Tool 61 (Display & Monitor Config) CONSOLIDATED, not ported.** Its report + DisplaySwitch are already
   covered by `docking-displays` (44, batch 4); its "fix display driver" by `display-adapter-reset`
   (73, batch 3). Mark 61 consolidated -> 44 + 73 in the parity checklist. 6C is therefore 54, 55, 57, 59.
3. **v8 sub-menu -> v9 report-then-action.** Each tool runs a read-only report first (the v8 "show
   current/status/check" option folds into this), then `Read-ToolChoice -Choices @('None', <actions>)
   -Default 'None' -Silent:$Silent`. Under `-Silent` -> None -> report only.
4. **Keep GUI-launch actions** (open Indexing Options, Default Apps settings) as interactive choices;
   offer a programmatic action alongside where one exists. GUI launches are no-ops under `-Silent`
   (only reached via an interactive action choice).
5. **New Category `'User'`** for all of batch 6 (the v8 "Common User Issues" section). After 6C the menu
   has 6 categories alphabetical: A=Browser B=Cloud C=Diagnostics D=Laptop E=Repair F=User.
6. **Honest port of `default-apps` (59).** Modern Win10/11 hash-protect the per-user association
   "UserChoice", so v8's `assoc`/`ftype` reset does not reliably change a user's defaults. v9 ports it as
   report-current-associations + open the Default Apps settings (the reliable path), and the Description
   says so rather than implying a working programmatic reset.

## Architecture

```
src\tools\user\Reset-WindowsSearch.ps1       -> windows-search-rebuild (54)
src\tools\user\Repair-StartMenuTaskbar.ps1   -> start-menu-taskbar     (55)
src\tools\user\Reset-WindowsExplorer.ps1     -> windows-explorer-reset (57)
src\tools\user\Set-DefaultApps.ps1           -> default-apps           (59)
```

New Category `'User'`. Tool count **66 -> 70** (4 user + the existing 66). No new core helper -
each tool is self-contained and uses the existing `Write-ToolOutput`/`Read-ToolChoice`/`New-ToolRun`/
`Complete-ToolRun` interface. A small inline `Restart-Explorer` helper pattern (Stop-Process explorer ->
Start-Process explorer) recurs in tools 55 and 57; define it inline in each (nested) rather than a shared
core helper - it is two lines and the two tools differ in surrounding context. (If a third consumer
appears in 6D/6E, promote it to a core helper then.)

### Tool 1: `windows-search-rebuild` (54) - Modifies, Admin=$true

`Reset-WindowsSearch` / `New-ToolRun -Id 'windows-search-rebuild'`.

- **Report (always):** WSearch service Status + StartType (Get-Service WSearch); note if the service is
  absent. (Folds v8 option 4 "check status".)
- **Actions** (`Read-ToolChoice -Choices @('None','RestartService','RebuildIndex','OpenIndexingOptions')
  -Default 'None'`):
  - `RestartService` - Stop-Service WSearch -Force; wait; Start-Service; report new status.
  - `RebuildIndex` - DESTRUCTIVE (clears the index; 1-2 h background rebuild). Typed CONFIRM
    (`Read-ToolChoice -Choices @('CONFIRM','Cancel') -Default 'Cancel'`). Stop WSearch ->
    remove `%ProgramData%\Microsoft\Search\Data\*` (scoped; `-ErrorAction SilentlyContinue`) ->
    Start WSearch. Report that the rebuild runs in the background.
  - `OpenIndexingOptions` - interactive GUI: `Start-Process control.exe -ArgumentList 'srchadmin.dll'`;
    tell the tech to use Advanced -> Rebuild. (No-op meaning under -Silent; only reached interactively.)
- Risk Modifies (the only destructive action, RebuildIndex, is typed-gated). RequiresAdmin $true
  (service control + ProgramData write) -> dispatcher refuses non-elevated `-Silent`.

### Tool 2: `start-menu-taskbar` (55) - Modifies, Admin=$false

`Repair-StartMenuTaskbar` / `New-ToolRun -Id 'start-menu-taskbar'`.

- **Report:** explorer.exe running? (Get-Process explorer); OS caption/build (Win10 vs Win11 - layout
  paths differ).
- **Actions** (`@('None','RestartExplorer','ResetStartLayout','ReRegisterStartMenu')`):
  - `RestartExplorer` - Stop-Process explorer -Force; Start-Process explorer; brief wait.
  - `ResetStartLayout` - confirm (Yes/No, Default No). Back up the layout folder to
    `%TEMP%\StartMenu_Backup_<ts>` (best-effort); stop explorer; clear the layout cache
    (`%LOCALAPPDATA%\Microsoft\Windows\Caches\*` and `...\Shell\LayoutModification.xml`); restart explorer.
  - `ReRegisterStartMenu` - confirm (Yes/No, Default No; note it can take a minute). Re-register the
    StartMenuExperienceHost appx for the current user
    (`Get-AppxPackage Microsoft.Windows.StartMenuExperienceHost | ForEach-Object {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}`),
    `-ErrorAction SilentlyContinue`; report success/failure count.
- Risk Modifies; RequiresAdmin $false (HKCU/user AppData + the user's own explorer process).

### Tool 3: `windows-explorer-reset` (57) - Modifies, Admin=$false

`Reset-WindowsExplorer` / `New-ToolRun -Id 'windows-explorer-reset'`.

- **Report:** explorer.exe running? (Get-Process explorer).
- **Actions** (`@('None','RestartExplorer','ClearExplorerCache','RebuildIconCache')`):
  - `RestartExplorer` - as above.
  - `ClearExplorerCache` - confirm (Yes/No, Default No). Stop explorer; remove
    `%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db`,
    `%APPDATA%\Microsoft\Windows\Recent\*` (incl. AutomaticDestinations + CustomDestinations jump lists);
    restart explorer.
  - `RebuildIconCache` - confirm (Yes/No, Default No). Stop explorer; remove
    `%LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache_*.db` and `%LOCALAPPDATA%\IconCache.db`;
    restart explorer.
- Risk Modifies; RequiresAdmin $false.

### Tool 4: `default-apps` (59) - Modifies, Admin=$false

`Set-DefaultApps` / `New-ToolRun -Id 'default-apps'`.

- **Report:** current associations for common extensions
  (`.txt .pdf .jpg .png .docx .xlsx .html .zip .mp4`) via `cmd /c assoc <ext>` (read-only; wrap each in
  try/catch; show "(none)" when unset). (Folds v8 option 1.)
- **Actions** (`@('None','OpenDefaultApps')`):
  - `OpenDefaultApps` - interactive GUI: `Start-Process 'ms-settings:defaultapps'`; tell the tech that
    per-type defaults must be set here (Windows hash-protects the per-user choice).
- Risk Modifies (label honest: it mostly reports + opens settings); RequiresAdmin $false.
- Verb note: `Set-DefaultApps` uses approved verb `Set`; the function name reflects the user intent
  ("set default apps") even though the heavy lifting is the GUI. (Alternative `Show-`/`Open-` are not
  approved verbs; `Set` is the closest approved verb that fits the tool's purpose.)

## Registry entries (appended to tools.psd1)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable | Tags |
|---|---|---|---|---|---|---|---|---|
| windows-search-rebuild | 54 | Windows Search Rebuild | Reset-WindowsSearch | User | $true | Modifies | $true | search,wsearch,index,cortana |
| start-menu-taskbar | 55 | Start Menu and Taskbar Repair | Repair-StartMenuTaskbar | User | $false | Modifies | $true | startmenu,taskbar,explorer,shell |
| windows-explorer-reset | 57 | Windows Explorer Reset | Reset-WindowsExplorer | User | $false | Modifies | $true | explorer,shell,thumbnail,iconcache |
| default-apps | 59 | Default Apps and File Types | Set-DefaultApps | User | $false | Modifies | $true | defaultapps,fileassociation,fta |

LegacyIds 54/55/57/59 are free and numeric. All `Category = 'User'`. All `SilentCapable = $true`
(under `-Silent` the action menu returns None -> report only; the admin tool additionally refuses
non-elevated silent at the dispatcher).

## Testing

- Build green + full suite green: ASCII-only encoding gate, template-compliance gates (approved verbs
  Reset/Repair/Set; `[switch]$Silent`; run-bracketing; `New-ToolRun -Id` <-> registry Id AST test),
  registry-mapping for the 4 new tools, unique Id/LegacyId.
- No new unit tests required (these tools are interactive I/O wrappers around OS commands; the existing
  template/registry/encoding gates cover them, consistent with batches 1-4). Add a focused test only if a
  tool grows a pure helper worth locking.
- **Smoke (non-elevated dev session):**
  - `start-menu-taskbar -Silent`, `windows-explorer-reset -Silent`, `default-apps -Silent` -> report only
    (None default), exit 0; quote the summary. (No explorer restart, no cache deletion, no GUI launch.)
  - `windows-search-rebuild -Silent` -> RequiresAdmin -> dispatcher refuses non-elevated (exit 1); quote.
  - NEVER run the destructive paths (RebuildIndex, ClearExplorerCache, RebuildIconCache, ResetStartLayout)
    in the dev session; verify them by reading + the silent report.

## Conventions carried from prior batches

Faithful BEHAVIOR port (not code); `Write-ToolOutput`/`Read-ToolChoice` only (no `Write-Host`; no
`Read-Host` - none of these 4 tools need free-text input); tight tech-facing summaries; Info headline +
Detail rows; empty-collection / absent-service early-return Warning; descriptions/tags match actual v8
behavior (default-apps description is honest about the GUI requirement); ASCII-only source (UTF-8 BOM +
trailing newline); PS 5.1 (no ternary/`??`/`&&`; never assign `$input`/`$matches`/`$profile`). Destructive
sub-actions double-gated (typed CONFIRM where index-clearing; Yes/No Default-No for cache/layout resets).
Scoped removals only (explicit user/ProgramData paths; never a drive root).

## Out of scope (other sub-batches / not porting)

Tool 61 (consolidated -> 44 + 73). Sub-batches 6A/6B/6D/6E (separate specs). No new browsers, no GPO-based
default-app XML import (system-wide, out of scope for a per-user interactive tool).
