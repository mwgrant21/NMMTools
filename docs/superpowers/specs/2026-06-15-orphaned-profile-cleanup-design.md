# Orphaned Profile Cleanup - Design Spec

**Date:** 2026-06-15
**Scope:** New `User` tool `Remove-OrphanedProfile` that audits local user profiles, flags **orphaned**
ones (SID no longer resolves to an account, OR the profile folder is missing), and - behind a typed
`CONFIRM` - removes their registrations while **quarantining** (renaming, not deleting) any leftover folder.
Mirrors the existing `Repair-TemporaryProfile` house pattern. Adds one pure, unit-tested classification
helper to core.
**Status:** Approved (brainstormed with Matt 2026-06-15). Next: writing-plans -> implementation plan.

## Context

A real incident: a user was unjoined from Intune/MDM, lost O365 sync, and their profile became corrupt and
unlistable. After deleting it, the Advanced > User Profiles dialog showed the admin/IT account plus **seven
"unknown" profiles** that should not have existed - classic orphaned `Win32_UserProfile` / `ProfileList`
entries whose SID no longer maps to a real account ("Account Unknown").

The toolkit already covers the *diagnostic* side of this incident: `azure-ad-health` (id 21, dsregcmd join
state) and `intune-health` (id 29, MDM enrollment). The closest profile tool, `Repair-TemporaryProfile`
(id 95), handles only the `.bak` temp-profile case. **Nothing detects or cleans up orphaned/unknown
profiles** - that is the gap this tool fills.

This is a clean rewrite, not a port. A candidate script (`D:\user profile removed from intune.ps1`) was
reviewed and **FAILED** both `ps-code-reviewer` and `security-code-reviewer` (command injection via
`cmd /c`, `-like "*\$TargetUser"` mass-deletion, machine-wide `Stop-Process`, world-readable backups,
declared-but-unhonored `SupportsShouldProcess`, robocopy exit code ignored, silent no-op cache path). Those
blockers are avoided here by construction: no `cmd /c`, no operator wildcard input, no process killing, no
data backup to world paths, and the toolkit's own `Read-ToolChoice` confirm instead of `ShouldProcess`.

## Decisions made with Matt (do not re-litigate)

1. **Orphan definition = unknown SID OR missing folder** (no age-based removal).
2. **Removal quarantines the folder:** rename leftover folder to `<path>.orphan_<timestamp>`; remove only the
   registration. A *temporarily* unresolvable SID (DC unreachable) therefore loses only its dialog entry, not
   its data.
3. **Hard-protected, never a candidate:** `Special` profiles, `Loaded` (signed-in) profiles, and the account
   running the tool (its own SID). (System/well-known SIDs are `Special`.)
4. **One tool**, mirroring `Repair-TemporaryProfile`: read-only scan -> report -> `Read-ToolChoice` action ->
   typed `CONFIRM` -> `reg.exe export` backup (abort on failure) -> per-item, failure-isolated removal.
5. **Metadata mirrors `temp-profile-repair`:** `RequiresAdmin=$true`, `SilentCapable=$true`,
   `Risk='Disruptive'`, `Category='User'`. A `-Silent` run hits the toolkit's "disruptive needs `-Force`"
   refusal; even `-Silent -Force` only audits, because the `CONFIRM` auto-cancels with no interactive input.
   **The tool cannot delete a profile silently.**
6. **Name** `Remove-OrphanedProfile` / "Orphaned Profile Cleanup"; **LegacyId 105** (next free above the
   current max of 104).
7. **Removal granularity:** all flagged orphans in one typed `CONFIRM` (after showing the full list), not
   per-profile prompts.
8. **Classifier home:** a pure helper in core `07-repair-helpers.ps1` (the registry test forbids unregistered
   functions in `src/tools`, so the unit-testable helper must live in core).

## New behavior

### Component 1 - Pure classifier: add to `src/core/07-repair-helpers.ps1`

```powershell
function Get-NmmProfileVerdict {
    # Pure classification for one user profile, from already-determined facts. Never throws.
    # Returns: 'Protected' | 'Orphan-UnknownSid' | 'Orphan-MissingFolder' | 'Healthy'.
    # Protection wins over everything (a Special/Loaded/own-account profile is never an orphan, even if its
    # SID does not resolve). Then unknown-SID, then missing-folder, else healthy.
    param(
        [bool]$Special,
        [bool]$Loaded,
        [bool]$IsCurrentUser,
        [bool]$SidResolves,
        [bool]$FolderExists
    )
    if ($Special -or $Loaded -or $IsCurrentUser) { return 'Protected' }
    if (-not $SidResolves)  { return 'Orphan-UnknownSid' }
    if (-not $FolderExists) { return 'Orphan-MissingFolder' }
    return 'Healthy'
}
```

