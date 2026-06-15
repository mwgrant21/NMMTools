# Batch 7 Part 2 (Quick Fixes Q1-Q9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 Quick Fixes Q1-Q9 into v9 as nine new `QuickFix`-category tools, each a self-contained abbreviated one-click workflow with a single upfront confirm.

**Architecture:** One tool = one file in a NEW `src/tools/quickfix/` folder defining one top-level `Invoke-*QuickFix` function, plus one entry in `src/registry/tools.psd1`. `build.ps1` recurses `src/tools`, so the new folder builds automatically; the landing menu letters categories alphabetically, so `QuickFix` auto-inserts (letter E) with no menu code change. Each tool: `New-ToolRun` -> describe steps -> ONE `Read-ToolChoice -Choices @('Yes','No') -Default 'No' -Silent:$Silent` gate -> run all steps -> honest `Complete-ToolRun`. Under `-Silent` the gate returns `No` -> `Skipped` no-op.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs/superpowers/specs/2026-06-14-batch-7-quickfixes-design.md`

---

## Conventions every task must follow

- **PS 5.1 only:** no ternary, `??`, `&&`/`||`. Never ASSIGN `$input`/`$matches`/`$profile` (reading `$Matches[1]` after `-match` is fine). Approved verbs only (`Invoke-` is approved).
- **`New-ToolRun -Id '<id>'`** literal MUST equal the registry `Id`.
- **Encoding:** ASCII-only source, UTF-8 **with BOM**, trailing newline. Write the file, then run the encoding fix (Task 1 Step 3).
- **Status enum:** `Complete-ToolRun -Status` accepts only `Success | Failed | Warning | Skipped`. `Write-ToolOutput -Level` accepts `Info | Success | Warning | Error | Detail`.
- **Q9 reuses CORE helpers** `Get-BrowserCatalog`, `Get-BrowserProfiles`, `Get-BrowserBackupRoot`, `Close-Browsers` (defined in `src/core/08-browser-helpers.ps1`; globally available in the built artifact; core funcs are NOT registry-scanned).
- **Build + test after every tool:**
  ```powershell
  Import-Module Pester -MinimumVersion 5.0
  & "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
  Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
  ```
  Expected: build succeeds, all tests green, registry/template counts rise by one each tool.
- **Commit message:** single-line `-m` only.

## File Structure

- Create: `src/tools/quickfix/Invoke-OfficeQuickFix.ps1` (Task 1)
- Create: `src/tools/quickfix/Invoke-OneDriveQuickFix.ps1` (Task 2)
- Create: `src/tools/quickfix/Invoke-TeamsQuickFix.ps1` (Task 3)
- Create: `src/tools/quickfix/Invoke-LoginQuickFix.ps1` (Task 4)
- Create: `src/tools/quickfix/Invoke-WiFiQuickFix.ps1` (Task 5)
- Create: `src/tools/quickfix/Invoke-VpnQuickFix.ps1` (Task 6)
- Create: `src/tools/quickfix/Invoke-AvPrepQuickFix.ps1` (Task 7)
- Create: `src/tools/quickfix/Invoke-DockingQuickFix.ps1` (Task 8)
- Create: `src/tools/quickfix/Invoke-BrowserBackupQuickFix.ps1` (Task 9)
- Modify: `src/registry/tools.psd1` — append one entry per tool, inserted before the closing `    )` that follows the LAST current entry (`rdp-config`).
- Modify: `docs/parity-checklist.md` (Task 10)

---

### Task 1: office-quick-fix (v8 Q1)

**Files:**
- Create: `src/tools/quickfix/Invoke-OfficeQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Invoke-OfficeQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'office-quick-fix'

        Write-ToolOutput 'Office quick fix will: close Office apps, clear Office sign-in credentials, and launch a Click-to-Run repair.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the Office quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Office quick fix declined'
            return
        }

        foreach ($name in @('OUTLOOK','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS')) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }

        $cleared = 0
        foreach ($line in (cmdkey /list 2>$null)) {
            if ($line -match '^\s*Target:\s*(.+?)\s*$') {
                $t = $Matches[1]
                if ($t -match 'MicrosoftOffice') {
                    cmdkey /delete:$t 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { $cleared++ }
                }
            }
        }

        $c2r = 'C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'
        $repairLaunched = $false
        if (Test-Path -LiteralPath $c2r) {
            Start-Process -FilePath $c2r -ArgumentList '/update user' -ErrorAction SilentlyContinue
            $repairLaunched = $true
        }

        Complete-ToolRun $run -Status Success -Summary ('Office apps closed, {0} credential(s) cleared, C2R repair launched={1}' -f $cleared, $repairLaunched)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** in `src/registry/tools.psd1`, immediately after the `rdp-config` entry's closing `}` and before the closing `    )`:

