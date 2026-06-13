# Porting Batch 5: Browser & Data Tools - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 Browser & Data tools (menu 48-50) into v9 as two tools - a merged `browser-backup-restore` (48/49) and a separate `browser-clear` (50) - backed by one shared browser catalog, hardening the v8 data-safety bugs.

**Architecture:** A new core helper `src\core\08-browser-helpers.ps1` is the single source of truth for each browser's paths and file-sets (catalog + profile enumeration + close-browsers + backup-root resolver). Two tool files in `src\tools\browser\` consume it. Backup/restore/clear logic is inlined in each tool's `switch` (BitLocker precedent) so each tool file defines exactly one registered function. A new `tests\browser-helpers.tests.ps1` locks the "passwords/autofill/bookmarks preserved" invariants.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs\superpowers\specs\2026-06-13-batch-5-browser-design.md`.

**v8 reference (READ-ONLY):** `C:\Users\IT\Desktop\NMMTools.ps1` - `Backup-BrowserData` L4189, `Restore-BrowserData` L4372, `Clear-BrowserCaches` L1601, `Get-BrowserBackupUserRoot` L4157.

---

## Standing rules (carried from batches 1-4)

- PS 5.1: no ternary / `??` / `&&`; never assign `$input`, `$matches`, or `$profile` (use `$prof`).
- **ASCII-only source** (the encoding test fails the build on non-ASCII). UTF-8 BOM + trailing newline.
- Tools use `Write-ToolOutput` / `Read-ToolChoice` only - never `Write-Host`. `Read-Host` is allowed ONLY for free-text path input that is reached after an interactive branch (never under `-Silent`).
- Every tool function: approved verb, `[switch]$Silent` param, calls `New-ToolRun` + `Complete-ToolRun`, and its `New-ToolRun -Id` literal MUST equal its registry `Id`.
- `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`.
- Core helper functions live in `src\core\` (exempt from the registry-mapping test, which scans `src\tools` only).

## Registry entries (added in Tasks 2 and 3)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable |
|---|---|---|---|---|---|---|---|
| browser-backup-restore | 48 | Browser Backup and Restore | Invoke-BrowserBackupRestore | Browser | $false | Modifies | $true |
| browser-clear | 50 | Comprehensive Browser Clear | Clear-BrowserData | Browser | $false | Disruptive | $true |

Legacy 49 (Restore) folds into 48 as an action - typing `49` will not dispatch (consistent with 99->22, 27->30).

## Smoke safety (non-elevated dev session)

- `browser-backup-restore -Silent` -> action menu defaults to **None** -> report only, exit 0. SAFE. Quote the summary.
- `browser-clear -Silent` -> Disruptive -> dispatcher refuses without `-Force`, exit 1. Quote the refusal.
- NEVER execute the real Backup write / Restore overwrite / Clear delete in the dev session. Verify those paths by READING the code + the helper tests.

---

## Setup: create the batch branch

- [ ] **Step 1: Branch off master**

Run:
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" checkout -b port/batch-5-browser
```
Expected: `Switched to a new branch 'port/batch-5-browser'`

---

## Task 1: Shared browser helper + tests (TDD)