This file's header comment is updated to note it now also holds the orphaned-profile classifier (it is no
longer exclusively the repair-suite's helpers).

### Component 2 - The tool: new `src/tools/user/Remove-OrphanedProfile.ps1`

Integration code (CIM, SID translation, `reg`/`Rename`/`Remove-CimInstance`) lives here and is not unit-
tested, consistent with every other tool. Structure mirrors `Repair-TemporaryProfile`:

```
function Remove-OrphanedProfile {
    [CmdletBinding()]
    param([switch]$Silent)
    $run = $null
    try {
        $run = New-ToolRun -Id 'orphaned-profiles'
        # ... audit / report / gate / remove ...
    } catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

**Audit (read-only).** `$currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value`.
Enumerate `Get-CimInstance Win32_UserProfile`. For each profile compute the facts and a verdict:
- `Special`, `Loaded` from the CIM object; `IsCurrentUser = ($_.SID -eq $currentSid)`.
- `SidResolves`: `try { ([System.Security.Principal.SecurityIdentifier]$_.SID).Translate([System.Security.Principal.NTAccount]) | Out-Null; $true } catch { $false }` (an unmappable SID throws `IdentityNotMappedException` - exactly the "Account Unknown" case).
- `FolderExists`: `$_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath)`.
- `$verdict = Get-NmmProfileVerdict -Special $Special -Loaded $Loaded -IsCurrentUser $isCurrent -SidResolves $sidResolves -FolderExists $folderExists`.

Report each: orphans at `Warning` (` [orphan: unknown-SID] <path>  SID=<sid>  lastUse=<...>` /
`[orphan: missing-folder] ...`), Protected/Healthy at `Detail`. Collect the orphans (keep SID + LocalPath +
reason) into `$orphans`.

**No orphans** -> `Complete-ToolRun $run -Status Success -Summary 'No orphaned profiles found'`; return.

**Action gate.** Show the flagged list and count, then:
`$action = Read-ToolChoice -Prompt 'Orphaned profile action' -Choices @('None','RemoveOrphaned') -Default 'None' -Silent:$Silent`.
`None` -> `Complete-ToolRun $run -Status Warning -Summary ('{0} orphaned profile(s) found; no removal applied' -f $orphans.Count)`; return.

**RemoveOrphaned.**
1. Warn: removes registrations and quarantines (renames) their folders; affected users must be logged off.
2. Typed gate: `Read-ToolChoice -Prompt ('Type CONFIRM to remove these {0} orphaned profiles' -f $orphans.Count) -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent`. Not `CONFIRM` -> `Complete-ToolRun $run -Status Skipped -Summary 'RemoveOrphaned cancelled (no CONFIRM)'`; return.
3. **Backup `ProfileList` first** (same as the house pattern): `& reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' $backup /y *>$null` to `$env:TEMP\ProfileList_backup_<ts>.reg`. If `-not (Test-Path -LiteralPath $backup)` -> `Complete-ToolRun $run -Status Failed -Summary 'Aborted: could not export ProfileList backup (no changes made)'`; return.
4. **Per orphan (failure-isolated):**
   a. **Quarantine the folder.** If `FolderExists`: `Rename-Item -LiteralPath $localPath -NewName (<leaf>.orphan_<ts>) -ErrorAction Stop`. On failure (locked) -> report `Error`, **skip this profile's registration removal** (never half-clean), `continue`. (For `missing-folder` orphans there is nothing to rename.)
   b. **Remove the registration.** `Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid } | Remove-CimInstance -ErrorAction Stop`. Because the folder was already renamed away from `ProfileImagePath`, CIM has no live folder to delete - the quarantined data is untouched. On CIM failure, fall back to `& reg.exe delete ('HKLM\...\ProfileList\{0}' -f $sid) /f *>$null` and check `$LASTEXITCODE`. Report `Removed` (Success) / failure (Error, citing the backup path).
5. Tally removed vs skipped/failed; `Complete-ToolRun`:
   - all removed -> `Success` "Removed N orphaned profile(s); folders quarantined; backup: <path>"
   - some failed -> `Warning` with counts and backup path
   - none removed -> `Failed` with backup path retained.

### Component 3 - Registry entry: `src/registry/tools.psd1` (User section)