```powershell
        @{
            Id            = 'office-quick-fix'
            LegacyId      = 'Q1'
            Name          = 'Quick Fix: Office Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-OfficeQuickFix'
            Description   = 'One-click Office fix: close Office apps, clear Office sign-in credentials, and launch a Click-to-Run repair; see also office-repair'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','office','m365','credentials')
        }
```

- [ ] **Step 3: Fix encoding** (BOM + CRLF + trailing newline). Run:

```powershell
$f = "$env:USERPROFILE\Desktop\NMMToolkit\src\tools\quickfix\Invoke-OfficeQuickFix.ps1"
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

Expected: build succeeds; all tests pass; registry reports 92 tools; a new `E=QuickFix` category appears in `-ListTools`.

- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): office-quick-fix (port v8 Q1)"
```

---

### Task 2: onedrive-quick-fix (v8 Q2)

**Files:**
- Create: `src/tools/quickfix/Invoke-OneDriveQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Invoke-OneDriveQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'onedrive-quick-fix'

        $candidates = @(
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
            "$env:PROGRAMFILES\Microsoft OneDrive\OneDrive.exe",
            "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
        )
        $exe = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

        Write-ToolOutput 'OneDrive quick fix will: stop OneDrive, reset it (/reset), and restart it.' -Level Info
        if (-not $exe) {
            Write-ToolOutput 'OneDrive.exe not found at the expected paths.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'OneDrive not installed at expected paths; nothing done'
            return
        }
        $go = Read-ToolChoice -Prompt 'Proceed with the OneDrive reset?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'OneDrive quick fix declined'
            return
        }

        Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process -FilePath $exe -ArgumentList '/reset' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Start-Process -FilePath $exe -ErrorAction SilentlyContinue

        Complete-ToolRun $run -Status Success -Summary 'OneDrive reset and restarted'
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `office-quick-fix`, before the closing `    )`):

```powershell
        @{
            Id            = 'onedrive-quick-fix'
            LegacyId      = 'Q2'
            Name          = 'Quick Fix: OneDrive Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-OneDriveQuickFix'
            Description   = 'One-click OneDrive fix: stop OneDrive, reset it (/reset), and restart it; see also onedrive-repair'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','onedrive','sync','reset')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-OneDriveQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 93 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): onedrive-quick-fix (port v8 Q2)"
```

---

### Task 3: teams-quick-fix (v8 Q3)

**Files:**
- Create: `src/tools/quickfix/Invoke-TeamsQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Invoke-TeamsQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-quick-fix'

        Write-ToolOutput 'Teams quick fix will: close Teams (classic and new), clear the Teams cache, and restart Teams.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the Teams quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Teams quick fix declined'
            return
        }

        foreach ($name in @('Teams','ms-teams','MSTeams')) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2

        $cacheDirs = @(
            "$env:APPDATA\Microsoft\Teams\Cache",
            "$env:APPDATA\Microsoft\Teams\blob_storage",
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
        )
        $cleared = 0
        foreach ($dir in $cacheDirs) {
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $cleared++
            }
        }

        $classic = "$env:LOCALAPPDATA\Microsoft\Teams\Update.exe"
        if (Test-Path -LiteralPath $classic) {
            Start-Process -FilePath $classic -ArgumentList '--processStart Teams.exe' -ErrorAction SilentlyContinue
        } else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams' -ErrorAction SilentlyContinue
        }

        Complete-ToolRun $run -Status Success -Summary ('Teams closed; {0} cache location(s) cleared; Teams restarted' -f $cleared)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `onedrive-quick-fix`, before the closing `    )`):

```powershell
        @{
            Id            = 'teams-quick-fix'
            LegacyId      = 'Q3'
            Name          = 'Quick Fix: Teams Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-TeamsQuickFix'
            Description   = 'One-click Teams fix: close Teams (classic and new), clear the Teams cache, and restart Teams; see also teams-cache'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','teams','cache')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-TeamsQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 94 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): teams-quick-fix (port v8 Q3)"
```

---

### Task 4: login-quick-fix (v8 Q4)