**Files:**
- Create: `src\core\08-browser-helpers.ps1`
- Create: `tests\browser-helpers.tests.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests\browser-helpers.tests.ps1`:
```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\08-browser-helpers.ps1')
    $script:Catalog = @(Get-BrowserCatalog)
}

Describe 'Get-BrowserCatalog' {
    It 'returns the four supported browsers in order' {
        $script:Catalog.Count | Should -Be 4
        ($script:Catalog | ForEach-Object { $_.Name }) | Should -Be @('Chrome','Edge','Brave','Firefox')
    }
    It 'classifies three Chromium browsers and one Firefox' {
        @($script:Catalog | Where-Object { $_.Family -eq 'Chromium' }).Count | Should -Be 3
        @($script:Catalog | Where-Object { $_.Family -eq 'Firefox' }).Count  | Should -Be 1
    }
    It 'gives every browser a BasePath, ProcessNames, and ProfileGlobs' {
        foreach ($b in $script:Catalog) {
            [string]::IsNullOrWhiteSpace($b.BasePath) | Should -BeFalse
            @($b.ProcessNames).Count  | Should -BeGreaterThan 0
            @($b.ProfileGlobs).Count  | Should -BeGreaterThan 0
        }
    }
}

Describe 'browser-clear preserve invariant' {
    It 'never clears a preserved file (ClearFiles intersect PreserveFiles is empty)' {
        foreach ($b in $script:Catalog) {
            $overlap = @($b.ClearFiles | Where-Object { $b.PreserveFiles -contains $_ })
            $overlap | Should -BeNullOrEmpty -Because "$($b.Name) must not clear a preserved file"
        }
    }
    It 'preserves Chromium passwords, autofill, and bookmarks' {
        foreach ($b in @($script:Catalog | Where-Object { $_.Family -eq 'Chromium' })) {
            foreach ($keep in @('Login Data','Web Data','Bookmarks')) {
                $b.ClearFiles    | Should -Not -Contain $keep
                $b.PreserveFiles | Should -Contain $keep
            }
        }
    }
    It 'preserves Firefox passwords, bookmarks (places.sqlite), and autofill' {
        $ff = @($script:Catalog | Where-Object { $_.Name -eq 'Firefox' })[0]
        foreach ($keep in @('key4.db','logins.json','places.sqlite','formhistory.sqlite')) {
            $ff.ClearFiles    | Should -Not -Contain $keep
            $ff.PreserveFiles | Should -Contain $keep
        }
    }
}

Describe 'browser-backup set' {
    It 'includes the password stores' {
        foreach ($b in @($script:Catalog | Where-Object { $_.Family -eq 'Chromium' })) {
            $b.BackupFiles | Should -Contain 'Login Data'
        }
        $ff = @($script:Catalog | Where-Object { $_.Name -eq 'Firefox' })[0]
        $ff.BackupFiles | Should -Contain 'key4.db'
        $ff.BackupFiles | Should -Contain 'logins.json'
    }
}

Describe 'Get-BrowserProfiles' {
    It 'returns an empty array when the base path is absent' {
        $fake = @{ BasePath = 'Z:\NoSuchBrowser\User Data'; ProfileGlobs = @('Default','Profile*') }
        @(Get-BrowserProfiles -Browser $fake).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```powershell
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests\browser-helpers.tests.ps1" -Output Detailed
```
Expected: FAIL - `Get-BrowserCatalog` is not recognized (file does not exist yet).

- [ ] **Step 3: Write the helper implementation**

Create `src\core\08-browser-helpers.ps1`:
```powershell
# Shared browser helpers for browser-backup-restore and browser-clear.
# Plain functions (no registry entries). Single source of truth for where each
# browser stores its data, so the backup set and the clear set cannot drift apart.