```
@{
    Id            = 'orphaned-profiles'
    LegacyId      = '105'
    Name          = 'Orphaned Profile Cleanup'
    Category      = 'User'
    Function      = 'Remove-OrphanedProfile'
    Description   = 'Audit local user profiles and flag orphaned ones (SID no longer resolves to an account, or the profile folder is missing); on typed confirm, remove the registration and quarantine the folder (rename, not delete) after a ProfileList registry backup. Affected users must be logged off.'
    RequiresAdmin = $true
    SilentCapable = $true
    Risk          = 'Disruptive'
    Tags          = @('profile','orphaned','unknown','sid','profilelist','cleanup')
}
```

### Unchanged

`Repair-TemporaryProfile` and every other tool, the registry schema, dispatch, the menu, and all
`-Tool`/`-Silent`/`-ListTools`/PDQ semantics. The new tool appears in the menu automatically (registry-driven)
and is gated by the existing risk-confirm path for `Disruptive` tools.

## Files

- Modify: `src/core/07-repair-helpers.ps1` - add `Get-NmmProfileVerdict`; broaden the header comment.
- Create: `src/tools/user/Remove-OrphanedProfile.ps1` - the tool function.
- Modify: `src/registry/tools.psd1` - add the `orphaned-profiles` entry in the User section.
- Create: `tests/profile-helpers.tests.ps1` - unit tests for `Get-NmmProfileVerdict`.

No dispatch/menu/CLI changes. The registry-consistency test (`tests/registry.tests.ps1`) automatically
covers the new entry (it requires the registered `Function` to exist in a tool file and every tool-file
function to be registered exactly once).

## Testing

### `tests/profile-helpers.tests.ps1` (new)
Dot-source `src/core/02-output.ps1` (helpers may call `Write-ToolOutput`; the classifier does not, but the
file is dot-sourced as a unit) and `src/core/07-repair-helpers.ps1`. Pure truth-table tests for
`Get-NmmProfileVerdict`:

1. **Protected wins:** `Special=$true` (any other args) -> `Protected`; `Loaded=$true` -> `Protected`;
   `IsCurrentUser=$true` -> `Protected`.
2. **Protection beats orphan:** `Special=$true, SidResolves=$false, FolderExists=$false` -> `Protected`
   (NOT an orphan).
3. **Unknown SID:** `Special=$false,Loaded=$false,IsCurrentUser=$false,SidResolves=$false` -> `Orphan-UnknownSid`
   (regardless of `FolderExists`).
4. **Missing folder:** not protected, `SidResolves=$true, FolderExists=$false` -> `Orphan-MissingFolder`.
5. **Healthy:** not protected, `SidResolves=$true, FolderExists=$true` -> `Healthy`.
6. **Never throws** for any boolean combination.

### Registry & build
- `tests/registry.tests.ps1` (unchanged) now asserts `Remove-OrphanedProfile` is defined in a tool file and
  registered once, the `orphaned-profiles` Id/LegacyId are unique kebab/numeric, Risk is valid, etc.
- `build.ps1` must compile (parse gate) and PSScriptAnalyzer stay **error**-clean. `Remove-OrphanedProfile`
  and `Get-NmmProfileVerdict` use approved verbs (`Remove`/`Get`). The Warning-severity
  `PSUseShouldProcessForStateChangingFunctions` is tolerated (the gate fails only on Error; existing
  `Remove-AdobeCC`/`Remove-WindowsOld`/`Repair-TemporaryProfile` already rely on `Read-ToolChoice` confirms
  rather than `ShouldProcess`).
- Full suite recomputed (currently 97).

**Not unit-tested (by design, matching every other tool):** the live CIM enumeration, SID translation,
`reg.exe` backup, `Rename-Item` quarantine, and `Remove-CimInstance`. These are integration behaviors
verified by manual smoke on a machine with a seeded orphan, not by Pester. The risky logic that *can* be
isolated - the orphan/protect classification - is the pure helper, which is fully unit-tested.

## Manual smoke (in the plan's verification step)
On a test machine: create a throwaway local profile, delete the account (leaving an orphaned SID), run the
tool, confirm it lists the orphan as `unknown-SID`, run `RemoveOrphaned`/`CONFIRM`, and verify the dialog
entry is gone, the folder is renamed `.orphan_<ts>`, and a `ProfileList` backup `.reg` exists. Verify a
`-Silent` run refuses (disruptive) and `-Silent -Force` only audits.

## Out of scope

- Age/staleness-based removal (decided against - age != orphaned).
- Hard-deleting profile folders (decided: quarantine/rename).
- Touching `Special`/`Loaded`/own-account profiles under any flag.
- Rebuilding MDM/Entra diagnostics (`azure-ad-health`/`intune-health` already cover them).
- A separate read-only audit tool or fleet/PDQ orphan reporting (possible later; this tool's `-Silent -Force`
  already yields an audit-only pass).
- Any change to dispatch, the registry schema, the menu, or other tools.