**Files:**
- Create: `src/tools/quickfix/Invoke-LoginQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Invoke-LoginQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'login-quick-fix'

        Write-ToolOutput 'Login quick fix will: clear Office/M365 sign-in credentials and report the device join state. The user must sign in again afterward.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the login quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Login quick fix declined'
            return
        }

        $cleared = 0
        foreach ($line in (cmdkey /list 2>$null)) {
            if ($line -match '^\s*Target:\s*(.+?)\s*$') {
                $t = $Matches[1]
                if ($t -match 'MicrosoftOffice|Office') {
                    cmdkey /delete:$t 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { $cleared++ }
                }
            }
        }

        Write-ToolOutput 'Device join state:' -Level Detail
        foreach ($l in (dsregcmd /status 2>$null | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined')) {
            Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} Office credential(s) cleared; user should sign in again' -f $cleared)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `teams-quick-fix`, before the closing `    )`):

```powershell
        @{
            Id            = 'login-quick-fix'
            LegacyId      = 'Q4'
            Name          = 'Quick Fix: Login Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-LoginQuickFix'
            Description   = 'One-click login fix: clear Office/M365 sign-in credentials and report the device join state; see also credential-manager and m365-auth-reset'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','login','credentials','signin')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-LoginQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 95 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): login-quick-fix (port v8 Q4)"
```

---

### Task 5: wifi-quick-fix (v8 Q5)

**Files:**
- Create: `src/tools/quickfix/Invoke-WiFiQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Invoke-WiFiQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'wifi-quick-fix'

        Write-ToolOutput 'Wi-Fi quick fix will: restart the Wi-Fi adapter, release/renew the IP address, and flush DNS. Connectivity drops briefly.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the Wi-Fi quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Wi-Fi quick fix declined'
            return
        }

        $wifi = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*Wi-Fi*' -or $_.Name -like '*Wireless*' } | Select-Object -First 1
        $adapterReset = $false
        if ($wifi) {
            Restart-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction SilentlyContinue
            $adapterReset = $true
            Start-Sleep -Seconds 3
        } else {
            Write-ToolOutput 'No Wi-Fi/Wireless adapter found; skipping adapter reset.' -Level Warning
        }

        ipconfig /release 2>$null | Out-Null
        ipconfig /renew 2>$null | Out-Null
        ipconfig /flushdns 2>$null | Out-Null

        if ($adapterReset) {
            Complete-ToolRun $run -Status Success -Summary 'Wi-Fi adapter reset; IP renewed; DNS flushed'
        } else {
            Complete-ToolRun $run -Status Warning -Summary 'No Wi-Fi adapter found; IP renewed and DNS flushed only'
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `login-quick-fix`, before the closing `    )`). Note `RequiresAdmin = $true`, `Risk = 'Disruptive'`:

```powershell
        @{
            Id            = 'wifi-quick-fix'
            LegacyId      = 'Q5'
            Name          = 'Quick Fix: Wi-Fi Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-WiFiQuickFix'
            Description   = 'One-click Wi-Fi fix: restart the Wi-Fi adapter, release/renew the IP, and flush DNS; see also wifi-diagnostics and network-stack-reset'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','wifi','network','dns')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-WiFiQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 96 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): wifi-quick-fix (port v8 Q5)"
```

---

### Task 6: vpn-quick-fix (v8 Q6)

**Files:**
- Create: `src/tools/quickfix/Invoke-VpnQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content (NOTE: v8's `Pbk\*` profile-deletion is intentionally OMITTED):

```powershell
function Invoke-VpnQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'vpn-quick-fix'

        Write-ToolOutput 'VPN quick fix will: disconnect active VPNs, flush DNS, and clear the ARP cache. Your VPN profiles are NOT deleted.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the VPN quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'VPN quick fix declined'
            return
        }

        $vpns = @(Get-VpnConnection -ErrorAction SilentlyContinue)
        $disconnected = 0
        foreach ($v in $vpns) {
            rasdial $v.Name /disconnect 2>$null | Out-Null
            $disconnected++
        }
        ipconfig /flushdns 2>$null | Out-Null
        netsh interface ip delete arpcache 2>$null | Out-Null

        Complete-ToolRun $run -Status Success -Summary ('{0} VPN connection(s) disconnected; DNS flushed; ARP cache cleared' -f $disconnected)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `wifi-quick-fix`, before the closing `    )`). Note `RequiresAdmin = $true`, `Risk = 'Disruptive'`:

```powershell
        @{
            Id            = 'vpn-quick-fix'
            LegacyId      = 'Q6'
            Name          = 'Quick Fix: VPN Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-VpnQuickFix'
            Description   = 'One-click VPN fix: disconnect active VPNs, flush DNS, and clear the ARP cache (does not delete VPN profiles); see also vpn-health'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','vpn','network','dns')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-VpnQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 97 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): vpn-quick-fix (port v8 Q6, drop Pbk profile deletion)"
```

