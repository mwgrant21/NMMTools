# Porting Batch 6C: Shell & UI Tools - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 "Common User Issues" shell/UI tools 54, 55, 57, 59 into v9 as four report-then-action tools in a new Category 'User'.

**Architecture:** Each v8 numbered sub-menu becomes one v9 tool: a read-only report (the v8 "show status" option) followed by `Read-ToolChoice -Choices @('None', <actions>) -Default 'None' -Silent:$Silent`. Destructive sub-actions get a typed CONFIRM or a Yes/No (Default No) gate. GUI-launch actions are kept as interactive choices (no-op under -Silent). No new core helper - each tool is self-contained.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs\superpowers\specs\2026-06-13-batch-6c-shell-ui-design.md`.

**v8 reference (READ-ONLY):** `C:\Users\IT\Desktop\NMMTools.ps1` - `Reset-WindowsSearch` L6517, `Repair-StartMenuTaskbar` L6733, `Reset-WindowsExplorer` L7254, `Reset-FileAssociations` L7933.

---

## Standing rules (carried from batches 1-5)

- PS 5.1: no ternary / `??` / `&&`; never assign `$input`, `$matches`, or `$profile`.
- **ASCII-only source** (the encoding test fails the build on non-ASCII). UTF-8 BOM + trailing newline.
- Tools use `Write-ToolOutput` / `Read-ToolChoice` only - never `Write-Host`/`Read-Host`.
- Every tool function: approved verb, `[switch]$Silent` param, calls `New-ToolRun` + `Complete-ToolRun`, and its `New-ToolRun -Id` literal MUST equal its registry `Id`.
- `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`.
- One tool file per registered function in `src\tools\user\`; one registry entry each (the registry-mapping test requires the pairing, so add BOTH together in each task).

## Registry entries (added per task)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable |
|---|---|---|---|---|---|---|---|
| windows-search-rebuild | 54 | Windows Search Rebuild | Reset-WindowsSearch | User | $true | Modifies | $true |
| start-menu-taskbar | 55 | Start Menu and Taskbar Repair | Repair-StartMenuTaskbar | User | $false | Modifies | $true |
| windows-explorer-reset | 57 | Windows Explorer Reset | Reset-WindowsExplorer | User | $false | Modifies | $true |
| default-apps | 59 | Default Apps and File Types | Set-DefaultApps | User | $false | Modifies | $true |

New Category 'User'. Tool count **66 -> 70**. Menu becomes 6 categories alphabetical: A=Browser B=Cloud C=Diagnostics D=Laptop E=Repair F=User. (Categories are derived from the registry - no menu code change needed.)

## Smoke safety (non-elevated dev session)

- `start-menu-taskbar -Silent`, `windows-explorer-reset -Silent`, `default-apps -Silent` -> action menu defaults to **None** -> report only, exit 0. SAFE. Quote the summary.
- `windows-search-rebuild -Silent` -> RequiresAdmin -> dispatcher refuses non-elevated (Refused / exit 1). Quote.
- NEVER execute the destructive actions (RebuildIndex, ResetStartLayout, ReRegisterStartMenu, ClearExplorerCache, RebuildIconCache) or any explorer restart / GUI launch in the dev session. Verify those by READING the code + the silent report.

---

## Setup: create the batch branch

- [ ] **Step 1: Branch off master**

Run:
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" checkout -b port/batch-6c-shell-ui
```
Expected: `Switched to a new branch 'port/batch-6c-shell-ui'`

---

## Task 1: windows-search-rebuild (54)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry to the Tools array)
- Create: `src\tools\user\Reset-WindowsSearch.ps1`

