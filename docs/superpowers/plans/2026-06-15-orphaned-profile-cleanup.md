# Orphaned Profile Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `User` tool `Remove-OrphanedProfile` that audits local user profiles, flags orphaned ones (SID no longer resolves to an account, or the profile folder is missing), and on a typed `CONFIRM` removes their registrations while quarantining (renaming) any leftover folder after a `ProfileList` registry backup.

**Architecture:** A pure, unit-tested classifier (`Get-NmmProfileVerdict`) lands in core `07-repair-helpers.ps1`; the tool function in `src/tools/user/Remove-OrphanedProfile.ps1` does the live CIM/SID/registry/rename work and calls the classifier; a registry entry in `tools.psd1` wires it into the menu. Mirrors the existing `Repair-TemporaryProfile` house pattern (scan -> report -> `Read-ToolChoice` action -> typed `CONFIRM` -> `reg.exe export` backup -> per-item failure-isolated work).

**Tech Stack:** PowerShell 5.1, Pester 5, PSScriptAnalyzer (via `build.ps1`). Tests dot-source individual `src` files, so they run without building.

**Spec:** `docs/superpowers/specs/2026-06-15-orphaned-profile-cleanup-design.md`

**HARD CONSTRAINT - ASCII only:** `tests/encoding.tests.ps1` fails the suite if any `src/**/*.ps1` contains a character > 127 (BOM excepted). Every string literal below is plain ASCII. Use `->` (hyphen + greater-than), never an em-dash or arrow glyph. Do not paste any Unicode.

---

## File Structure

- **Modify** `src/core/07-repair-helpers.ps1` — append the pure `Get-NmmProfileVerdict` classifier; broaden the header comment (the file is no longer exclusively repair-suite helpers).
- **Create** `tests/profile-helpers.tests.ps1` — unit tests (truth table) for `Get-NmmProfileVerdict`.
- **Create** `src/tools/user/Remove-OrphanedProfile.ps1` — the tool function (integration code; not unit-tested, like every other tool).
- **Modify** `src/registry/tools.psd1` — add the `orphaned-profiles` entry in the User section.

Conventions to follow (from the existing codebase): tool files contain exactly one registered function named after the file (the registry test enforces this — never add a second function to a tool file). Tools use `New-ToolRun`/`Complete-ToolRun`, `Write-ToolOutput`, and `Read-ToolChoice` (never `Write-Host`/`Read-Host`). Core helper files may hold multiple unregistered functions.

---

## Task 1: `Get-NmmProfileVerdict` pure classifier

**Files:**
- Modify: `src/core/07-repair-helpers.ps1` (append the function; update the header comment)
- Create: `tests/profile-helpers.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/profile-helpers.tests.ps1` with:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\07-repair-helpers.ps1')
}