---

### Task 7: av-prep-quick-fix (v8 Q7)

**Files:**
- Create: `src/tools/quickfix/Invoke-AvPrepQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Invoke-AvPrepQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'av-prep-quick-fix'

        Write-ToolOutput 'Audio/Video prep will: close meeting apps and browsers (Teams, Zoom, Skype, Edge, Chrome, Firefox), restart the audio service, and open the Camera app.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed? This closes browsers and meeting apps.' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Audio/Video prep declined'
            return
        }

        $killed = 0
        foreach ($name in @('Teams','ms-teams','MSTeams','Zoom','Skype','msedge','chrome','firefox')) {
            $p = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
            if ($p.Count -gt 0) {
                $p | Stop-Process -Force -ErrorAction SilentlyContinue
                $killed++
            }
        }
        Start-Sleep -Seconds 2
        Restart-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
        Start-Process 'microsoft.windows.camera:' -ErrorAction SilentlyContinue

        $svc = (Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue).Status
        if (-not $svc) { $svc = 'Unknown' }
        if ($svc -eq 'Running') {
            Complete-ToolRun $run -Status Success -Summary ('{0} app group(s) closed; audio service Running; Camera opened' -f $killed)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('{0} app group(s) closed; audio service status {1}' -f $killed, $svc)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `vpn-quick-fix`, before the closing `    )`). Note `RequiresAdmin = $true`, `Risk = 'Disruptive'`:

```powershell
        @{
            Id            = 'av-prep-quick-fix'
            LegacyId      = 'Q7'
            Name          = 'Quick Fix: Audio/Video Prep'
            Category      = 'QuickFix'
            Function      = 'Invoke-AvPrepQuickFix'
            Description   = 'One-click meeting prep: close meeting apps and browsers to free the camera/mic, restart the audio service, and open the Camera app; see also webcam-audio-test and teams-camera-repair'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','audio','camera','meeting')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-AvPrepQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 98 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): av-prep-quick-fix (port v8 Q7)"
```

---

### Task 8: docking-quick-fix (v8 Q8)

**Files:**
- Create: `src/tools/quickfix/Invoke-DockingQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content (NOTE: v8's `Remove-Item HKCU:\...\DWM -Recurse` is intentionally OMITTED):

```powershell
function Invoke-DockingQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'docking-quick-fix'

        Write-ToolOutput 'Docking quick fix will: detect displays and switch to extend mode. Use Win+P afterward to change the display mode if needed.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the docking quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Docking quick fix declined'
            return
        }

        Start-Process -FilePath 'DisplaySwitch.exe' -ArgumentList '/detect' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process -FilePath 'DisplaySwitch.exe' -ArgumentList '/extend' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        Complete-ToolRun $run -Status Success -Summary 'Displays detected and set to extend; use Win+P to change mode'
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `av-prep-quick-fix`, before the closing `    )`):

```powershell
        @{
            Id            = 'docking-quick-fix'
            LegacyId      = 'Q8'
            Name          = 'Quick Fix: Docking Station'
            Category      = 'QuickFix'
            Function      = 'Invoke-DockingQuickFix'
            Description   = 'One-click docking fix: detect displays and switch to extend mode (use Win+P to change mode); see also docking-displays'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','docking','display','monitor')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-DockingQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 99 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): docking-quick-fix (port v8 Q8, drop DWM key deletion)"
```

---

### Task 9: browser-backup-quick-fix (v8 Q9)

**Files:**
- Create: `src/tools/quickfix/Invoke-BrowserBackupQuickFix.ps1`
- Modify: `src/registry/tools.psd1`

This tool reuses the CORE browser helpers (`Get-BrowserCatalog`, `Get-BrowserProfiles`, `Get-BrowserBackupRoot`, `Close-Browsers`) from `src/core/08-browser-helpers.ps1` — they are globally available in the built artifact.

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Invoke-BrowserBackupQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'browser-backup-quick-fix'

        $catalog = Get-BrowserCatalog
        $root = Get-BrowserBackupRoot -PreferredRoot 'M:\BrowserBackups'

        Write-ToolOutput ('Browser backup quick fix will: close all browsers, then back up bookmarks/logins for installed browsers to {0}.' -f $root) -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed? This closes all browsers.' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Browser backup quick fix declined'
            return
        }

        $procNames = @($catalog | ForEach-Object { $_.ProcessNames } | Sort-Object -Unique)
        [void](Close-Browsers -ProcessNames $procNames)

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $destDir = Join-Path $root ('QuickBackup_{0}' -f $stamp)
        try { New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null }
        catch {
            Complete-ToolRun $run -Status Warning -Summary ('Backup destination not writable: {0}' -f $destDir)
            return
        }

        $files = 0
        $browsers = 0
        foreach ($b in $catalog) {
            $profiles = @(Get-BrowserProfiles -Browser $b)
            if ($profiles.Count -eq 0) { continue }
            $browsers++
            foreach ($prof in $profiles) {
                $target = Join-Path (Join-Path $destDir $b.Name) $prof.Name
                New-Item -ItemType Directory -Path $target -Force -ErrorAction SilentlyContinue | Out-Null
                foreach ($fn in $b.BackupFiles) {
                    $src = Join-Path $prof.FullName $fn
                    if (Test-Path -LiteralPath $src) {
                        Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath (Join-Path $target $fn)) { $files++ }
                    }
                }
            }
        }

        $zip = ('{0}.zip' -f $destDir)
        Compress-Archive -Path (Join-Path $destDir '*') -DestinationPath $zip -Force -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath $zip) {
            Complete-ToolRun $run -Status Success -Summary ('{0} file(s) from {1} browser(s) backed up to {2}' -f $files, $browsers, $zip)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('{0} file(s) copied to {1} but ZIP was not created' -f $files, $destDir)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `docking-quick-fix`, before the closing `    )`). Note `Risk = 'Disruptive'`:

```powershell
        @{
            Id            = 'browser-backup-quick-fix'
            LegacyId      = 'Q9'
            Name          = 'Quick Fix: Browser Backup'
            Category      = 'QuickFix'
            Function      = 'Invoke-BrowserBackupQuickFix'
            Description   = 'One-click browser backup: close browsers and back up bookmarks/logins for installed browsers to a timestamped ZIP; see also browser-backup-restore'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','browser','backup','bookmarks')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Invoke-BrowserBackupQuickFix.ps1`.
- [ ] **Step 4: Build and test** — Expected: 100 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): browser-backup-quick-fix (port v8 Q9, reuse browser core helpers)"
```

---

### Task 10: Update parity checklist

**Files:**
- Modify: `docs/parity-checklist.md`

- [ ] **Step 1: Update the header.** Change the header line to read `updated batch 7 close-out (v8 parity COMPLETE). **100 of ~111 items ported**` and append `Q1-Q9` to the ported list.

- [ ] **Step 2: Update the Quick Fixes table rows** for Q1-Q9:

| v8 # | new Status | v9 Id |
|---|---|---|
| Q1 | `ported (batch 7)` | `office-quick-fix` |
| Q2 | `ported (batch 7)` | `onedrive-quick-fix` |
| Q3 | `ported (batch 7)` | `teams-quick-fix` |
| Q4 | `ported (batch 7)` | `login-quick-fix` |
| Q5 | `ported (batch 7)` | `wifi-quick-fix` |
| Q6 | `ported (batch 7)` | `vpn-quick-fix` |
| Q7 | `ported (batch 7)` | `av-prep-quick-fix` |
| Q8 | `ported (batch 7)` | `docking-quick-fix` |
| Q9 | `ported (batch 7)` | `browser-backup-quick-fix` |

- [ ] **Step 3: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "docs(7): parity checklist - 100 tools, v8 parity COMPLETE"
```

---

## Self-Review (controller, after all tasks)

- **Spec coverage:** nine `Invoke-*QuickFix` tool files (Q1-Q9) under the new `QuickFix` category — all present. Each tool's described steps match the spec; the two dropped v8 behaviors (Q6 Pbk, Q8 DWM) are omitted as required.
- **Type/name consistency:** every `New-ToolRun -Id '<id>'` literal matches its registry `Id`; each file's function name matches the registry `Function`.
- **Interaction model:** every tool gates the whole sequence behind one `Read-ToolChoice -Default 'No' -Silent:$Silent`; under `-Silent` it returns `No` -> `Skipped` no-op.
- **Status enum:** no `Complete-ToolRun -Status Error` anywhere.
- **Admin/Risk:** wifi/vpn/av-prep = admin + Disruptive; office/browser-backup = Disruptive; the rest Modifies — matches the spec table.

## Final review + finish

After Task 10, dispatch a whole-batch reviewer (constrained `general-purpose`: "output ONLY your review; do not modify files/memory/commit") over the nine new tool files + registry diff (focus on the dropped-behavior verification for Q6/Q8, the `-Silent` no-op gate, and Q9's correct use of the browser core helpers), fix anything it flags, then use **superpowers:finishing-a-development-branch** to merge `batch-7-quickfixes` to master locally (single-line `-m` merge message).