- [ ] **Step 1: Append the registry entry** as the LAST element of the `Tools = @( ... )` array in `src\registry\tools.psd1` (immediately before the array's closing `)`):
```powershell
        @{
            Id            = 'windows-search-rebuild'
            LegacyId      = '54'
            Name          = 'Windows Search Rebuild'
            Category      = 'User'
            Function      = 'Reset-WindowsSearch'
            Description   = 'Restart the Windows Search service, rebuild the search index, or open Indexing Options'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('search','wsearch','index','cortana')
        }
```

- [ ] **Step 2: Create `src\tools\user\Reset-WindowsSearch.ps1`** with EXACTLY this content:
```powershell
function Reset-WindowsSearch {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-search-rebuild'

        # --- Report ---
        $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-ToolOutput 'Windows Search service (WSearch) not found on this machine.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'WSearch service not present'
            return
        }
        Write-ToolOutput ('Windows Search service: Status={0}  StartType={1}' -f $svc.Status, $svc.StartType) -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Windows Search action' `
            -Choices @('None','RestartService','RebuildIndex','OpenIndexingOptions') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartService' {
                Write-ToolOutput 'Restarting WSearch...' -Level Info
                Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $now = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status
                Write-ToolOutput ('WSearch status: {0}' -f $now) -Level Detail
                if ($now -eq 'Running') {
                    Complete-ToolRun $run -Status Success -Summary 'WSearch restarted (Running)'
                } else {
                    Complete-ToolRun $run -Status Warning -Summary ('WSearch restart left status {0}' -f $now)
                }
            }

            'RebuildIndex' {
                Write-ToolOutput 'WARNING: this clears the search index; Windows rebuilds it in the background (can take 1-2 hours).' -Level Warning
                $gate = Read-ToolChoice -Prompt 'Type CONFIRM to clear and rebuild the search index' `
                    -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
                if ($gate -ne 'CONFIRM') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RebuildIndex cancelled (no CONFIRM)'
                } else {
                    Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    $dataDir = Join-Path $env:ProgramData 'Microsoft\Search\Data'
                    if (Test-Path -LiteralPath $dataDir) {
                        Get-ChildItem -LiteralPath $dataDir -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                    Write-ToolOutput 'Search index cleared; rebuild runs in the background.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Search index cleared; background rebuild started'
                }
            }

            'OpenIndexingOptions' {
                Start-Process 'control.exe' -ArgumentList 'srchadmin.dll' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Indexing Options opened. Use Advanced -> Rebuild to rebuild the index.' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened Indexing Options (manual rebuild)'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('WSearch reported ({0}); no action taken' -f $svc.Status)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite**
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: build prints `Built ...`; suite `Failed: 0` (71 passed). Template gates check verb `Reset` (approved), `[switch]$Silent`, and `New-ToolRun -Id 'windows-search-rebuild'` matching the registry Id.

- [ ] **Step 4: Smoke the admin refusal (RequiresAdmin under non-elevated -Silent)**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $false
. "$r\src\tools\user\Reset-WindowsSearch.ps1"
$tool = Resolve-NmmTool -Query 'windows-search-rebuild'
Write-Output ("RESULT: " + (Invoke-NmmTool -Tool $tool -Silent))
```
Expected: `RESULT: Refused` (RequiresAdmin + not elevated). Paste that line.

- [ ] **Step 5: Commit**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Reset-WindowsSearch.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port shell batch 6c.1 (windows-search-rebuild)"
```

---

## Task 2: start-menu-taskbar (55)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-StartMenuTaskbar.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'start-menu-taskbar'
            LegacyId      = '55'
            Name          = 'Start Menu and Taskbar Repair'
            Category      = 'User'
            Function      = 'Repair-StartMenuTaskbar'
            Description   = 'Restart Explorer, reset the Start Menu layout, or re-register the Start Menu app for the current user'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('startmenu','taskbar','explorer','shell')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-StartMenuTaskbar.ps1`** with EXACTLY this content:
```powershell
function Repair-StartMenuTaskbar {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'start-menu-taskbar'

        # --- Report ---
        $explorer = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        Write-ToolOutput ('explorer.exe running: {0}' -f ($explorer.Count -gt 0)) -Level Info
        $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($os) { Write-ToolOutput ('OS: {0}' -f $os) -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Start Menu / Taskbar action' `
            -Choices @('None','RestartExplorer','ResetStartLayout','ReRegisterStartMenu') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartExplorer' {
                Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Process 'explorer.exe'
                Start-Sleep -Seconds 2
                Write-ToolOutput 'Explorer restarted.' -Level Success
                Complete-ToolRun $run -Status Success -Summary 'Explorer restarted'
            }

            'ResetStartLayout' {
                $confirm = Read-ToolChoice -Prompt 'Reset the Start Menu layout (current layout will be cleared)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ResetStartLayout cancelled'
                } else {
                    $shell = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'
                    $backup = Join-Path $env:TEMP ('StartMenu_Backup_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                    if (Test-Path -LiteralPath $shell) {
                        Copy-Item -LiteralPath $shell -Destination $backup -Recurse -ErrorAction SilentlyContinue
                        Write-ToolOutput ('Backed up layout to {0}' -f $backup) -Level Detail
                    }
                    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $caches = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches'
                    if (Test-Path -LiteralPath $caches) {
                        Get-ChildItem -LiteralPath $caches -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    $layoutXml = Join-Path $shell 'LayoutModification.xml'
                    if (Test-Path -LiteralPath $layoutXml) { Remove-Item -LiteralPath $layoutXml -Force -ErrorAction SilentlyContinue }
                    Start-Process 'explorer.exe'
                    Start-Sleep -Seconds 2
                    Write-ToolOutput 'Start layout reset; explorer restarted.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary ('Start layout reset (backup: {0})' -f $backup)
                }
            }

            'ReRegisterStartMenu' {
                $confirm = Read-ToolChoice -Prompt 'Re-register the Start Menu app for the current user (can take a minute)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ReRegisterStartMenu cancelled'
                } else {
                    Write-ToolOutput 'Re-registering StartMenuExperienceHost...' -Level Info
                    $ok = 0
                    $fail = 0
                    Get-AppxPackage -Name 'Microsoft.Windows.StartMenuExperienceHost' -ErrorAction SilentlyContinue | ForEach-Object {
                        $manifest = Join-Path $_.InstallLocation 'AppXManifest.xml'
                        try {
                            Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                            $ok++
                        } catch {
                            $fail++
                        }
                    }
                    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    Start-Process 'explorer.exe'
                    Start-Sleep -Seconds 2
                    if ($fail -gt 0) {
                        Complete-ToolRun $run -Status Warning -Summary ('Start Menu re-register: {0} ok, {1} failed' -f $ok, $fail)
                    } else {
                        Complete-ToolRun $run -Status Success -Summary ('Start Menu re-registered ({0} package)' -f $ok)
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Start Menu / Taskbar reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same commands as Task 1 Step 3). Expected: `Failed: 0`.

- [ ] **Step 4: Smoke the silent report-only path**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
. "$r\src\tools\user\Repair-StartMenuTaskbar.ps1"
Set-OutputSink -Sink Silent
Repair-StartMenuTaskbar -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: `start-menu-taskbar: Success - Start Menu / Taskbar reported; no action taken`. NO explorer restart occurs (None default). Paste the run-record line.

- [ ] **Step 5: Commit**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-StartMenuTaskbar.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port shell batch 6c.2 (start-menu-taskbar)"
```

---

## Task 3: windows-explorer-reset (57)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Reset-WindowsExplorer.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'windows-explorer-reset'
            LegacyId      = '57'
            Name          = 'Windows Explorer Reset'
            Category      = 'User'
            Function      = 'Reset-WindowsExplorer'
            Description   = 'Restart Explorer, clear thumbnail/Recent/jump-list caches, or rebuild the icon cache'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('explorer','shell','thumbnail','iconcache')
        }
```

- [ ] **Step 2: Create `src\tools\user\Reset-WindowsExplorer.ps1`** with EXACTLY this content:
```powershell
function Reset-WindowsExplorer {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-explorer-reset'

        # --- Report ---
        $explorer = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        Write-ToolOutput ('explorer.exe running: {0}' -f ($explorer.Count -gt 0)) -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Explorer action' `
            -Choices @('None','RestartExplorer','ClearExplorerCache','RebuildIconCache') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartExplorer' {
                Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Process 'explorer.exe'
                Start-Sleep -Seconds 2
                Write-ToolOutput 'Explorer restarted.' -Level Success
                Complete-ToolRun $run -Status Success -Summary 'Explorer restarted'
            }

            'ClearExplorerCache' {
                $confirm = Read-ToolChoice -Prompt 'Clear thumbnails, Recent files, and jump lists?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearExplorerCache cancelled'
                } else {
                    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
                    if (Test-Path -LiteralPath $explorerDir) {
                        Get-ChildItem -LiteralPath $explorerDir -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
                    foreach ($sub in @('', 'AutomaticDestinations', 'CustomDestinations')) {
                        if ($sub) { $path = Join-Path $recent $sub } else { $path = $recent }
                        if (Test-Path -LiteralPath $path) {
                            Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue |
                                Where-Object { -not $_.PSIsContainer } |
                                Remove-Item -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Start-Process 'explorer.exe'
                    Start-Sleep -Seconds 2
                    Write-ToolOutput 'Explorer cache cleared; explorer restarted.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Cleared thumbnails, Recent, and jump lists'
                }
            }

            'RebuildIconCache' {
                $confirm = Read-ToolChoice -Prompt 'Rebuild the icon cache (deletes IconCache; explorer restarts)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RebuildIconCache cancelled'
                } else {
                    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
                    if (Test-Path -LiteralPath $explorerDir) {
                        Get-ChildItem -LiteralPath $explorerDir -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    $iconDb = Join-Path $env:LOCALAPPDATA 'IconCache.db'
                    if (Test-Path -LiteralPath $iconDb) { Remove-Item -LiteralPath $iconDb -Force -ErrorAction SilentlyContinue }
                    Start-Process 'explorer.exe'
                    Start-Sleep -Seconds 2
                    Write-ToolOutput 'Icon cache deleted; explorer restarted (icons regenerate over a few minutes).' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Icon cache rebuilt'
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Explorer reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`.

- [ ] **Step 4: Smoke the silent report-only path**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
. "$r\src\tools\user\Reset-WindowsExplorer.ps1"
Set-OutputSink -Sink Silent
Reset-WindowsExplorer -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: `windows-explorer-reset: Success - Explorer reported; no action taken`. NO explorer restart / cache deletion. Paste the run-record line.

- [ ] **Step 5: Commit**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Reset-WindowsExplorer.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port shell batch 6c.3 (windows-explorer-reset)"
```

---

## Task 4: default-apps (59)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Set-DefaultApps.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'default-apps'
            LegacyId      = '59'
            Name          = 'Default Apps and File Types'
            Category      = 'User'
            Function      = 'Set-DefaultApps'
            Description   = 'Report current file-type associations and open Default Apps settings (Windows protects per-user defaults; per-type changes are made in Settings)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('defaultapps','fileassociation','fta','settings')
        }
```

- [ ] **Step 2: Create `src\tools\user\Set-DefaultApps.ps1`** with EXACTLY this content:
```powershell
function Set-DefaultApps {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'default-apps'

        # --- Report: current associations for common types (read-only) ---
        Write-ToolOutput 'Current file associations (common types):' -Level Info
        $exts = @('.txt','.pdf','.jpg','.png','.docx','.xlsx','.html','.zip','.mp4')
        foreach ($ext in $exts) {
            $assoc = $null
            try { $assoc = (cmd /c ('assoc {0}' -f $ext) 2>$null) } catch { $assoc = $null }
            if ($assoc) {
                Write-ToolOutput ('  {0}' -f ($assoc -join ' ')) -Level Detail
            } else {
                Write-ToolOutput ('  {0} = (none)' -f $ext) -Level Detail
            }
        }
        Write-ToolOutput 'Note: Windows 10/11 protect the per-user default-app choice; per-type changes must be made in Settings.' -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Default apps action' `
            -Choices @('None','OpenDefaultApps') -Default 'None' -Silent:$Silent

        switch ($action) {

            'OpenDefaultApps' {
                Start-Process 'ms-settings:defaultapps' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Default Apps settings opened. Set per-type and per-protocol defaults there.' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened Default Apps settings'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Reported current associations; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`. Template gate checks verb `Set` (approved).

- [ ] **Step 4: Smoke the silent report-only path**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
. "$r\src\tools\user\Set-DefaultApps.ps1"
Set-OutputSink -Sink Silent
Set-DefaultApps -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: prints the common-type associations, then `default-apps: Success - Reported current associations; no action taken`. NO settings window opens (None default). Paste the run-record line.

- [ ] **Step 5: Commit**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Set-DefaultApps.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port shell batch 6c.4 (default-apps)"
```

---

## Task 5: Sub-batch 6C close-out

**Files:**
- Modify: `docs\parity-checklist.md`

- [ ] **Step 1: Verify 70 tools and the new User category**
```powershell
$lines = (& "$env:USERPROFILE\Desktop\NMMToolkit\dist\NMMTools.ps1" -ListTools | Out-String) -split "`r?`n"
$toolRows = $lines | Where-Object { $_ -match '\s(Browser|Cloud|Diagnostics|Laptop|Repair|User)\s+(ReadOnly|Modifies|Disruptive)\s' }
Write-Output ("Total tool rows: {0}" -f $toolRows.Count)
'Browser','Cloud','Diagnostics','Laptop','Repair','User' | ForEach-Object {
  $cat = $_
  '{0,-12} {1}' -f $cat, ($toolRows | Where-Object { $_ -match ('\s{0}\s+(ReadOnly|Modifies|Disruptive)\s' -f $cat) }).Count
}
```
Expected: Total = **70**; User = **4** (windows-search-rebuild, start-menu-taskbar, windows-explorer-reset, default-apps); Browser 2, Cloud 8, Diagnostics 23, Laptop 17, Repair 16. Quote the User rows.

- [ ] **Step 2: Confirm build + full suite are green**
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: Build OK; `Failed: 0`.

- [ ] **Step 3: Update the parity checklist** in `docs\parity-checklist.md`:

(a) In the Common User Issues table, update the four ported rows and the 61 consolidation. Find the rows for 54, 55, 57, 59 (and 61) and set:
```markdown
| 54 | Windows Search Rebuild | ported (batch 6c) | windows-search-rebuild |
| 55 | Start Menu & Taskbar Repair | ported (batch 6c) | start-menu-taskbar |
| 57 | Windows Explorer Reset | ported (batch 6c) | windows-explorer-reset |
| 59 | Default Apps & File Types | ported (batch 6c) | default-apps |
| 61 | Display & Monitor Config | consolidated -> tools 44 + 73 | — |
```
(b) Update the header count line near the top from `66 of ~111 items ported` to `70 of ~111 items ported` and add `, 54, 55, 57, 59` to the ported-items list (and note 61 consolidated).

- [ ] **Step 4: Commit the docs**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add docs/parity-checklist.md
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "docs: batch 6c complete - parity checklist (70/106 ported)"
```

- [ ] **Step 5: Final review + finish the branch**

Review focus: each tool's destructive actions are gated (RebuildIndex typed CONFIRM; ResetStartLayout/ReRegisterStartMenu/ClearExplorerCache/RebuildIconCache Yes-No Default-No); all removals are scoped to explicit user/ProgramData paths (never a drive root); windows-search-rebuild is admin-gated; -Silent on all four is a safe no-op (report only, or Refused for the admin tool); default-apps description is honest about the GUI requirement.

Then invoke the **superpowers:finishing-a-development-branch** skill to merge `port/batch-6c-shell-ui` to master (verify suite on the merged result before deleting the branch).

---

## Self-review (completed by plan author)

- **Spec coverage:** 4 tools (54/55/57/59) -> Tasks 1-4; tool 61 consolidation -> Task 5 Step 3 parity update; new Category 'User' -> all four registry entries; report-then-action with None default -> every tool's action menu; GUI-launch kept -> OpenIndexingOptions (T1), OpenDefaultApps (T4); honest default-apps -> T4 report + note; admin gating -> windows-search-rebuild RequiresAdmin $true + T1 Step 4 refusal smoke; destructive gates -> typed CONFIRM (RebuildIndex) + Yes/No Default-No (others); 70-tool/6-category verify -> T5 Step 1; testing/smoke matrix -> per-task Step 3/4.
- **Placeholder scan:** none - every step has complete code, exact commands, and expected output.
- **Type/name consistency:** registry Function names (`Reset-WindowsSearch`, `Repair-StartMenuTaskbar`, `Reset-WindowsExplorer`, `Set-DefaultApps`) match the defined functions and the `New-ToolRun -Id` literals match each registry `Id` (`windows-search-rebuild`, `start-menu-taskbar`, `windows-explorer-reset`, `default-apps`). All four use approved verbs (Reset/Repair/Set) and declare `[switch]$Silent`.
