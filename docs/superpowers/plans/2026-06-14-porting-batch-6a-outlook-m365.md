# Batch 6A: Outlook / M365 Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 Outlook/M365 tools 76, 79, 80, 81, 82, 96 into v9 as six `User`-category tools (consolidating 78 into the M365 auth tool and 106 into the search tool), each following the report-then-action pattern.

**Architecture:** One tool = one file in `src/tools/user/` defining one top-level function, plus one entry in `src/registry/tools.psd1`. The single-file artifact is produced by `build.ps1`. Destructive arms are gated behind `Read-ToolChoice -Default 'None' -Silent:$Silent` so `-Silent` is report-only. The generic template/registry/encoding Pester suites auto-cover each new tool; there are no per-tool unit tests to author.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs/superpowers/specs/2026-06-14-batch-6a-outlook-m365-design.md`

---

## Conventions every task must follow

- **PS 5.1 only:** no ternary, `??`, `&&`/`||`. Never ASSIGN `$input`/`$matches`/`$profile` (reading `$Matches[n]` after `-match` is allowed). Approved verbs only.
- **`New-ToolRun -Id '<id>'`** literal MUST equal the registry `Id` (AST template test enforces this on the top-level function only).
- **Nested helper functions** (e.g. `Stop-OutlookGraceful`, `Get-OfficeCredTarget`) are defined *inside* the tool function so the registry scanner (top-level `FindAll(..., $false)`) ignores them. Two tool files may each define their own `Stop-OutlookGraceful` — they are function-local, so there is no collision in the concatenated artifact.
- **Encoding:** ASCII-only source, UTF-8 **with BOM**, trailing newline. Write the file, then run the encoding fix (Step shown in Task 1) — the `encoding.tests.ps1` suite checks BOM + ASCII + trailing newline.
- **Status enum:** `Complete-ToolRun -Status` accepts only `Success | Failed | Warning | Skipped`. `Error` is a `Write-ToolOutput -Level`, not a status.
- **Build + test after every tool:**
  ```powershell
  Import-Module Pester -MinimumVersion 5.0
  & "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
  Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
  ```
  Expected: build succeeds, all tests green, the registry/template test counts rise by one each tool.
- **Commit message:** single-line `-m` only (never a here-string containing a quoted word — it mangles git args).

## File Structure

- Create: `src/tools/user/Repair-OutlookSearch.ps1` (Task 1)
- Create: `src/tools/user/Reset-M365Auth.ps1` (Task 2)
- Create: `src/tools/user/Repair-AutoDiscover.ps1` (Task 3)
- Create: `src/tools/user/Reset-OutlookOst.ps1` (Task 4)
- Create: `src/tools/user/Repair-OutlookProfile.ps1` (Task 5)
- Create: `src/tools/user/Repair-OutlookAddins.ps1` (Task 6)
- Modify: `src/registry/tools.psd1` — append one entry per tool (each task), inserted before the closing `    )` that currently follows the `audio-repair` entry.
- Modify: `docs/parity-checklist.md` (Task 7)

---

### Task 1: outlook-search-repair (v8 76 + 106)

**Files:**
- Create: `src/tools/user/Repair-OutlookSearch.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Repair-OutlookSearch {
    [CmdletBinding()]
    param([switch]$Silent)

    # Close Outlook gracefully then force; returns $true if Outlook is no longer running.
    function Stop-OutlookGraceful {
        $proc = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue)
        if ($proc.Count -eq 0) { return $true }
        foreach ($p in $proc) { $p.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        if (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0) {
            Stop-Process -Name 'OUTLOOK' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        return (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -eq 0)
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-search-repair'
        $edb = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb"
        $catalogKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Search'

        # --- Report ---
        $ws = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if ($ws) {
            Write-ToolOutput ('Windows Search (WSearch): {0} (StartType {1})' -f $ws.Status, $ws.StartType) -Level Info
        } else {
            Write-ToolOutput 'Windows Search service (WSearch) not found.' -Level Warning
        }
        if (Test-Path -LiteralPath $edb) {
            $sizeMB = [math]::Round((Get-Item -LiteralPath $edb -ErrorAction SilentlyContinue).Length / 1MB, 1)
            Write-ToolOutput ('Search index DB: {0} ({1} MB)' -f $edb, $sizeMB) -Level Detail
        } else {
            Write-ToolOutput 'Search index DB (Windows.edb) not found at the default path.' -Level Detail
        }
        $olRunning = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0
        Write-ToolOutput ('Outlook running: {0}' -f $olRunning) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook search repair' `
            -Choices @('None','RestartService','RebuildIndex') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartService' {
                [void](Stop-OutlookGraceful)
                Restart-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                $now = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status
                if (-not $now) { $now = 'Unknown' }
                if ($now -eq 'Running') {
                    Complete-ToolRun $run -Status Success -Summary 'WSearch restarted (Running); Outlook search will recover'
                } else {
                    Complete-ToolRun $run -Status Warning -Summary ('WSearch restart left status {0}' -f $now)
                }
            }

            'RebuildIndex' {
                $confirm = Read-ToolChoice -Prompt 'Stop WSearch, delete the search index, and rebuild? (15-60 min reindex)' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RebuildIndex cancelled'
                    return
                }
                [void](Stop-OutlookGraceful)
                Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $stopped = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status -eq 'Stopped'
                $deleted = $false
                if ($stopped) {
                    $dir = Split-Path -Parent $edb
                    if (Test-Path -LiteralPath $edb) {
                        Remove-Item -LiteralPath $edb -Force -ErrorAction SilentlyContinue
                    }
                    Get-ChildItem -LiteralPath $dir -Filter '*.log' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                    $deleted = -not (Test-Path -LiteralPath $edb)
                }
                if (Test-Path -LiteralPath $catalogKey) {
                    Remove-ItemProperty -LiteralPath $catalogKey -Name 'Catalog' -ErrorAction SilentlyContinue
                }
                Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $now = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status
                if (-not $now) { $now = 'Unknown' }
                if (-not $stopped) {
                    Complete-ToolRun $run -Status Warning -Summary 'WSearch did not stop; index not deleted (Windows.edb is locked while WSearch runs)'
                } elseif ($now -ne 'Running') {
                    Complete-ToolRun $run -Status Warning -Summary ('Index removed but WSearch status is {0}' -f $now)
                } elseif (-not $deleted) {
                    Complete-ToolRun $run -Status Warning -Summary 'WSearch restarted but Windows.edb still present; rebuild may not have triggered'
                } else {
                    Complete-ToolRun $run -Status Success -Summary 'Search index deleted; WSearch Running; rebuild started (15-60 min)'
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Outlook search state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** in `src/registry/tools.psd1`, immediately after the `audio-repair` entry's closing `}` and before the closing `    )`:

```powershell
        @{
            Id            = 'outlook-search-repair'
            LegacyId      = '76'
            Name          = 'Outlook Search Repair'
            Category      = 'User'
            Function      = 'Repair-OutlookSearch'
            Description   = 'Report Windows Search service, index DB size, and Outlook state, then restart WSearch or rebuild the search index (deletes Windows.edb and clears the Outlook search catalog); see also tool 54'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','search','wsearch','index')
        }
```

- [ ] **Step 3: Fix encoding** (BOM + trailing newline). Run:

```powershell
$f = "$env:USERPROFILE\Desktop\NMMToolkit\src\tools\user\Repair-OutlookSearch.ps1"
$txt = (Get-Content -LiteralPath $f -Raw) -replace "`r`n","`n" -replace "`n","`r`n"
if ($txt[-1] -ne "`n") { $txt += "`r`n" }
$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($f, $txt, $enc)
```

- [ ] **Step 4: Build and test.** Run:

```powershell
Import-Module Pester -MinimumVersion 5.0
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```

Expected: build succeeds; all tests pass; registry now reports 81 tools.

- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(6a): outlook-search-repair (port v8 76, fold 106)"
```

---

### Task 2: m365-auth-reset (v8 79 + 78)

**Files:**
- Create: `src/tools/user/Reset-M365Auth.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Reset-M365Auth {
    [CmdletBinding()]
    param([switch]$Silent)

    # Parse cmdkey /list for Office/M365 credential targets (anchored Target: line).
    function Get-OfficeCredTarget {
        $targets = New-Object System.Collections.Generic.List[string]
        foreach ($line in (cmdkey /list 2>$null)) {
            if ($line -match '^\s*Target:\s*(.+?)\s*$') {
                $t = $Matches[1]
                if ($t -match 'MicrosoftOffice|office|microsoftonline|sharepoint|outlook') {
                    $targets.Add($t)
                }
            }
        }
        return $targets
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'm365-auth-reset'
        $local      = $env:LOCALAPPDATA
        $msalPaths  = @("$local\Microsoft\OneAuth", "$local\Microsoft\IdentityCache")
        $wamCache   = "$local\Microsoft\TokenBroker\Cache"
        $adGlob     = "$local\Microsoft\Outlook\*autodiscover*"
        $secModeKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook'

        # --- Report ---
        $creds = @(Get-OfficeCredTarget)
        Write-ToolOutput ('Office/M365 saved credentials: {0}' -f $creds.Count) -Level Info
        foreach ($c in $creds) { Write-ToolOutput ('  {0}' -f $c) -Level Detail }
        foreach ($p in $msalPaths) {
            Write-ToolOutput ('MSAL cache {0} present: {1}' -f (Split-Path -Leaf $p), (Test-Path -LiteralPath $p)) -Level Detail
        }
        Write-ToolOutput ('WAM TokenBroker cache present: {0}' -f (Test-Path -LiteralPath $wamCache)) -Level Detail
        $adFiles = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        Write-ToolOutput ('AutoDiscover cache files: {0}' -f $adFiles.Count) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'M365 auth reset (closes Office apps; user must sign in again)' `
            -Choices @('None','ClearTokens','ClearTokensAndSharedMailbox') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success -Summary ('{0} Office credential(s) reported; no action taken' -f $creds.Count)
            return
        }

        $confirm = Read-ToolChoice -Prompt 'Close all Office apps and clear cached sign-in tokens?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($confirm -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary ('{0} cancelled' -f $action)
            return
        }

        foreach ($name in @('OUTLOOK','TEAMS','ms-teams','MSTeams','WINWORD','EXCEL','ONENOTE')) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2

        $cleared = 0
        foreach ($t in @(Get-OfficeCredTarget)) {
            cmdkey /delete:$t 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $cleared++ }
        }

        foreach ($p in ($msalPaths + $wamCache)) {
            if (Test-Path -LiteralPath $p) {
                Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $extra = ''
        if ($action -eq 'ClearTokensAndSharedMailbox') {
            $adRemoved = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
            $adRemoved | Remove-Item -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $secModeKey -Name 'OutlookSecurityMode' -ErrorAction SilentlyContinue
            $extra = ('; {0} AutoDiscover cache file(s) removed, OutlookSecurityMode cleared' -f $adRemoved.Count)
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} credential(s) cleared, MSAL/WAM caches reset{1}; user must sign in again' -f $cleared, $extra)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after the `outlook-search-repair` entry, before the closing `    )`):

```powershell
        @{
            Id            = 'm365-auth-reset'
            LegacyId      = '79'
            Name          = 'M365 Auth Reset'
            Category      = 'User'
            Function      = 'Reset-M365Auth'
            Description   = 'Report Office/M365 saved credentials and MSAL/WAM token caches, then clear them (stops the sign-in loop); optionally also clear AutoDiscover cache + OutlookSecurityMode for shared-mailbox access; see also tools 60/85'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','m365','auth','token','wam','credential')
        }
```

- [ ] **Step 3: Fix encoding** — same command as Task 1 Step 3, with `$f` pointing at `Reset-M365Auth.ps1`.
- [ ] **Step 4: Build and test** — same command as Task 1 Step 4. Expected: 82 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(6a): m365-auth-reset (port v8 79, fold 78 shared mailbox)"
```

---

### Task 3: autodiscover-fix (v8 80)

**Files:**
- Create: `src/tools/user/Repair-AutoDiscover.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Repair-AutoDiscover {
    [CmdletBinding()]
    param([switch]$Silent)

    # HEAD the AutoDiscover endpoint; returns a human-readable status string.
    function Test-AutoDiscoverEndpoint {
        try {
            $r = Invoke-WebRequest -Uri 'https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml' -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            return ('reachable (HTTP {0})' -f $r.StatusCode)
        } catch {
            return ('unreachable: {0}' -f $_.Exception.Message)
        }
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'autodiscover-fix'
        $adGlob = "$env:LOCALAPPDATA\Microsoft\Outlook\*autodiscover*"
        $adKey  = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\AutoDiscover'

        # --- Report ---
        Write-ToolOutput ('AutoDiscover endpoint: {0}' -f (Test-AutoDiscoverEndpoint)) -Level Info
        $adFiles = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        Write-ToolOutput ('AutoDiscover cache files: {0}' -f $adFiles.Count) -Level Detail
        Write-ToolOutput ('AutoDiscover registry key present: {0}' -f (Test-Path -LiteralPath $adKey)) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'AutoDiscover fix' -Choices @('None','Fix') -Default 'None' -Silent:$Silent

        if ($action -ne 'Fix') {
            Complete-ToolRun $run -Status Success -Summary 'AutoDiscover state reported; no action taken'
            return
        }

        ipconfig /flushdns | Out-Null
        $removed = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        $removed | Remove-Item -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $adKey) {
            Remove-Item -LiteralPath $adKey -Recurse -Force -ErrorAction SilentlyContinue
        }
        $retest = Test-AutoDiscoverEndpoint
        if ($retest -like 'reachable*') {
            Complete-ToolRun $run -Status Success -Summary ('DNS flushed, {0} cache file(s) + reg key cleared; endpoint {1}' -f $removed.Count, $retest)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('DNS flushed, {0} cache file(s) + reg key cleared; endpoint still {1}' -f $removed.Count, $retest)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `m365-auth-reset`, before the closing `    )`):

```powershell
        @{
            Id            = 'autodiscover-fix'
            LegacyId      = '80'
            Name          = 'AutoDiscover Fix'
            Category      = 'User'
            Function      = 'Repair-AutoDiscover'
            Description   = 'Test the Outlook AutoDiscover endpoint and report cache/registry state, then flush DNS, clear AutoDiscover cache files and the AutoDiscover registry key, and re-test; see also m365-auth-reset'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','autodiscover','dns','exchange')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Repair-AutoDiscover.ps1`.
- [ ] **Step 4: Build and test** — Expected: 83 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(6a): autodiscover-fix (port v8 80)"
```

---

### Task 4: outlook-ost-rebuild (v8 81)

**Files:**
- Create: `src/tools/user/Reset-OutlookOst.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Reset-OutlookOst {
    [CmdletBinding()]
    param([switch]$Silent)

    function Stop-OutlookGraceful {
        $proc = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue)
        if ($proc.Count -eq 0) { return $true }
        foreach ($p in $proc) { $p.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        if (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0) {
            Stop-Process -Name 'OUTLOOK' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        return (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -eq 0)
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-ost-rebuild'
        $ostDir = "$env:LOCALAPPDATA\Microsoft\Outlook"

        # --- Report ---
        $ost = @(Get-ChildItem -Path "$ostDir\*.ost" -ErrorAction SilentlyContinue)
        if ($ost.Count -eq 0) {
            Write-ToolOutput 'No .ost files found (Outlook may be in IMAP or online mode).' -Level Warning
        } else {
            Write-ToolOutput ('OST files: {0}' -f $ost.Count) -Level Info
            foreach ($o in $ost) {
                Write-ToolOutput ('  {0}  ({1} MB)' -f $o.Name, [math]::Round($o.Length / 1MB, 1)) -Level Detail
            }
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Rename OST to force an Exchange re-sync' -Choices @('None','RenameOst') -Default 'None' -Silent:$Silent

        if ($action -ne 'RenameOst') {
            Complete-ToolRun $run -Status Success -Summary ('{0} OST file(s) reported; no action taken' -f $ost.Count)
            return
        }
        if ($ost.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary 'No OST file to rebuild (IMAP/online mode)'
            return
        }
        $confirm = Read-ToolChoice -Prompt 'Close Outlook and rename the OST? Outlook re-syncs from Exchange on next launch.' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($confirm -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'RenameOst cancelled'
            return
        }
        if (-not (Stop-OutlookGraceful)) {
            Complete-ToolRun $run -Status Warning -Summary 'Outlook is still running; the OST is locked - close Outlook and retry'
            return
        }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $renamed = 0
        foreach ($o in @(Get-ChildItem -Path "$ostDir\*.ost" -ErrorAction SilentlyContinue)) {
            $newName = ('{0}.bak_{1}' -f $o.Name, $stamp)
            Rename-Item -LiteralPath $o.FullName -NewName $newName -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $o.FullName)) { $renamed++ }
        }
        if ($renamed -gt 0) {
            Complete-ToolRun $run -Status Success -Summary ('{0} OST file(s) renamed; relaunch Outlook to rebuild from Exchange' -f $renamed)
        } else {
            Complete-ToolRun $run -Status Warning -Summary 'No OST files were renamed (still locked or already gone)'
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `autodiscover-fix`, before the closing `    )`):

```powershell
        @{
            Id            = 'outlook-ost-rebuild'
            LegacyId      = '81'
            Name          = 'Outlook OST Rebuild'
            Category      = 'User'
            Function      = 'Reset-OutlookOst'
            Description   = 'List Outlook OST cache files and sizes, then close Outlook and rename each OST (keeps a timestamped .bak) so Outlook re-syncs from Exchange on next launch'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','ost','cache','exchange','resync')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Reset-OutlookOst.ps1`.
- [ ] **Step 4: Build and test** — Expected: 84 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(6a): outlook-ost-rebuild (port v8 81)"
```

---

### Task 5: outlook-profile-repair (v8 82)

**Files:**
- Create: `src/tools/user/Repair-OutlookProfile.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Repair-OutlookProfile {
    [CmdletBinding()]
    param([switch]$Silent)

    function Stop-OutlookGraceful {
        $proc = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue)
        if ($proc.Count -eq 0) { return $true }
        foreach ($p in $proc) { $p.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        if (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0) {
            Stop-Process -Name 'OUTLOOK' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        return (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -eq 0)
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-profile-repair'
        $profilesKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
        $outlookKey  = 'HKCU:\Software\Microsoft\Office\16.0\Outlook'

        # --- Report ---
        $profiles = @(Get-ChildItem -LiteralPath $profilesKey -ErrorAction SilentlyContinue)
        Write-ToolOutput ('Outlook profiles: {0}' -f $profiles.Count) -Level Info
        foreach ($p in $profiles) { Write-ToolOutput ('  {0}' -f $p.PSChildName) -Level Detail }
        $def = (Get-ItemProperty -LiteralPath $outlookKey -Name 'DefaultProfile' -ErrorAction SilentlyContinue).DefaultProfile
        if ($def) { Write-ToolOutput ('Default profile: {0}' -f $def) -Level Detail }
        Write-ToolOutput 'WARNING: RecreateProfile deletes ALL Outlook profile settings. Mail data on the server is unaffected.' -Level Warning

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook profile repair' -Choices @('None','RecreateProfile') -Default 'None' -Silent:$Silent

        if ($action -ne 'RecreateProfile') {
            Complete-ToolRun $run -Status Success -Summary ('{0} profile(s) reported; no action taken' -f $profiles.Count)
            return
        }

        # Nuclear: require typed confirmation (free-text after an interactive choice; never reached under -Silent)
        $typed = Read-Host 'Type REBUILD to delete and recreate the Outlook profile'
        if ($typed -ne 'REBUILD') {
            Complete-ToolRun $run -Status Skipped -Summary 'RecreateProfile cancelled (confirmation not typed)'
            return
        }

        [void](Stop-OutlookGraceful)

        $backup = Join-Path $env:TEMP ('OutlookProfiles_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        reg export 'HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles' $backup /y 2>$null | Out-Null

        Remove-Item -LiteralPath $profilesKey -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $profilesKey -Force | Out-Null
        New-Item -Path (Join-Path $profilesKey 'Outlook') -Force | Out-Null
        Set-ItemProperty -LiteralPath $outlookKey -Name 'DefaultProfile' -Value 'Outlook' -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath (Join-Path $profilesKey 'Outlook')) {
            Complete-ToolRun $run -Status Success -Summary ('Outlook profile recreated; backup at {0}; relaunch Outlook to run setup' -f $backup)
        } else {
            Write-ToolOutput ('Profile recreation FAILED. Restore from backup: {0}' -f $backup) -Level Error
            Complete-ToolRun $run -Status Failed -Summary ('Profile recreation failed; restore from backup: {0}' -f $backup)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `outlook-ost-rebuild`, before the closing `    )`). Note `Risk = 'Disruptive'`:

```powershell
        @{
            Id            = 'outlook-profile-repair'
            LegacyId      = '82'
            Name          = 'Outlook Profile Repair'
            Category      = 'User'
            Function      = 'Repair-OutlookProfile'
            Description   = 'List Outlook profiles, then (nuclear) back up the Profiles registry key, delete it, and recreate a fresh default profile - all account settings are wiped; requires a typed REBUILD confirmation; see also tool 22'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('outlook','profile','registry','nuclear')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Repair-OutlookProfile.ps1`.
- [ ] **Step 4: Build and test** — Expected: 85 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(6a): outlook-profile-repair (port v8 82)"
```

---

### Task 6: outlook-addin-repair (v8 96)

**Files:**
- Create: `src/tools/user/Repair-OutlookAddins.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Repair-OutlookAddins {
    [CmdletBinding()]
    param([switch]$Silent)

    # Scan Outlook add-in keys (HKCU + HKLM) read-only.
    function Get-OutlookAddin {
        $roots = @(
            'HKCU:\Software\Microsoft\Office\16.0\Outlook\Addins',
            'HKLM:\Software\Microsoft\Office\16.0\Outlook\Addins',
            'HKLM:\Software\WOW6432Node\Microsoft\Office\16.0\Outlook\Addins'
        )
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                $lb = $null
                if ($props -and ($props.PSObject.Properties.Name -contains 'LoadBehavior')) { $lb = [int]$props.LoadBehavior }
                $fn = $k.PSChildName
                if ($props -and $props.FriendlyName) { $fn = $props.FriendlyName }
                $list.Add([pscustomobject]@{
                    Name         = $k.PSChildName
                    FriendlyName = $fn
                    LoadBehavior = $lb
                    Hive         = ($root -split ':')[0]
                    PSPath       = $k.PSPath
                })
            }
        }
        return $list
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-addin-repair'
        $resiliencyRoot = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
        $disabledKey    = Join-Path $resiliencyRoot 'DisabledItems'
        $crashKey       = Join-Path $resiliencyRoot 'CrashingAddinList'
        $doNotDisable   = Join-Path $resiliencyRoot 'DoNotDisableAddinList'

        # --- Report ---
        $addins = @(Get-OutlookAddin)
        Write-ToolOutput ('Outlook add-ins found: {0}' -f $addins.Count) -Level Info
        foreach ($a in $addins) {
            $lbText = 'n/a'
            if ($null -ne $a.LoadBehavior) { $lbText = [string]$a.LoadBehavior }
            Write-ToolOutput ('  [{0}] {1}  LoadBehavior={2}' -f $a.Hive, $a.FriendlyName, $lbText) -Level Detail
        }
        $disabledCount = 0
        if (Test-Path -LiteralPath $disabledKey) {
            $dp = (Get-ItemProperty -LiteralPath $disabledKey -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
            $disabledCount = @($dp).Count
        }
        $crashCount = 0
        if (Test-Path -LiteralPath $crashKey) {
            $cp = (Get-ItemProperty -LiteralPath $crashKey -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
            $crashCount = @($cp).Count
        }
        Write-ToolOutput ('Resiliency DisabledItems: {0}; CrashingAddinList: {1}' -f $disabledCount, $crashCount) -Level Detail
        $onbase = @($addins | Where-Object { $_.Name -match 'OnBase|Hyland' -or $_.FriendlyName -match 'OnBase|Hyland' })
        if ($onbase.Count -gt 0) { Write-ToolOutput ('OnBase/Hyland add-in detected: {0}' -f $onbase[0].FriendlyName) -Level Info }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook add-in repair' -Choices @('None','ReEnable') -Default 'None' -Silent:$Silent
        if ($action -ne 'ReEnable') {
            Complete-ToolRun $run -Status Success -Summary ('{0} add-in(s) reported; no action taken' -f $addins.Count)
            return
        }

        if (Test-Path -LiteralPath $disabledKey) { Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $crashKey)    { Remove-Item -LiteralPath $crashKey -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not (Test-Path -LiteralPath $doNotDisable)) { New-Item -Path $doNotDisable -Force -ErrorAction SilentlyContinue | Out-Null }

        $reenabled = New-Object System.Collections.Generic.List[string]
        foreach ($a in $addins) {
            if ($a.Hive -eq 'HKCU' -and $a.LoadBehavior -eq 0) {
                Set-ItemProperty -LiteralPath $a.PSPath -Name 'LoadBehavior' -Value 3 -ErrorAction SilentlyContinue
                $reenabled.Add($a.FriendlyName)
            }
            $existing = Get-ItemProperty -LiteralPath $doNotDisable -Name $a.Name -ErrorAction SilentlyContinue
            if ($null -eq $existing) {
                New-ItemProperty -LiteralPath $doNotDisable -Name $a.Name -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }

        Complete-ToolRun $run -Status Success -Summary ('Cleared {0} disabled + {1} crashing entr(ies); re-enabled {2} add-in(s)' -f $disabledCount, $crashCount, $reenabled.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `outlook-profile-repair`, before the closing `    )`):

```powershell
        @{
            Id            = 'outlook-addin-repair'
            LegacyId      = '96'
            Name          = 'Outlook Add-in Repair'
            Category      = 'User'
            Function      = 'Repair-OutlookAddins'
            Description   = 'Report Outlook add-ins (HKCU/HKLM) and Resiliency disabled/crashing lists, then clear those lists, re-enable disabled HKCU add-ins (LoadBehavior 3), and protect them from auto-disable (OnBase/Hyland aware)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','addin','onbase','loadbehavior','resiliency')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Repair-OutlookAddins.ps1`.
- [ ] **Step 4: Build and test** — Expected: 86 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(6a): outlook-addin-repair (port v8 96)"
```

---

### Task 7: Update parity checklist

**Files:**
- Modify: `docs/parity-checklist.md`

- [ ] **Step 1: Update the header count.** Change the line beginning `Generated at batch 1 close-out;...` so it reads `updated batch 6a close-out. **86 of ~111 items ported**` and append `76, 79, 80, 81, 82, 96` to the ported list and `78, 106` to the consolidated list.

- [ ] **Step 2: Update the Common User Issues table rows** for 76, 78, 79, 80, 81, 82, 96, 106:

| v8 # | new Status | v9 Id |
|---|---|---|
| 76 | `ported (batch 6a)` | `outlook-search-repair` |
| 78 | `consolidated -> tool 79 (m365-auth-reset)` | — |
| 79 | `ported (batch 6a)` | `m365-auth-reset` |
| 80 | `ported (batch 6a)` | `autodiscover-fix` |
| 81 | `ported (batch 6a)` | `outlook-ost-rebuild` |
| 82 | `ported (batch 6a)` | `outlook-profile-repair` |
| 96 | `ported (batch 6a)` | `outlook-addin-repair` |
| 106 | `consolidated -> tool 76 (outlook-search-repair)` | — |

- [ ] **Step 3: Update the known-consolidation-candidates note** — mark the `76 / 106` line resolved: `[resolved batch 6a: 106 consolidated -> 76]`.

- [ ] **Step 4: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "docs(6a): parity checklist - 86 tools, batch 6 complete"
```

---

## Self-Review (controller, after all tasks)

- **Spec coverage:** six tool files (76, 79, 80, 81, 82, 96) + two consolidations (78 into m365-auth-reset, 106 into outlook-search-repair) — all present. Each report-then-action arm and honesty rule in the spec maps to a `switch`/`if` branch above.
- **Type/name consistency:** every `New-ToolRun -Id '<id>'` literal matches its registry `Id` and the file's function name matches the registry `Function`. `Stop-OutlookGraceful` is defined in each of the three tool files that close Outlook (search, ost, profile) as a function-local helper — intentional, not a duplicate-symbol bug.
- **Status enum:** no `Complete-ToolRun -Status Error` anywhere (only `Success|Failed|Warning|Skipped`); `Error` appears only as a `Write-ToolOutput -Level`.
- **Approved verbs:** Repair / Reset / Get / Stop / Test — all approved.

## Final review + finish

After Task 7, dispatch a whole-batch reviewer (constrained `general-purpose`: "output ONLY your review; do not modify files/memory/commit") over the six new tool files + registry diff, fix anything it flags, then use **superpowers:finishing-a-development-branch** to merge `batch-6a-outlook-m365` to master locally (single-line `-m` merge message).