function Get-BrowserCatalog {
    # Chromium (Chrome/Edge/Brave) share identical file-sets and profile layout.
    $chromiumBackup = @('Bookmarks','Bookmarks.bak','Preferences','History','Login Data','Web Data')
    $chromiumClearF = @('Cookies','Cookies-journal','History','History-journal',
                        'History Provider Cache','Top Sites','Top Sites-journal','Visited Links')
    $chromiumClearD = @('Cache','Code Cache','GPUCache','Service Worker\CacheStorage',
                        'Service Worker\ScriptCache','Session Storage','Local Storage','IndexedDB',
                        'File System','Network','Current Session','Current Tabs','Last Session','Last Tabs')
    # PreserveFiles must never appear in ClearFiles/ClearDirs (locked by browser-helpers.tests.ps1).
    $chromiumPreserve = @('Login Data','Login Data For Account','Web Data','Bookmarks','Bookmarks.bak')

    @(
        @{ Name = 'Chrome'; Family = 'Chromium'
           BasePath = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')
           ProcessNames = @('chrome'); ProfileGlobs = @('Default','Profile*')
           BackupFiles = $chromiumBackup; ClearFiles = $chromiumClearF; ClearDirs = $chromiumClearD
           PreserveFiles = $chromiumPreserve; PrefsFile = 'Preferences' }
        @{ Name = 'Edge'; Family = 'Chromium'
           BasePath = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')
           ProcessNames = @('msedge'); ProfileGlobs = @('Default','Profile*')
           BackupFiles = $chromiumBackup; ClearFiles = $chromiumClearF; ClearDirs = $chromiumClearD
           PreserveFiles = $chromiumPreserve; PrefsFile = 'Preferences' }
        @{ Name = 'Brave'; Family = 'Chromium'
           BasePath = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data')
           ProcessNames = @('brave'); ProfileGlobs = @('Default','Profile*')
           BackupFiles = $chromiumBackup; ClearFiles = $chromiumClearF; ClearDirs = $chromiumClearD
           PreserveFiles = $chromiumPreserve; PrefsFile = 'Preferences' }
        @{ Name = 'Firefox'; Family = 'Firefox'
           BasePath = (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles')
           ProcessNames = @('firefox'); ProfileGlobs = @('*')
           BackupFiles = @('places.sqlite','key4.db','logins.json','cookies.sqlite','formhistory.sqlite','prefs.js')
           ClearFiles = @('cookies.sqlite','cookies.sqlite-shm','cookies.sqlite-wal',
                          'favicons.sqlite','favicons.sqlite-shm','favicons.sqlite-wal',
                          'permissions.sqlite','permissions.sqlite-shm','permissions.sqlite-wal','content-prefs.sqlite')
           ClearDirs = @('cache2')
           PreserveFiles = @('key4.db','logins.json','places.sqlite','places.sqlite-shm',
                             'places.sqlite-wal','formhistory.sqlite')
           PrefsFile = $null }
    )
}

function Get-BrowserProfiles {
    # Returns the installed profile directories for one browser (empty array if absent).
    param([Parameter(Mandatory)]$Browser)
    if (-not (Test-Path -LiteralPath $Browser.BasePath)) { return @() }
    $dirs = @()
    foreach ($glob in $Browser.ProfileGlobs) {
        $dirs += Get-ChildItem -LiteralPath $Browser.BasePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $glob }
    }
    @($dirs | Sort-Object FullName -Unique)
}

function Get-BrowserBackupRoot {
    # Prefer M:\BrowserBackups\<user>; fall back to <Desktop>\BrowserBackups\<user>.
    # Pure resolver - does NOT create the directory (so the report/-Silent path has no side effect).
    param([string]$PreferredRoot = 'M:\BrowserBackups')
    $preferredDrive = Split-Path $PreferredRoot -Qualifier
    if ($preferredDrive -and (Test-Path -LiteralPath $preferredDrive)) {
        $root = $PreferredRoot
    } else {
        $root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BrowserBackups'
    }
    Join-Path $root $env:USERNAME
}

function Close-Browsers {
    # Graceful CloseMainWindow, wait, then Kill stragglers. Returns the process names it acted on.
    param([Parameter(Mandatory)][string[]]$ProcessNames)
    $closed = @()
    foreach ($proc in $ProcessNames) {
        $running = @(Get-Process -Name $proc -ErrorAction SilentlyContinue)
        foreach ($p in $running) { try { $p.CloseMainWindow() | Out-Null } catch {} }
        if ($running.Count -gt 0) { $closed += $proc }
    }
    Start-Sleep -Seconds 2
    foreach ($proc in $ProcessNames) {
        Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
    }
    @($closed | Sort-Object -Unique)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```powershell
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests\browser-helpers.tests.ps1" -Output Detailed
```
Expected: PASS - all `Describe` blocks green (9 `It` assertions).

- [ ] **Step 5: Run the FULL suite to confirm no regressions**

Run:
```powershell
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: `Tests Passed: 64+` (the prior 59 + the 5 new browser-helper `It`s), Failed: 0. (Build runs inside the suite via artifact.tests.)

- [ ] **Step 6: Commit**

```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/core/08-browser-helpers.ps1 tests/browser-helpers.tests.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: batch 5 shared browser catalog helper + preserve-invariant tests"
```

---

## Task 2: browser-backup-restore tool (48/49)

**Files:**
- Modify: `src\registry\tools.psd1` (append one entry inside the `Tools = @( ... )` array, before the closing `)`)
- Create: `src\tools\browser\Invoke-BrowserBackupRestore.ps1`

- [ ] **Step 1: Append the registry entry**

In `src\registry\tools.psd1`, add this entry as the last element of the `Tools` array (immediately before the line that closes the array):
```powershell
        @{
            Id            = 'browser-backup-restore'
            LegacyId      = '48'
            Name          = 'Browser Backup and Restore'
            Category      = 'Browser'
            Function      = 'Invoke-BrowserBackupRestore'
            Description   = 'Back up or restore Chrome/Edge/Firefox/Brave bookmarks, passwords, and preferences; backup is ACL-locked'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('browser','backup','restore','bookmarks')
        }
