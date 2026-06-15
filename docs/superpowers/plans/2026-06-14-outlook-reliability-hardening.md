# Outlook Reliability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance two existing tools with durable fixes - pin the OnBase/Hyland Outlook add-in so Outlook's "slows down Outlook" disabling can't touch it (`outlook-addin-repair`), and add a search config diagnose + fix before the rebuild (`outlook-search-repair`).

**Architecture:** Edit two existing tool functions in `src/tools/user/` and update their two registry descriptions. No new tools (registry stays 100), no new tests (the project has no per-tool unit tests; correctness is gated by the template/registry/encoding/build suite + review).

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs/superpowers/specs/2026-06-14-outlook-reliability-hardening-design.md`

---

## Conventions

- PS 5.1 only; approved verbs; never assign `$input`/`$matches`/`$profile`. ASCII-only source, UTF-8 **with BOM**, trailing newline. `New-ToolRun -Id` literals unchanged.
- Registry writes use `New-ItemProperty -Force` (creates-or-overwrites with the right type): REG_SZ `'1'` via `-PropertyType String` for `AddinList\<ProgID>`; DWORD `1` via `-PropertyType DWord` for `DisablePromptOnLoadTimeDisable`.
- `Complete-ToolRun -Status` only `Success|Failed|Warning|Skipped`.
- Build + test after each task:
  ```powershell
  Import-Module Pester -MinimumVersion 5.0
  & "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
  Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
  ```
  Expected: build succeeds, all tests pass, registry still reports 100 tools.
- Single-line `-m` commits.

## File Structure

- Modify (full rewrite of the function): `src/tools/user/Repair-OutlookAddins.ps1` (Task 1)
- Modify (full rewrite of the function): `src/tools/user/Repair-OutlookSearch.ps1` (Task 2)
- Modify (two Description lines): `src/registry/tools.psd1` (one line in each task)

---

### Task 1: outlook-addin-repair - add PinOnBase

**Files:**
- Modify: `src/tools/user/Repair-OutlookAddins.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Replace the ENTIRE file** `src/tools/user/Repair-OutlookAddins.ps1` with exactly this content:

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
        $resiliencyRoot  = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
        $disabledKey     = Join-Path $resiliencyRoot 'DisabledItems'
        $crashKey        = Join-Path $resiliencyRoot 'CrashingAddinList'
        $doNotDisable    = Join-Path $resiliencyRoot 'DoNotDisableAddinList'
        $policyRoot      = 'HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Resiliency'
        $policyAddinList = Join-Path $policyRoot 'AddinList'

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

        # Durable-pin (policy) state.
        $promptSuppressed = $false
        if (Test-Path -LiteralPath $policyRoot) {
            $promptSuppressed = (Get-ItemProperty -LiteralPath $policyRoot -Name 'DisablePromptOnLoadTimeDisable' -ErrorAction SilentlyContinue).DisablePromptOnLoadTimeDisable -eq 1
        }
        $onbasePinned = $false
        if ($onbase.Count -gt 0 -and (Test-Path -LiteralPath $policyAddinList)) {
            $alProps = Get-ItemProperty -LiteralPath $policyAddinList -ErrorAction SilentlyContinue
            $onbasePinned = $true
            foreach ($o in $onbase) {
                $val = $null
                if ($alProps -and ($alProps.PSObject.Properties.Name -contains $o.Name)) { $val = [string]$alProps.$($o.Name) }
                if ($val -ne '1') { $onbasePinned = $false }
            }
        }
        if ($onbase.Count -gt 0) {
            Write-ToolOutput ('OnBase pinned (policy AddinList=1): {0}; slow-add-in prompt suppressed: {1}' -f $onbasePinned, $promptSuppressed) -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook add-in repair' -Choices @('None','ReEnable','PinOnBase') -Default 'None' -Silent:$Silent

        if ($action -eq 'ReEnable') {
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
            return
        }

        if ($action -eq 'PinOnBase') {
            if ($onbase.Count -eq 0) {
                Complete-ToolRun $run -Status Warning -Summary 'No OnBase/Hyland add-in found to pin'
                return
            }
            # Un-stick now: clear the soft resiliency lists and re-enable any HKCU OnBase registration.
            if (Test-Path -LiteralPath $disabledKey) { Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $crashKey)    { Remove-Item -LiteralPath $crashKey -Recurse -Force -ErrorAction SilentlyContinue }
            foreach ($o in $onbase) {
                if ($o.Hive -eq 'HKCU' -and $o.LoadBehavior -ne 3) {
                    Set-ItemProperty -LiteralPath $o.PSPath -Name 'LoadBehavior' -Value 3 -ErrorAction SilentlyContinue
                }
            }
            # Pin durably via the policy hive (per-user; works regardless of where OnBase is registered).
            if (-not (Test-Path -LiteralPath $policyRoot)) { New-Item -Path $policyRoot -Force -ErrorAction SilentlyContinue | Out-Null }
            New-ItemProperty -LiteralPath $policyRoot -Name 'DisablePromptOnLoadTimeDisable' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            if (-not (Test-Path -LiteralPath $policyAddinList)) { New-Item -Path $policyAddinList -Force -ErrorAction SilentlyContinue | Out-Null }
            foreach ($o in $onbase) {
                New-ItemProperty -LiteralPath $policyAddinList -Name $o.Name -Value '1' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            # Verify the pin took.
            $verified = 0
            $alProps2 = Get-ItemProperty -LiteralPath $policyAddinList -ErrorAction SilentlyContinue
            foreach ($o in $onbase) {
                if ($alProps2 -and ($alProps2.PSObject.Properties.Name -contains $o.Name) -and ([string]$alProps2.$($o.Name) -eq '1')) { $verified++ }
            }
            if ($verified -eq $onbase.Count) {
                Complete-ToolRun $run -Status Success -Summary ('Pinned {0} OnBase/Hyland add-in(s) as always-enabled (policy); Outlook will no longer disable them for slow load time' -f $verified)
            } else {
                Complete-ToolRun $run -Status Warning -Summary ('Pin incomplete: {0} of {1} OnBase add-in(s) verified in the policy AddinList' -f $verified, $onbase.Count)
            }
            return
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} add-in(s) reported; no action taken' -f $addins.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Update the registry Description** for `outlook-addin-repair` in `src/registry/tools.psd1`. First Read the entry to get the exact current `Description = '...'` line, then replace that one line with:

```powershell
            Description   = 'Report Outlook add-ins, Resiliency disabled/crashing lists, and the OnBase pin state; then re-enable disabled add-ins (LoadBehavior 3), or permanently pin the OnBase/Hyland add-in via policy so Outlook stops disabling it for "slowing down Outlook"'
```

- [ ] **Step 3: Fix encoding** on the edited tool file:

```powershell
$f = "$env:USERPROFILE\Desktop\NMMToolkit\src\tools\user\Repair-OutlookAddins.ps1"
$txt = (Get-Content -LiteralPath $f -Raw) -replace "`r`n","`n" -replace "`n","`r`n"
if ($txt[-1] -ne "`n") { $txt += "`r`n" }
[System.IO.File]::WriteAllText($f, $txt, (New-Object System.Text.UTF8Encoding($true)))
```

- [ ] **Step 4: Build and test.**

```powershell
Import-Module Pester -MinimumVersion 5.0
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```

Expected: build succeeds; all tests pass; registry still 100 tools.

- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(outlook): pin OnBase add-in via policy so Outlook stops disabling it (outlook-addin-repair PinOnBase)"
```

---

### Task 2: outlook-search-repair - diagnose + FixConfig

**Files:**
- Modify: `src/tools/user/Repair-OutlookSearch.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Replace the ENTIRE file** `src/tools/user/Repair-OutlookSearch.ps1` with exactly this content:

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
        $searchPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
        $searchSetupKey  = 'HKLM:\SOFTWARE\Microsoft\Windows Search'

        # --- Report ---
        $ws = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if ($ws) {
            $wsLevel = 'Info'
            if ("$($ws.StartType)" -notlike 'Automatic*') { $wsLevel = 'Warning' }
            Write-ToolOutput ('Windows Search (WSearch): {0} (StartType {1})' -f $ws.Status, $ws.StartType) -Level $wsLevel
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
        $catalogRegistered = $false
        if (Test-Path -LiteralPath $catalogKey) {
            $catalogRegistered = $null -ne (Get-ItemProperty -LiteralPath $catalogKey -Name 'Catalog' -ErrorAction SilentlyContinue)
        }
        Write-ToolOutput ('Outlook search catalog registered: {0}' -f $catalogRegistered) -Level Detail

        # Config diagnosis (the usual recurring-breakage causes).
        $preventOutlook = 0
        if (Test-Path -LiteralPath $searchPolicyKey) {
            $pv = (Get-ItemProperty -LiteralPath $searchPolicyKey -Name 'PreventIndexingOutlook' -ErrorAction SilentlyContinue).PreventIndexingOutlook
            if ($pv) { $preventOutlook = [int]$pv }
        }
        if ($preventOutlook -eq 1) {
            Write-ToolOutput 'PreventIndexingOutlook policy is ENABLED - Outlook indexing is disabled by policy.' -Level Warning
        } else {
            Write-ToolOutput 'PreventIndexingOutlook policy: not set (Outlook indexing allowed).' -Level Detail
        }
        $setupOk = (Get-ItemProperty -LiteralPath $searchSetupKey -Name 'SetupCompletedSuccessfully' -ErrorAction SilentlyContinue).SetupCompletedSuccessfully
        Write-ToolOutput ('Windows Search SetupCompletedSuccessfully: {0}' -f $setupOk) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook search repair' `
            -Choices @('None','FixConfig','RestartService','RebuildIndex') -Default 'None' -Silent:$Silent

        switch ($action) {

            'FixConfig' {
                $changes = New-Object System.Collections.Generic.List[string]
                $wnow = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                if ($wnow -and ("$($wnow.StartType)" -eq 'Disabled' -or "$($wnow.StartType)" -eq 'Manual')) {
                    Set-Service -Name 'WSearch' -StartupType Automatic -ErrorAction SilentlyContinue
                    Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                    $changes.Add('WSearch set to Automatic and started')
                }
                $gpoCaveat = $false
                if ($preventOutlook -eq 1) {
                    Set-ItemProperty -LiteralPath $searchPolicyKey -Name 'PreventIndexingOutlook' -Value 0 -ErrorAction SilentlyContinue
                    $recheck = (Get-ItemProperty -LiteralPath $searchPolicyKey -Name 'PreventIndexingOutlook' -ErrorAction SilentlyContinue).PreventIndexingOutlook
                    if ([int]$recheck -eq 0) {
                        $changes.Add('PreventIndexingOutlook policy cleared')
                        Write-ToolOutput 'Cleared PreventIndexingOutlook. If it returns after a gpupdate, it is set by Group Policy - fix the GPO; the toolkit cannot override a domain policy.' -Level Warning
                    } else {
                        $gpoCaveat = $true
                        Write-ToolOutput 'PreventIndexingOutlook could not be cleared (still 1) - it is enforced by Group Policy. Fix the GPO.' -Level Error
                    }
                }
                $wfin = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                $wstart = 'Unknown'
                if ($wfin) { $wstart = "$($wfin.StartType)" }
                if ($changes.Count -eq 0) {
                    Complete-ToolRun $run -Status Success -Summary 'Search config already healthy; no changes needed (run RebuildIndex if search is still broken)'
                } elseif ($gpoCaveat) {
                    Complete-ToolRun $run -Status Warning -Summary ('Applied: {0}; PreventIndexingOutlook is GPO-enforced - fix the GPO' -f ($changes -join '; '))
                } else {
                    Complete-ToolRun $run -Status Success -Summary ('Search config fixed ({0}); WSearch StartType {1}. Run RebuildIndex if search is still broken.' -f ($changes -join '; '), $wstart)
                }
            }

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

- [ ] **Step 2: Update the registry Description** for `outlook-search-repair` in `src/registry/tools.psd1`. Read the entry to get the exact current `Description = '...'` line, then replace that one line with:

```powershell
            Description   = 'Report Windows Search/WSearch, index size, the Outlook catalog, and the PreventIndexingOutlook policy; then fix the search config (WSearch startup, PreventIndexingOutlook), restart WSearch, or rebuild the index (deletes Windows.edb); see also tool 54'
```

- [ ] **Step 3: Fix encoding** on the edited tool file:

```powershell
$f = "$env:USERPROFILE\Desktop\NMMToolkit\src\tools\user\Repair-OutlookSearch.ps1"
$txt = (Get-Content -LiteralPath $f -Raw) -replace "`r`n","`n" -replace "`n","`r`n"
if ($txt[-1] -ne "`n") { $txt += "`r`n" }
[System.IO.File]::WriteAllText($f, $txt, (New-Object System.Text.UTF8Encoding($true)))
```

- [ ] **Step 4: Build and test** (same commands as Task 1 Step 4). Expected: build succeeds; all tests pass; registry still 100 tools.

- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(outlook): search-repair diagnoses + FixConfig (WSearch startup, PreventIndexingOutlook) before rebuild"
```

---

## Self-Review (controller, after all tasks)

- **Spec coverage:** add-in PinOnBase (un-stick + policy `AddinList\<ProgID>='1'` REG_SZ + `DisablePromptOnLoadTimeDisable=1` DWORD, OnBase-targeted, verify, no-OnBase Warning) - Task 1; search deeper report (WSearch StartType flag, PreventIndexingOutlook, SetupCompletedSuccessfully) + FixConfig (WSearch->Automatic, clear local PreventIndexingOutlook with GPO caveat) - Task 2; both registry descriptions updated.
- **Unchanged arms preserved:** add-in `ReEnable` and search `RestartService`/`RebuildIndex`/`Stop-OutlookGraceful` are byte-identical to the current code.
- **Conventions:** `New-ToolRun -Id` literals unchanged; no `Complete-ToolRun -Status Error`; registry value types correct (String '1' / DWord 1); both tools keep their admin/Risk (addin $false/Modifies, search $true/Modifies); nested helpers stay function-local.
- **No new tools/tests;** registry stays 100; both edited files re-encoded.

## Final review + finish

After Task 2, dispatch a reviewer (constrained `general-purpose`: "output ONLY your review; do not modify files/memory/commit") over both tool diffs + the two registry descriptions (focus: registry paths/value types, `-Silent` no-op gating of PinOnBase/FixConfig, the no-OnBase and GPO-revert honesty, dynamic-property access `$alProps.$($o.Name)` on dotted ProgIDs, and that ReEnable/RestartService/RebuildIndex are unchanged), fix anything it flags, then use **superpowers:finishing-a-development-branch** to merge `outlook-reliability-hardening` to master locally (single-line `-m`).