Describe 'Get-NmmProfileVerdict' {
    It 'protects Special profiles regardless of other facts' {
        Get-NmmProfileVerdict -Special $true -Loaded $false -IsCurrentUser $false -SidResolves $false -FolderExists $false | Should -Be 'Protected'
    }
    It 'protects Loaded profiles' {
        Get-NmmProfileVerdict -Special $false -Loaded $true -IsCurrentUser $false -SidResolves $false -FolderExists $false | Should -Be 'Protected'
    }
    It 'protects the current user profile even when its SID does not resolve' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $true -SidResolves $false -FolderExists $true | Should -Be 'Protected'
    }
    It 'flags an unresolvable SID as Orphan-UnknownSid' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $false -SidResolves $false -FolderExists $true | Should -Be 'Orphan-UnknownSid'
    }
    It 'flags a missing folder as Orphan-MissingFolder when the SID resolves' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $false -SidResolves $true -FolderExists $false | Should -Be 'Orphan-MissingFolder'
    }
    It 'treats a resolving SID with an existing folder as Healthy' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $false -SidResolves $true -FolderExists $true | Should -Be 'Healthy'
    }
    It 'never throws for any boolean combination' {
        foreach ($a in @($true,$false)) {
          foreach ($b in @($true,$false)) {
            foreach ($c in @($true,$false)) {
              foreach ($d in @($true,$false)) {
                foreach ($e in @($true,$false)) {
                  { Get-NmmProfileVerdict -Special $a -Loaded $b -IsCurrentUser $c -SidResolves $d -FolderExists $e } | Should -Not -Throw
                }
              }
            }
          }
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\profile-helpers.tests.ps1 -Output Detailed`
Expected: FAIL — `The term 'Get-NmmProfileVerdict' is not recognized`.

- [ ] **Step 3: Write the minimal implementation**

In `src/core/07-repair-helpers.ps1`, replace the existing 3-line header comment:

```
# Shared repair helpers for Invoke-SystemRepairSuite.
# These are plain functions, not tool functions - no registry entries needed.
# Called in sequence by the suite; each returns @{ Status; Summary } (Temp adds MbFreed).
```

with:

```
# Shared core helpers (plain functions, not tool functions - no registry entries needed).
# - Invoke-* : repair-suite steps for Invoke-SystemRepairSuite; each returns @{ Status; Summary } (Temp adds MbFreed).
# - Get-NmmProfileVerdict : pure orphaned-profile classifier used by Remove-OrphanedProfile.
```

Then append this function at the END of `src/core/07-repair-helpers.ps1`:

```powershell

function Get-NmmProfileVerdict {
    # Pure classification for one user profile, from already-determined facts. Never throws.
    # Returns: 'Protected' | 'Orphan-UnknownSid' | 'Orphan-MissingFolder' | 'Healthy'.
    # Protection wins over everything (a Special/Loaded/own-account profile is never an orphan,
    # even if its SID does not resolve). Then unknown-SID, then missing-folder, else healthy.
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

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\profile-helpers.tests.ps1 -Output Detailed`
Expected: PASS — all 7 cases green.

- [ ] **Step 5: Commit**

```bash
git add src/core/07-repair-helpers.ps1 tests/profile-helpers.tests.ps1
git commit -m "feat: add Get-NmmProfileVerdict orphaned-profile classifier

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `Remove-OrphanedProfile` tool + registry entry

**Files:**
- Modify: `src/registry/tools.psd1` (add entry after the `temp-profile-repair` entry)
- Create: `src/tools/user/Remove-OrphanedProfile.ps1`
- Test harness: `tests/registry.tests.ps1` (existing — used as the red/green gate; do not edit it)

This task uses the existing registry-consistency test as its failing test: adding the registry entry without the function file makes `tests/registry.tests.ps1` fail; creating the function file makes it pass.

- [ ] **Step 1: Add the registry entry**

In `src/registry/tools.psd1`, find the `temp-profile-repair` entry (its closing `}` is around line 926) and insert this block immediately after it:

```powershell
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

- [ ] **Step 2: Run the registry test to verify it fails**

Run: `Invoke-Pester .\tests\registry.tests.ps1 -Output Detailed`
Expected: FAIL — `every registry Function exists in a tools file` fails because `Remove-OrphanedProfile` is not defined in any `src/tools` file yet. (The `unique Ids`/`unique LegacyIds` cases must still pass — if `LegacyId 105` collides, pick the next free integer and update both the entry and this plan.)

- [ ] **Step 3: Create the tool function**

Create `src/tools/user/Remove-OrphanedProfile.ps1` with this exact content (ASCII only):

```powershell
function Remove-OrphanedProfile {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'orphaned-profiles'

        $plReg = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $ts    = Get-Date -Format 'yyyyMMdd_HHmmss'

        # Account running the tool - never a removal candidate.
        $currentSid = ''
        try { $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $currentSid = '' }

        # --- Audit (read-only) ---
        $profiles = @()
        try {
            $profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop)
        } catch {
            Complete-ToolRun $run -Status Failed -Summary ('Could not enumerate user profiles: {0}' -f $_.Exception.Message)
            return
        }

        $orphans = @()
        foreach ($p in $profiles) {
            $sid       = [string]$p.SID
            $localPath = [string]$p.LocalPath
            $special   = [bool]$p.Special
            $loaded    = [bool]$p.Loaded
            $isCurrent = ($sid -eq $currentSid)

            $sidResolves = $false
            try {
                $null = ([System.Security.Principal.SecurityIdentifier]$sid).Translate([System.Security.Principal.NTAccount])
                $sidResolves = $true
            } catch {
                $sidResolves = $false
            }

            $folderExists = [bool]($localPath -and (Test-Path -LiteralPath $localPath))

            $verdict = Get-NmmProfileVerdict -Special $special -Loaded $loaded -IsCurrentUser $isCurrent -SidResolves $sidResolves -FolderExists $folderExists

            switch ($verdict) {
                'Orphan-UnknownSid' {
                    Write-ToolOutput ('  [orphan: unknown-SID]    {0}  SID={1}' -f $localPath, $sid) -Level Warning
                    $orphans += [PSCustomObject]@{ Sid = $sid; LocalPath = $localPath; Reason = 'unknown-SID'; FolderExists = $folderExists }
                }
                'Orphan-MissingFolder' {
                    Write-ToolOutput ('  [orphan: missing-folder] {0}  SID={1}' -f $localPath, $sid) -Level Warning
                    $orphans += [PSCustomObject]@{ Sid = $sid; LocalPath = $localPath; Reason = 'missing-folder'; FolderExists = $folderExists }
                }
                'Protected' {
                    Write-ToolOutput ('  [protected] {0}' -f $localPath) -Level Detail
                }
                default {
                    Write-ToolOutput ('  [healthy]   {0}' -f $localPath) -Level Detail
                }
            }
        }

        if ($orphans.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary 'No orphaned profiles found'
            return
        }

        Write-ToolOutput ('{0} orphaned profile(s) found.' -f $orphans.Count) -Level Warning

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Orphaned profile action' -Choices @('None','RemoveOrphaned') -Default 'None' -Silent:$Silent
        if ($action -ne 'RemoveOrphaned') {
            Complete-ToolRun $run -Status Warning -Summary ('{0} orphaned profile(s) found; no removal applied' -f $orphans.Count)
            return
        }

        Write-ToolOutput 'WARNING: this removes profile registrations and quarantines (renames) their folders. Affected users must be logged off.' -Level Warning
        $gate = Read-ToolChoice -Prompt ('Type CONFIRM to remove these {0} orphaned profiles' -f $orphans.Count) -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
        if ($gate -ne 'CONFIRM') {
            Complete-ToolRun $run -Status Skipped -Summary 'RemoveOrphaned cancelled (no CONFIRM)'
            return
        }

        # 1. Backup ProfileList FIRST; abort if export fails (no changes made).
        $backup = Join-Path $env:TEMP ('ProfileList_backup_{0}.reg' -f $ts)
        & reg.exe export $plReg $backup /y *>$null
        if (-not (Test-Path -LiteralPath $backup)) {
            Complete-ToolRun $run -Status Failed -Summary 'Aborted: could not export ProfileList backup (no changes made)'
            return
        }
        Write-ToolOutput ('ProfileList backed up: {0}' -f $backup) -Level Info

        # 2. Per orphan: quarantine folder, then remove registration. Failure-isolated.
        $removed = 0
        $failed  = 0
        foreach ($o in $orphans) {
            $sid       = $o.Sid
            $localPath = $o.LocalPath

            if ($o.FolderExists) {
                try {
                    $leaf    = Split-Path -Path $localPath -Leaf
                    $newName = '{0}.orphan_{1}' -f $leaf, $ts
                    Rename-Item -LiteralPath $localPath -NewName $newName -ErrorAction Stop
                    Write-ToolOutput ('  Quarantined folder: {0} -> {1}' -f $localPath, $newName) -Level Info
                } catch {
                    Write-ToolOutput ('  SKIP {0}: could not quarantine folder ({1}); registration left intact; backup: {2}' -f $localPath, $_.Exception.Message, $backup) -Level Error
                    $failed++
                    continue
                }
            }

            $regGone = $false
            try {
                $inst = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { $_.SID -eq $sid }
                if ($inst) {
                    $inst | Remove-CimInstance -ErrorAction Stop
                }
                $regGone = $true
            } catch {
                # Fallback: delete the ProfileList key directly.
                & reg.exe delete ('{0}\{1}' -f $plReg, $sid) /f *>$null
                if ($LASTEXITCODE -eq 0) {
                    $regGone = $true
                } else {
                    Write-ToolOutput ('  FAILED to remove registration for SID {0} ({1}); folder already quarantined; backup: {2}' -f $sid, $_.Exception.Message, $backup) -Level Error
                    $failed++
                }
            }

            if ($regGone) {
                Write-ToolOutput ('  Removed orphaned profile: {0}  SID={1}' -f $localPath, $sid) -Level Success
                $removed++
            }
        }

        if ($removed -gt 0 -and $failed -eq 0) {
            Complete-ToolRun $run -Status Success -Summary ('Removed {0} orphaned profile(s); folders quarantined; backup: {1}' -f $removed, $backup)
        } elseif ($removed -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary ('Removed {0}, failed {1}; ProfileList backup: {2}' -f $removed, $failed, $backup)
        } else {
            Complete-ToolRun $run -Status Failed -Summary ('No profiles removed ({0} failed); ProfileList backup retained: {1}' -f $failed, $backup)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 4: Run the registry test + build to verify green**

Run: `Invoke-Pester .\tests\registry.tests.ps1 -Output Detailed`
Expected: PASS — `every registry Function exists in a tools file` and `every tool-file function has a registry entry` both pass; Ids/LegacyIds unique; Risk valid.

Run: `.\build.ps1`
Expected: prints `Built ...\dist\NMMTools.ps1 (... KB, v9.0.0-dev)` with no error output. The parse gate and the PSScriptAnalyzer Error gate both pass. (The Warning-severity `PSUseShouldProcessForStateChangingFunctions` on `Remove-OrphanedProfile` is acceptable — the gate fails only on Error, and existing `Remove-WindowsOld`/`Repair-TemporaryProfile` rely on the same `Read-ToolChoice` confirm pattern. If the analyzer reports an *Error*, fix it and re-run.)

- [ ] **Step 5: Commit**

```bash
git add src/registry/tools.psd1 src/tools/user/Remove-OrphanedProfile.ps1
git commit -m "feat: add Remove-OrphanedProfile (Orphaned Profile Cleanup) tool

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Full suite + build verification

**Files:** none changed (verification only)

- [ ] **Step 1: Run the full Pester suite**

Run: `Invoke-Pester .\tests -Output Detailed`
Expected: PASS — every test file green (the existing files plus the new `profile-helpers.tests.ps1`). Note the new total passing count (previously 97; +7 from `Get-NmmProfileVerdict`).

- [ ] **Step 2: Run the build (parse + analyzer gates)**

Run: `.\build.ps1`
Expected: `Built ...\dist\NMMTools.ps1` with no error output; `dist\NMMTools.ps1` regenerated; PSScriptAnalyzer reports no Error-severity findings.

- [ ] **Step 3: Manual smoke (documented; run only on a disposable test machine)**

This tool removes real profiles — do NOT run removal on a production machine. On a throwaway VM:
1. Create a local account, sign in once to materialize its profile, sign out, then delete the account (leaving an orphaned SID under `ProfileList`).
2. From the built artifact: `.\dist\NMMTools.ps1 -Tool orphaned-profiles` (interactive).
   - Expected: the audit lists the orphan as `[orphan: unknown-SID]`; the running admin and system profiles show `[protected]`.
   - Choose `RemoveOrphaned`, then type `CONFIRM`.
   - Expected: a `ProfileList backed up: %TEMP%\ProfileList_backup_<ts>.reg` line; `Quarantined folder: ... -> ....orphan_<ts>`; `Removed orphaned profile: ...`; the entry is gone from `SystemPropertiesAdvanced` > User Profiles; the folder is renamed (not deleted); the `.reg` backup exists.
3. Verify safety: `.\dist\NMMTools.ps1 -Tool orphaned-profiles -Silent` is refused (disruptive needs `-Force`); `.\dist\NMMTools.ps1 -Tool orphaned-profiles -Silent -Force` audits only (no removal, because the `CONFIRM` auto-cancels).

- [ ] **Step 4: Commit any artifact (only if `dist/` is tracked)**

`dist/` is git-ignored (`.gitignore` contains `dist/`), so there is nothing to commit here. Skip.

---

## Notes for the implementer

- **`CONFIRM`/`Cancel` both start with `C`:** `Read-ToolChoice` matches by unique prefix, so a bare `c` is ambiguous and re-prompts; the operator must type `con`/`CONFIRM` or `ca`/`Cancel`. This is intentional and identical to `Repair-TemporaryProfile`.
- **Why `Remove-CimInstance` after renaming the folder is safe:** `Win32_UserProfile` removal targets `ProfileImagePath`; once the folder is renamed away, there is no live folder at that path, so CIM removes only the registration + `ProfileList` key and cannot touch the quarantined data. The `reg.exe delete` fallback covers the rare case where `Remove-CimInstance` errors.
- **Silent safety:** `Read-ToolChoice` returns its `-Default` under the Silent sink / non-interactive host, so `action` defaults to `None` and `gate` to `Cancel` — the tool can never delete a profile without an interactive `CONFIRM`.
- **Tests dot-source `src` directly** — you do not need to run `build.ps1` between Pester iterations; only in Tasks 2-3 for the parse/analyzer gates.
- **ASCII only** — if `tests/encoding.tests.ps1` fails, you pasted a non-ASCII character (em-dash, smart quote, arrow glyph). Replace it with ASCII.