```

- [ ] **Step 2: Create the tool file**

Create `src\tools\browser\Invoke-BrowserBackupRestore.ps1`:
```powershell
function Invoke-BrowserBackupRestore {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'browser-backup-restore'
        $catalog = Get-BrowserCatalog

        # --- Report (always, read-only) ---
        $present = @()
        Write-ToolOutput 'Detected browsers:' -Level Info
        foreach ($b in $catalog) {
            $profiles = @(Get-BrowserProfiles -Browser $b)
            if ($profiles.Count -gt 0) {
                $present += $b
                Write-ToolOutput ('  {0}: {1} profile(s)' -f $b.Name, $profiles.Count) -Level Detail
            }
        }
        if ($present.Count -eq 0) {
            Write-ToolOutput 'No supported browsers found for this user.' -Level Warning
        }

        $userRoot = Get-BrowserBackupRoot
        Write-ToolOutput ('Backup root: {0}' -f $userRoot) -Level Info
        $existing = @(Get-ChildItem -LiteralPath $userRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'BrowserBackup_*' } | Sort-Object LastWriteTime -Descending)
        if ($existing.Count -gt 0) {
            Write-ToolOutput ('Existing backups ({0}):' -f $existing.Count) -Level Info
            for ($i = 0; $i -lt [Math]::Min(10, $existing.Count); $i++) {
                Write-ToolOutput ('  [{0}] {1}  {2}' -f $i,
                    $existing[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $existing[$i].Name) -Level Detail
            }
        }

        # --- Action menu (safe default None -> -Silent reports only) ---
        $action = Read-ToolChoice -Prompt 'Browser action' `
            -Choices @('None','Backup','Restore') -Default 'None' -Silent:$Silent

        switch ($action) {

            'Backup' {
                Write-ToolOutput 'WARNING: backup INCLUDES saved passwords (Chromium Login Data; Firefox key4.db/logins.json).' -Level Warning
                Write-ToolOutput 'Chromium passwords are encrypted to THIS machine/user and will NOT decrypt if restored elsewhere. Firefox passwords DO travel.' -Level Warning

                $closeChoice = Read-ToolChoice -Prompt 'Close all browsers for a clean backup?' `
                    -Choices @('Yes','No') -Default 'Yes' -Silent:$Silent
                if ($closeChoice -eq 'Yes') {
                    $procs = @($present | ForEach-Object { $_.ProcessNames } | Sort-Object -Unique)
                    if ($procs.Count -gt 0) { Close-Browsers -ProcessNames $procs | Out-Null }
                }

                $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                $destDir = Join-Path $userRoot ('BrowserBackup_{0}' -f $stamp)
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null

                $backedUp = 0
                foreach ($b in $present) {
                    foreach ($prof in @(Get-BrowserProfiles -Browser $b)) {
                        $target = Join-Path $destDir ('{0}\{1}' -f $b.Name, $prof.Name)
                        New-Item -Path $target -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                        foreach ($file in $b.BackupFiles) {
                            $src = Join-Path $prof.FullName $file
                            if (Test-Path -LiteralPath $src) {
                                try {
                                    Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction Stop
                                    $backedUp++
                                } catch {
                                    Write-ToolOutput ('  [FAIL] {0}/{1}/{2}: {3}' -f $b.Name, $prof.Name, $file, $_.Exception.Message) -Level Warning
                                }
                            }
                        }
                        Write-ToolOutput ('  {0}/{1}: backed up' -f $b.Name, $prof.Name) -Level Detail
                    }
                }

                $zipPath = '{0}.zip' -f $destDir
                try {
                    Compress-Archive -Path ('{0}\*' -f $destDir) -DestinationPath $zipPath -Force -ErrorAction Stop
                    Write-ToolOutput ('ZIP created: {0}' -f $zipPath) -Level Success
                } catch {
                    Write-ToolOutput ('ZIP creation failed: {0}' -f $_.Exception.Message) -Level Warning
                    $zipPath = $null
                }

                # ACL-lock folder + zip to current user (best-effort; warn on failure)
                $aclOk = $true
                & icacls "$destDir" /inheritance:r /grant:r ('{0}:(OI)(CI)F' -f $env:USERNAME) | Out-Null
                if ($LASTEXITCODE -ne 0) { $aclOk = $false }
                if ($zipPath) {
                    & icacls "$zipPath" /inheritance:r /grant:r ('{0}:F' -f $env:USERNAME) | Out-Null
                    if ($LASTEXITCODE -ne 0) { $aclOk = $false }
                }
                if ($aclOk) {
                    Write-ToolOutput 'Backup ACL-restricted to current user.' -Level Success
                    $aclNote = 'ACL-locked'
                } else {
                    Write-ToolOutput 'WARNING: ACL lock failed (common on network shares); backup is NOT restricted.' -Level Warning
                    $aclNote = 'ACL-lock failed'
                }

                Complete-ToolRun $run -Status Success `
                    -Summary ('Backed up {0} file(s) to {1} ({2})' -f $backedUp, $destDir, $aclNote)
            }

            'Restore' {
                if ($existing.Count -eq 0) {
                    Write-ToolOutput ('No backups found under {0}.' -f $userRoot) -Level Warning
                }
                # Read-Host is safe here: only reached in the interactive Restore branch (never under -Silent).
                $sel = Read-Host 'Backup number (from the list above) or full path to a folder/.zip'
                $backupPath = $null
                if ($sel -match '^\d+$' -and [int]$sel -lt $existing.Count) {
                    $backupPath = $existing[[int]$sel].FullName
                } elseif ($sel -and (Test-Path -LiteralPath $sel)) {
                    $backupPath = $sel
                }
                if (-not $backupPath) {
                    Complete-ToolRun $run -Status Warning -Summary 'Restore aborted: no valid backup selected'
                    return
                }

                $sourceRoot = $backupPath
                $tempFolder = $null
                if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                    if ($backupPath.ToLower().EndsWith('.zip')) {
                        $tempFolder = Join-Path $env:TEMP ('NMM_BrowserRestore_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                        New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null
                        Expand-Archive -LiteralPath $backupPath -DestinationPath $tempFolder -Force
                        $sourceRoot = $tempFolder
                    } else {
                        Complete-ToolRun $run -Status Warning -Summary 'Restore aborted: file is not a .zip'
                        return
                    }
                }

                Write-ToolOutput 'WARNING: restore OVERWRITES current browser data with the backup.' -Level Warning
                Write-ToolOutput 'Chromium passwords from another machine/user will not decrypt here.' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Proceed with restore (overwrites current data)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    if ($tempFolder -and (Test-Path -LiteralPath $tempFolder)) {
                        Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Complete-ToolRun $run -Status Skipped -Summary 'Restore cancelled by user'
                    return
                }

                $closeChoice = Read-ToolChoice -Prompt 'Close all browsers before restore?' `
                    -Choices @('Yes','No') -Default 'Yes' -Silent:$Silent
                if ($closeChoice -eq 'Yes') {
                    Close-Browsers -ProcessNames @('chrome','msedge','firefox','brave') | Out-Null
                }

                $restored = 0
                foreach ($b in $catalog) {
                    $browserSource = Join-Path $sourceRoot $b.Name
                    if (-not (Test-Path -LiteralPath $browserSource)) { continue }
                    foreach ($profDir in @(Get-ChildItem -LiteralPath $browserSource -Directory -ErrorAction SilentlyContinue)) {
                        $targetProfile = Join-Path $b.BasePath $profDir.Name
                        if (-not (Test-Path -LiteralPath $targetProfile)) {
                            New-Item -ItemType Directory -Path $targetProfile -Force | Out-Null
                        }
                        foreach ($file in @(Get-ChildItem -LiteralPath $profDir.FullName -File -ErrorAction SilentlyContinue)) {
                            if ($b.BackupFiles -notcontains $file.Name) {
                                Write-ToolOutput ('  [skip] unexpected file {0}/{1}/{2}' -f $b.Name, $profDir.Name, $file.Name) -Level Detail
                                continue
                            }
                            try {
                                Copy-Item -LiteralPath $file.FullName -Destination $targetProfile -Force -ErrorAction Stop
                                $restored++
                            } catch {
                                Write-ToolOutput ('  [FAIL] {0}/{1}/{2}: {3}' -f $b.Name, $profDir.Name, $file.Name, $_.Exception.Message) -Level Warning
                            }
                        }
                    }
                }

                if ($tempFolder -and (Test-Path -LiteralPath $tempFolder)) {
                    Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
                }
                Write-ToolOutput 'Restart browsers to load the restored data.' -Level Info
                Complete-ToolRun $run -Status Success -Summary ('Restored {0} file(s) from {1}' -f $restored, $backupPath)
            }

            default {
                # 'None' -> report only
                if ($present.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No browsers found; no action taken'
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} browser(s) detected; no action taken' -f $present.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build and run the full suite (the template/registry gates ARE the automated test)**

Run:
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: Build prints `Built ... NMMTools.ps1`. Suite Failed: 0. (Registry-to-function mapping, template compliance - approved verb `Invoke`, `-Silent` param, `New-ToolRun -Id 'browser-backup-restore'` matching the registry - and encoding all pass.)

- [ ] **Step 4: Smoke the silent (report-only) path**

Run:
```powershell
$env:USERPROFILE\Desktop\NMMToolkit\dist\NMMTools.ps1 -Tool browser-backup-restore -Silent
```
Expected: report of detected browsers + backup root + existing backups, then `[SUCCESS] N browser(s) detected; no action taken` (or `[WARNING] No browsers found...`). Exit 0. No files written. Quote the summary line.

> If the dist self-elevates and the dev session cannot elevate, run the function directly instead:
> `. .\dist\NMMTools.ps1` is not appropriate (it has a param/entry block); instead dot-source the three pieces and call the function:
> ```powershell
> $r = "$env:USERPROFILE\Desktop\NMMToolkit"
> . "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\08-browser-helpers.ps1"
> $script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
> . "$r\src\tools\browser\Invoke-BrowserBackupRestore.ps1"
> Set-OutputSink -Sink Silent; Invoke-BrowserBackupRestore -Silent
> ```
> Expected: the run brackets print and `Complete-ToolRun` records Success/Warning with no action taken.

- [ ] **Step 5: Commit**

```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/browser/Invoke-BrowserBackupRestore.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port browser batch 5.1 (browser-backup-restore, ACL-locked backup + DPAPI warning)"
```

---

## Task 3: browser-clear tool (50)

**Files:**
- Modify: `src\registry\tools.psd1` (append the second entry)
- Create: `src\tools\browser\Clear-BrowserData.ps1`

- [ ] **Step 1: Append the registry entry**

In `src\registry\tools.psd1`, add as the last element of the `Tools` array:
```powershell
        @{
            Id            = 'browser-clear'
            LegacyId      = '50'
            Name          = 'Comprehensive Browser Clear'
            Category      = 'Browser'
            Function      = 'Clear-BrowserData'
            Description   = 'Clear cache, cookies, history, sessions, and site permissions across all profiles; preserves passwords, autofill, and Firefox bookmarks'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('browser','cache','cookies','privacy')
        }
```

- [ ] **Step 2: Create the tool file**

Create `src\tools\browser\Clear-BrowserData.ps1`:
```powershell
function Clear-BrowserData {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'browser-clear'
        $catalog = Get-BrowserCatalog

        # --- Report ---
        Write-ToolOutput 'Comprehensive Browser Clear' -Level Info
        Write-ToolOutput '  CLEARS:    cache, cookies, history, sessions, site permissions' -Level Detail
        Write-ToolOutput '  PRESERVES: saved passwords, autofill, and Firefox bookmarks' -Level Detail
        $present = @()
        foreach ($b in $catalog) {
            $profiles = @(Get-BrowserProfiles -Browser $b)
            if ($profiles.Count -gt 0) {
                $present += [PSCustomObject]@{ Browser = $b; Profiles = $profiles }
                Write-ToolOutput ('  {0}: {1} profile(s)' -f $b.Name, $profiles.Count) -Level Detail
            }
        }
        if ($present.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No supported browsers found; nothing to clear'
            return
        }

        # --- Disruptive typed gate (refuses -Silent without -Force at the dispatcher) ---
        $gate = Read-ToolChoice `
            -Prompt 'Type CONFIRM to clear browsing data (passwords/autofill/Firefox bookmarks are kept)' `
            -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
        if ($gate -ne 'CONFIRM') {
            Complete-ToolRun $run -Status Skipped -Summary 'Browser clear cancelled (no CONFIRM)'
            return
        }

        # Force-close browsers (locked files block deletion)
        $allProcs = @($present | ForEach-Object { $_.Browser.ProcessNames } | Sort-Object -Unique)
        Write-ToolOutput 'Closing browsers...' -Level Info
        if ($allProcs.Count -gt 0) { Close-Browsers -ProcessNames $allProcs | Out-Null }
        Start-Sleep -Seconds 1

        $clearedItems = 0
        $clearedBrowsers = 0
        foreach ($entry in $present) {
            $b = $entry.Browser
            $browserItems = 0
            foreach ($prof in $entry.Profiles) {
                foreach ($dir in $b.ClearDirs) {
                    $full = Join-Path $prof.FullName $dir
                    if (Test-Path -LiteralPath $full) {
                        Remove-Item ('{0}\*' -f $full) -Recurse -Force -ErrorAction SilentlyContinue
                        $browserItems++
                    }
                }
                foreach ($file in $b.ClearFiles) {
                    $full = Join-Path $prof.FullName $file
                    if (Test-Path -LiteralPath $full) {
                        Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
                        $browserItems++
                    }
                }
                # Chromium: clear site permissions from Preferences JSON, preserving all other prefs.
                # Written UTF-8 without BOM (Chrome rejects a BOM in Preferences; v8 used ANSI Set-Content).
                if ($b.PrefsFile) {
                    $prefPath = Join-Path $prof.FullName $b.PrefsFile
                    if (Test-Path -LiteralPath $prefPath) {
                        try {
                            $prefs = Get-Content -LiteralPath $prefPath -Raw | ConvertFrom-Json
                            if ($prefs.profile.content_settings.exceptions) {
                                $prefs.profile.content_settings.exceptions = New-Object PSObject
                            }
                            if ($prefs.profile.per_host_zoom_levels) {
                                $prefs.profile.per_host_zoom_levels = New-Object PSObject
                            }
                            $json = $prefs | ConvertTo-Json -Depth 100 -Compress
                            [System.IO.File]::WriteAllText($prefPath, $json, (New-Object System.Text.UTF8Encoding($false)))
                            $browserItems++
                        } catch {
                            Write-ToolOutput ('  Note: could not edit {0} Preferences ({1})' -f $b.Name, $prof.Name) -Level Detail
                        }
                    }
                }
            }
            if ($browserItems -gt 0) {
                Write-ToolOutput ('  [OK] {0}: cleared {1} item(s) across {2} profile(s)' -f $b.Name, $browserItems, @($entry.Profiles).Count) -Level Success
                $clearedBrowsers++
                $clearedItems += $browserItems
            }
        }

        Complete-ToolRun $run -Status Success `
            -Summary ('Cleared {0} item(s) across {1} browser(s); passwords/autofill/Firefox bookmarks preserved' -f $clearedItems, $clearedBrowsers)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build and run the full suite**

Run:
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: Build OK. Suite Failed: 0 (approved verb `Clear`; `-Silent`; `New-ToolRun -Id 'browser-clear'` matches registry; unique Id/LegacyId).

- [ ] **Step 4: Smoke the silent refusal (Disruptive)**

Run:
```powershell
$env:USERPROFILE\Desktop\NMMToolkit\dist\NMMTools.ps1 -Tool browser-clear -Silent
```
Expected: dispatcher refuses (`Refused` / exit 1) because `browser-clear` is Disruptive and `-Silent` was passed without `-Force`. Quote the refusal line. NEVER pass `-Force` here in dev.

> Dispatcher-direct fallback if the dist self-elevates (mirrors dispatch.tests):
> ```powershell
> $r = "$env:USERPROFILE\Desktop\NMMToolkit"
> . "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"; . "$r\src\core\08-browser-helpers.ps1"
> $script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $true
> . "$r\src\tools\browser\Clear-BrowserData.ps1"
> $tool = Resolve-NmmTool -Query 'browser-clear'
> Invoke-NmmTool -Tool $tool -Silent   # Expected: 'Refused'
> ```

- [ ] **Step 5: Commit**

```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/browser/Clear-BrowserData.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port browser batch 5.2 (browser-clear, all-profiles + FF-bookmark-safe)"
```

---

## Task 4: Batch close-out

**Files:**
- Modify: `docs\parity-checklist.md`

- [ ] **Step 1: Verify 66 tools across 5 categories**

Run:
```powershell
$out = & "$env:USERPROFILE\Desktop\NMMToolkit\dist\NMMTools.ps1" -ListTools
($out | Select-String -Pattern '\bBrowser\b').Count   # expect 2 browser rows
```
Expected: total tool rows = **66** (2 Browser + 8 Cloud + 23 Diagnostics + 17 Laptop + 16 Repair). The two Browser rows: `browser-backup-restore` (Modifies, Admin False) and `browser-clear` (Disruptive, Admin False). Quote both rows.

- [ ] **Step 2: Confirm full suite + build are green**

Run:
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: Build OK; `Failed: 0`.

- [ ] **Step 3: Update the parity checklist**

In `docs\parity-checklist.md`, update the Browser & Data Tools table rows for 48-50:
```markdown
| 48 | Browser Backup (Chrome/Edge/Firefox/Brave) | ported (batch 5) | browser-backup-restore |
| 49 | Browser Restore from Backup | consolidated -> tool 48 (browser-backup-restore) | - |
| 50 | Comprehensive Browser Clear (All Data Except Passwords) | ported (batch 5) | browser-clear |
```
And update the header count line near the top of the file from `64 of ~111 items ported` to `66 of ~111 items ported` and append `, 48, 50` (and note 49 consolidated) to the ported-items list.

- [ ] **Step 4: Commit the docs**

```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add docs/parity-checklist.md
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "docs: batch 5 complete - parity checklist (66/106 ported)"
```

- [ ] **Step 5: Final review + finish the branch**

Review focus: backup ACL-lock applied to folder AND zip; DPAPI cross-machine warning shown; restore overwrites only known catalog files (allow-list) and confirms (Default No); clear iterates ALL profiles, preserves Login Data/Web Data/Bookmarks (Chromium) and key4.db/logins.json/places.sqlite/formhistory.sqlite (Firefox); Disruptive `browser-clear` refuses silent-no-force.

Then invoke the **superpowers:finishing-a-development-branch** skill to merge `port/batch-5-browser` to master (verify suite on the merged result before deleting the branch).

---

## Self-review (completed by plan author)

- **Spec coverage:** Decisions 1-6 -> merged tool (Task 2) + separate clear (Task 3) + shared helper (Task 1); ACL-lock + DPAPI warning (Task 2 Backup); M: destination (`Get-BrowserBackupRoot`, Task 1); all-profiles clear (Task 3, `ProfileGlobs` + per-profile loop); FF bookmark preservation (Task 1 catalog `PreserveFiles` keeps `places.sqlite`, Task 3 only removes `ClearFiles`); browser-helpers tests (Task 1). User-context caveat surfaced via the report. Testing + smoke matrix -> Task 1 Step 5, Task 2 Step 4, Task 3 Step 4, Task 4.
- **Placeholder scan:** none - every step has complete code, exact commands, expected output.
- **Type/name consistency:** `Get-BrowserCatalog`, `Get-BrowserProfiles`, `Get-BrowserBackupRoot`, `Close-Browsers` defined in Task 1 and used identically in Tasks 2-3; catalog keys (`BasePath`, `ProcessNames`, `ProfileGlobs`, `BackupFiles`, `ClearFiles`, `ClearDirs`, `PreserveFiles`, `PrefsFile`) match between helper, tests, and both tools. Registry `Id` literals match the `New-ToolRun -Id` literals.
