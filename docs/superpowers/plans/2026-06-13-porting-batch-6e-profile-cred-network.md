# Porting Batch 6E: Profile / Credentials / Network Tools - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 tools 58/60/66/95 (+ fold retired tool 26) into v9 as four report-then-action tools in Category 'User'.

**Architecture:** Each tool runs a read-only report first, then `Read-ToolChoice -Choices @('None', <actions>) -Default 'None' -Silent:$Silent`. Destructive actions gated (Yes/No Default-No or typed CONFIRM/CLEAR). No new core helper - each tool self-contained.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs\superpowers\specs\2026-06-13-batch-6e-profile-cred-network-design.md`.

**v8 reference (READ-ONLY):** `C:\Users\IT\Desktop\NMMTools.ps1` - `Repair-NetworkDrives` L7479, `Clear-SavedCredentials` L8132, `Clear-ProfileCache` L8935, `Repair-TemporaryProfile` L11175, retired `Clear-CredentialManager` L1345.

---

## Two safety hardenings over v8 (intentional deviations - flag to Matt)

1. **profile-cache: OneDrive is REPORT-ONLY (not cleaned).** v8 deleted the whole `AppData\Local\Microsoft\OneDrive` folder as "cache" - that is the OneDrive APP + settings, deleting it breaks OneDrive. v9 reports its size but never cleans it (same treatment as Downloads). Cleanable set = Temp, Teams, Office, Chrome, Edge.
2. **temp-profile-repair: ProfileList surgery uses `reg copy` (not PowerShell recreate).** v8 recreated the key by reading each value and passing `.GetType().Name` (e.g. `Int32`) as `-PropertyType`, which is not a valid registry type (`DWord`/`Binary`/`ExpandString`). v9 uses `reg.exe copy <.bak> <real> /s /f` which preserves value types and subkeys correctly, after a `reg export` backup.

## Standing rules (carried from batches 1-6)

- PS 5.1: no ternary / `??` / `&&`; never ASSIGN `$input`/`$matches`/`$profile` (reading `$matches[n]` after `-match` is allowed). **ASCII-only source** (encoding test fails build on non-ASCII), UTF-8 BOM + trailing newline.
- Tools use `Write-ToolOutput` / `Read-ToolChoice` only - never `Write-Host`. `Read-Host` allowed only for the interactive RemapDrive input (reached only after an action choice; never under `-Silent`). Native data reads (`cmdkey /list`, `net use`, `reg export`) are allowed.
- Every tool function: approved verb (Repair/Clear), `[switch]$Silent`, calls `New-ToolRun` + `Complete-ToolRun`, `New-ToolRun -Id` literal == registry Id.
- `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`.
- One tool file per registered function in `src\tools\user\`; one registry entry each (add BOTH per task).

## Registry entries (added per task)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable |
|---|---|---|---|---|---|---|---|
| network-drives | 58 | Mapped Network Drive Repair | Repair-NetworkDrives | User | $false | Modifies | $true |
| credential-manager | 60 | Credential Manager Cleanup | Clear-SavedCredentials | User | $false | Modifies | $true |
| profile-cache | 66 | Profile Size and Cache Cleanup | Clear-ProfileCache | User | $false | Modifies | $true |
| temp-profile-repair | 95 | Temporary Profile Repair | Repair-TemporaryProfile | User | $true | Disruptive | $true |

Tool count **73 -> 77** (User category 7 -> 11). Retired 26 folds into credential-manager (ClearOffice365 action).

## Smoke safety (non-elevated dev session)

- `network-drives -Silent`, `credential-manager -Silent`, `profile-cache -Silent` -> report only (None default), exit 0.
- `temp-profile-repair -Silent` -> RequiresAdmin + Disruptive -> dispatcher refuses (Refused / exit 1).
- NEVER run the destructive actions (RemapDrive, any Clear*, CleanCaches, RepairProfile) in dev - they delete credentials/cache and edit HKLM. Verify by reading + the silent report.

---

## Setup: create the batch branch

- [ ] **Step 1: Branch off master**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" checkout -b port/batch-6e-profile-cred-network
```
Expected: `Switched to a new branch 'port/batch-6e-profile-cred-network'`

---

## Task 1: network-drives (58)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-NetworkDrives.ps1`

- [ ] **Step 1: Append the registry entry** (LAST element of the `Tools = @( ... )` array, before its closing `)`):
```powershell
        @{
            Id            = 'network-drives'
            LegacyId      = '58'
            Name          = 'Mapped Network Drive Repair'
            Category      = 'User'
            Function      = 'Repair-NetworkDrives'
            Description   = 'Report mapped network drives and reconnect disconnected ones, or remap a drive letter to a UNC path'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('network','drive','mapped','unc')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-NetworkDrives.ps1`** with EXACTLY this content:
```powershell
function Repair-NetworkDrives {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'network-drives'

        # --- Report ---
        $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayRoot -like '\\*' })
        if ($drives.Count -gt 0) {
            Write-ToolOutput ('Mapped network drives: {0}' -f $drives.Count) -Level Info
            foreach ($d in $drives) {
                $state = 'DISCONNECTED'
                if (Test-Path -LiteralPath $d.Root) { $state = 'CONNECTED' }
                Write-ToolOutput ('  {0}: {1}  [{2}]' -f $d.Name, $d.DisplayRoot, $state) -Level Detail
            }
        } else {
            Write-ToolOutput 'No mapped network drives found.' -Level Warning
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Network drive action' `
            -Choices @('None','ReconnectAll','RemapDrive') -Default 'None' -Silent:$Silent

        switch ($action) {

            'ReconnectAll' {
                $configured = @()
                $netUse = & net.exe use
                foreach ($line in $netUse) {
                    $text = [string]$line
                    if ($text -match '^\s*(OK|Disconnected|Unavailable)\s+(\w):\s+(\\\\[^\s]+)') {
                        $configured += [PSCustomObject]@{ Letter = $matches[2]; Path = $matches[3] }
                    }
                }
                $regDrives = @(Get-ItemProperty 'HKCU:\Network\*' -ErrorAction SilentlyContinue)
                foreach ($rd in $regDrives) {
                    if ($rd.RemotePath -and $rd.PSChildName -and -not (@($configured | Where-Object { $_.Letter -eq $rd.PSChildName }).Count)) {
                        $configured += [PSCustomObject]@{ Letter = $rd.PSChildName; Path = $rd.RemotePath }
                    }
                }
                if ($configured.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No configured network drives to reconnect'
                } else {
                    $okCount = 0
                    foreach ($cd in $configured) {
                        $dl = '{0}:' -f $cd.Letter
                        if (Test-Path -LiteralPath $dl) {
                            & net.exe use $dl /delete /y *>$null
                            Start-Sleep -Milliseconds 500
                        }
                        & net.exe use $dl $cd.Path /persistent:yes *>$null
                        Start-Sleep -Milliseconds 500
                        if (Test-Path -LiteralPath $dl) {
                            Write-ToolOutput ('  [OK] {0} -> {1}' -f $dl, $cd.Path) -Level Success
                            $okCount++
                        } else {
                            Write-ToolOutput ('  [FAIL] {0} -> {1}' -f $dl, $cd.Path) -Level Warning
                        }
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Reconnected {0} of {1} configured drive(s)' -f $okCount, $configured.Count)
                }
            }

            'RemapDrive' {
                # Read-Host is safe here: only reached in the interactive RemapDrive branch (never under -Silent).
                $letter = (Read-Host 'Drive letter to (re)map (e.g. Z)').Trim().TrimEnd(':')
                $unc = (Read-Host 'UNC path (e.g. \\server\share)').Trim()
                if ([string]::IsNullOrWhiteSpace($letter) -or ($unc -notlike '\\*')) {
                    Complete-ToolRun $run -Status Warning -Summary 'RemapDrive aborted: invalid drive letter or UNC path'
                } else {
                    $dl = '{0}:' -f $letter
                    & net.exe use $dl /delete /y *>$null
                    Start-Sleep -Milliseconds 500
                    & net.exe use $dl $unc /persistent:yes *>$null
                    Start-Sleep -Milliseconds 500
                    if (Test-Path -LiteralPath $dl) {
                        Complete-ToolRun $run -Status Success -Summary ('Mapped {0} -> {1}' -f $dl, $unc)
                    } else {
                        Complete-ToolRun $run -Status Warning -Summary ('Mapped {0} -> {1} but not accessible (clear stale share creds via credential-manager)' -f $dl, $unc)
                    }
                }
            }

            default {
                if ($drives.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No mapped network drives; no action taken'
                } else {
                    Complete-ToolRun $run -Status Success -Summary ('{0} mapped drive(s) reported; no action taken' -f $drives.Count)
                }
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
Expected: `Built ...`; suite `Failed: 0` (71 passed). Verb `Repair` approved; Id matches.

- [ ] **Step 4: Smoke the silent report-only path**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
. "$r\src\tools\user\Repair-NetworkDrives.ps1"
Set-OutputSink -Sink Silent
Repair-NetworkDrives -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: `network-drives: Success - N mapped drive(s) reported; no action taken` (or `Warning - No mapped network drives...`). NO drive changes. Paste the run-record line.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-NetworkDrives.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-NetworkDrives.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port batch 6e.1 (network-drives)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 2: credential-manager (60 + retired 26)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Clear-SavedCredentials.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'credential-manager'
            LegacyId      = '60'
            Name          = 'Credential Manager Cleanup'
            Category      = 'User'
            Function      = 'Clear-SavedCredentials'
            Description   = 'List saved Windows credentials and clear network, web, Office 365, or all of them (stops the Office sign-in loop); or open Credential Manager'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('credential','cmdkey','password','office365')
        }
```

- [ ] **Step 2: Create `src\tools\user\Clear-SavedCredentials.ps1`** with EXACTLY this content:
```powershell
function Clear-SavedCredentials {
    [CmdletBinding()]
    param([switch]$Silent)

    # Returns the current list of cmdkey credential Targets (re-queried each call).
    function Get-CredTargets {
        $l = (cmdkey /list 2>&1) | Out-String
        @(($l -split "`r?`n") |
            Where-Object { $_ -match 'Target:' } |
            ForEach-Object { ($_ -replace '.*Target:\s*', '').Trim() } |
            Where-Object { $_ })
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'credential-manager'

        # --- Report ---
        $targets = @(Get-CredTargets)
        Write-ToolOutput ('Saved credentials: {0}' -f $targets.Count) -Level Info
        foreach ($t in ($targets | Select-Object -First 20)) { Write-ToolOutput ('  {0}' -f $t) -Level Detail }
        if ($targets.Count -gt 20) { Write-ToolOutput ('  ... and {0} more' -f ($targets.Count - 20)) -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Credential action' `
            -Choices @('None','ClearNetwork','ClearWeb','ClearOffice365','ClearAll','OpenCredManager') -Default 'None' -Silent:$Silent

        switch ($action) {

            'ClearNetwork' {
                $removed = 0
                foreach ($t in (Get-CredTargets)) {
                    if ($t -like '*\\*' -or $t -like 'Domain:*' -or $t -like '*smb*' -or $t -like '*cifs*') {
                        cmdkey "/delete:$t" *>$null
                        $removed++
                    }
                }
                Complete-ToolRun $run -Status Success -Summary ('Cleared {0} network/share credential(s)' -f $removed)
            }

            'ClearWeb' {
                $removed = 0
                foreach ($t in (Get-CredTargets)) {
                    if ($t -like '*http*' -or $t -like '*.com' -or $t -like '*.net' -or $t -like '*.org' -or $t -like 'WindowsLive:*') {
                        cmdkey "/delete:$t" *>$null
                        $removed++
                    }
                }
                Complete-ToolRun $run -Status Success -Summary ('Cleared {0} web credential(s)' -f $removed)
            }

            'ClearOffice365' {
                $removed = 0
                foreach ($t in (Get-CredTargets)) {
                    if ($t -match 'MicrosoftOffice') {
                        cmdkey "/delete:$t" *>$null
                        $removed++
                    }
                }
                Complete-ToolRun $run -Status Success -Summary ('Cleared {0} Office 365 credential(s) (stops the Office sign-in loop)' -f $removed)
            }

            'ClearAll' {
                Write-ToolOutput 'WARNING: removes ALL saved credentials (shares, RDP, web, services). You will re-enter passwords everywhere.' -Level Warning
                $gate = Read-ToolChoice -Prompt 'Type CLEAR to remove ALL saved credentials' `
                    -Choices @('CLEAR','Cancel') -Default 'Cancel' -Silent:$Silent
                if ($gate -ne 'CLEAR') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearAll cancelled (no CLEAR)'
                } else {
                    $removed = 0
                    foreach ($t in (Get-CredTargets)) {
                        cmdkey "/delete:$t" *>$null
                        $removed++
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Cleared ALL {0} saved credential(s); resources will prompt for passwords' -f $removed)
                }
            }

            'OpenCredManager' {
                Start-Process 'control.exe' -ArgumentList '/name Microsoft.CredentialManager' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Credential Manager opened.' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened Credential Manager'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('{0} credential(s) reported; no action taken' -f $targets.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`. (The nested `Get-CredTargets` is fine - registry/template tests enumerate top-level tool functions only, matching the Test-VPNHealth/Test-TcpEndpoint precedent.)

- [ ] **Step 4: Smoke the silent report-only path**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
. "$r\src\tools\user\Clear-SavedCredentials.ps1"
Set-OutputSink -Sink Silent
Clear-SavedCredentials -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: lists credentials read-only, then `credential-manager: Success - N credential(s) reported; no action taken`. NO credentials deleted. Paste the run-record line.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Clear-SavedCredentials.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Clear-SavedCredentials.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port batch 6e.2 (credential-manager, folds retired tool 26 Office-cred clear)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 3: profile-cache (66)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Clear-ProfileCache.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'profile-cache'
            LegacyId      = '66'
            Name          = 'Profile Size and Cache Cleanup'
            Category      = 'User'
            Function      = 'Clear-ProfileCache'
            Description   = 'Report user-profile cache folder sizes (Teams/OneDrive/Office/Chrome/Edge/Temp/Downloads) and optionally clear the safe caches; never touches OneDrive or Downloads'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('profile','cache','cleanup','roaming')
        }
```

- [ ] **Step 2: Create `src\tools\user\Clear-ProfileCache.ps1`** with EXACTLY this content:
```powershell
function Clear-ProfileCache {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'profile-cache'

        $prof = $env:USERPROFILE
        # Cleanable=$true folders have their CONTENTS cleared. OneDrive (app folder) and Downloads
        # (user data) are REPORT-ONLY - clearing them would break OneDrive / delete user files.
        $folders = @(
            @{ Name = 'Temp';      Path = $env:TEMP; Cleanable = $true },
            @{ Name = 'Teams';     Path = (Join-Path $prof 'AppData\Local\Microsoft\Teams'); Cleanable = $true },
            @{ Name = 'Office';    Path = (Join-Path $prof 'AppData\Local\Microsoft\Office\16.0\OfficeFileCache'); Cleanable = $true },
            @{ Name = 'Chrome';    Path = (Join-Path $prof 'AppData\Local\Google\Chrome\User Data\Default\Cache'); Cleanable = $true },
            @{ Name = 'Edge';      Path = (Join-Path $prof 'AppData\Local\Microsoft\Edge\User Data\Default\Cache'); Cleanable = $true },
            @{ Name = 'OneDrive';  Path = (Join-Path $prof 'AppData\Local\Microsoft\OneDrive'); Cleanable = $false },
            @{ Name = 'Downloads'; Path = (Join-Path $prof 'Downloads'); Cleanable = $false }
        )

        # --- Report (read-only sizes) ---
        Write-ToolOutput 'Profile cache sizes:' -Level Info
        $totalBefore = [int64]0
        foreach ($f in $folders) {
            if (Test-Path -LiteralPath $f.Path) {
                $sz = [int64]0
                try {
                    $s = (Get-ChildItem -LiteralPath $f.Path -Recurse -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                    if ($s) { $sz = [int64]$s }
                } catch { }
                $totalBefore += $sz
                $tag = ''
                if (-not $f.Cleanable) { $tag = '  (report-only)' }
                Write-ToolOutput ('  {0,-9} {1,8:N1} MB{2}' -f $f.Name, ($sz / 1MB), $tag) -Level Detail
            }
        }
        Write-ToolOutput ('Total: {0:N1} MB' -f ($totalBefore / 1MB)) -Level Info

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Profile cache action' -Choices @('None','CleanCaches') -Default 'None' -Silent:$Silent

        switch ($action) {

            'CleanCaches' {
                Write-ToolOutput 'This clears the Temp/Teams/Office/Chrome/Edge caches (NOT OneDrive or Downloads).' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Clear the cleanable cache folders?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'CleanCaches cancelled'
                } else {
                    foreach ($f in ($folders | Where-Object { $_.Cleanable })) {
                        if (Test-Path -LiteralPath $f.Path) {
                            Get-ChildItem -LiteralPath $f.Path -Force -ErrorAction SilentlyContinue |
                                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $totalAfter = [int64]0
                    foreach ($f in $folders) {
                        if (Test-Path -LiteralPath $f.Path) {
                            try {
                                $s = (Get-ChildItem -LiteralPath $f.Path -Recurse -Force -ErrorAction SilentlyContinue |
                                    Measure-Object -Property Length -Sum).Sum
                                if ($s) { $totalAfter += [int64]$s }
                            } catch { }
                        }
                    }
                    $freed = [math]::Round((($totalBefore - $totalAfter) / 1MB), 1)
                    if ($freed -lt 0) { $freed = 0 }
                    Complete-ToolRun $run -Status Success -Summary ('Cleared cleanable caches; freed {0} MB' -f $freed)
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('Profile cache reported ({0:N1} MB); no action taken' -f ($totalBefore / 1MB))
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`. Verb `Clear` approved.

- [ ] **Step 4: Smoke the silent report-only path**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
. "$r\src\tools\user\Clear-ProfileCache.ps1"
Set-OutputSink -Sink Silent
Clear-ProfileCache -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: prints cache sizes (OneDrive/Downloads tagged report-only), then `profile-cache: Success - Profile cache reported (N MB); no action taken`. NO files deleted. Paste the run-record line.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Clear-ProfileCache.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Clear-ProfileCache.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port batch 6e.3 (profile-cache; OneDrive/Downloads report-only, contents-only clear)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 4: temp-profile-repair (95)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-TemporaryProfile.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'temp-profile-repair'
            LegacyId      = '95'
            Name          = 'Temporary Profile Repair'
            Category      = 'User'
            Function      = 'Repair-TemporaryProfile'
            Description   = 'Detect the "signed in with a temporary profile" issue (orphaned .bak keys in HKLM ProfileList) and repair it via reg copy after a registry backup; affected user must be logged off'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('profile','temporary','profilelist','registry')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-TemporaryProfile.ps1`** with EXACTLY this content:
```powershell
function Repair-TemporaryProfile {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'temp-profile-repair'

        $plPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $plReg  = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

        # --- Report (read-only scan) ---
        $keys = @(Get-ChildItem -LiteralPath $plPath -ErrorAction SilentlyContinue)
        $tempPattern = @()
        $orphanBak = @()
        foreach ($k in $keys) {
            $sid = Split-Path $k.Name -Leaf
            if ($sid.EndsWith('.bak')) {
                $img = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
                $realSid = $sid -replace '\.bak$', ''
                $realExists = Test-Path -LiteralPath ('{0}\{1}' -f $plPath, $realSid)
                if ($realExists) {
                    $tempPattern += [PSCustomObject]@{ RealSid = $realSid; Img = $img }
                    Write-ToolOutput ('  [TEMP-PROFILE] {0}  ({1})' -f $sid, $img) -Level Warning
                } else {
                    $orphanBak += [PSCustomObject]@{ Sid = $sid; Img = $img }
                    Write-ToolOutput ('  [orphan .bak] {0}  ({1})' -f $sid, $img) -Level Detail
                }
            }
        }

        if ($tempPattern.Count -eq 0) {
            if ($orphanBak.Count -gt 0) {
                Complete-ToolRun $run -Status Warning -Summary ('{0} orphan .bak key(s) found but no temp-profile pattern; no auto-repair' -f $orphanBak.Count)
            } else {
                Complete-ToolRun $run -Status Success -Summary 'No temporary profile issues detected'
            }
            return
        }

        Write-ToolOutput ('{0} temporary-profile pattern(s) detected (real SID + .bak).' -f $tempPattern.Count) -Level Warning

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Temporary profile action' -Choices @('None','RepairProfile') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RepairProfile' {
                Write-ToolOutput 'WARNING: this edits HKLM ProfileList. The AFFECTED USER MUST BE LOGGED OFF first.' -Level Warning
                $gate = Read-ToolChoice -Prompt 'Type CONFIRM to repair (is the affected user logged off?)' `
                    -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
                if ($gate -ne 'CONFIRM') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RepairProfile cancelled (no CONFIRM)'
                } else {
                    # 1. Backup ProfileList FIRST; abort if export fails (no changes made).
                    $backup = Join-Path $env:TEMP ('ProfileList_backup_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                    & reg.exe export $plReg $backup /y *>$null
                    if (-not (Test-Path -LiteralPath $backup)) {
                        Complete-ToolRun $run -Status Failed -Summary 'Aborted: could not export ProfileList backup (no changes made)'
                        return
                    }
                    Write-ToolOutput ('ProfileList backed up: {0}' -f $backup) -Level Info

                    # 2. For each temp-profile pattern: reg copy .bak -> real SID (type-correct), then delete .bak.
                    $repaired = 0
                    foreach ($p in $tempPattern) {
                        $realReg = '{0}\{1}' -f $plReg, $p.RealSid
                        $bakReg  = '{0}\{1}.bak' -f $plReg, $p.RealSid
                        & reg.exe delete $realReg /f *>$null
                        & reg.exe copy $bakReg $realReg /s /f *>$null
                        if ($LASTEXITCODE -eq 0) {
                            & reg.exe delete $bakReg /f *>$null
                            Write-ToolOutput ('  Repaired: {0}' -f $p.Img) -Level Success
                            $repaired++
                        } else {
                            Write-ToolOutput ('  Repair failed for {0} (reg copy exit {1}); backup retained at {2}' -f $p.Img, $LASTEXITCODE, $backup) -Level Error
                        }
                    }

                    if ($repaired -gt 0) {
                        Complete-ToolRun $run -Status Success -Summary ('Repaired {0} temp profile(s); backup: {1}; have the user log in again' -f $repaired, $backup)
                    } else {
                        Complete-ToolRun $run -Status Failed -Summary ('No profiles repaired; backup retained at {0}' -f $backup)
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Warning -Summary ('{0} temp-profile pattern(s) detected; no repair applied' -f $tempPattern.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`. Verb `Repair` approved; registry tests confirm unique Id/LegacyId and Risk 'Disruptive'.

- [ ] **Step 4: Smoke the silent refusal (RequiresAdmin + Disruptive)**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $false
. "$r\src\tools\user\Repair-TemporaryProfile.ps1"
$tool = Resolve-NmmTool -Query 'temp-profile-repair'
Write-Output ("RESULT: " + (Invoke-NmmTool -Tool $tool -Silent))
```
Expected: `RESULT: Refused` (RequiresAdmin + not elevated). Paste that line. Do NOT run the repair.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-TemporaryProfile.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-TemporaryProfile.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port batch 6e.4 (temp-profile-repair; reg-copy surgery + reg-export backup)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 5: Sub-batch 6E close-out

**Files:**
- Modify: `docs\parity-checklist.md`

- [ ] **Step 1: Verify 77 tools and the User category**
```powershell
$tk = "$env:USERPROFILE\Desktop\NMMToolkit"
$lines = (& "$tk\dist\NMMTools.ps1" -ListTools | Out-String) -split "`r?`n"
$toolRows = $lines | Where-Object { $_ -match '\s(Browser|Cloud|Diagnostics|Laptop|Repair|User)\s+(ReadOnly|Modifies|Disruptive)\s' }
Write-Output ("Total tool rows: {0}" -f $toolRows.Count)
$lines | Where-Object { $_ -match '\s(network-drives|credential-manager|profile-cache|temp-profile-repair)\s' }
```
Expected: Total = **77**; the 4 new rows present (network-drives/credential-manager/profile-cache = User/Modifies/Admin False; temp-profile-repair = User/Disruptive/Admin True). Quote them.

- [ ] **Step 2: Confirm build + full suite are green**
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: Build OK; `Failed: 0`.

- [ ] **Step 3: Update the parity checklist** in `docs\parity-checklist.md`:

(a) Set the four ported rows:
```markdown
| 58 | Mapped Network Drives | ported (batch 6e) | network-drives |
| 60 | Credential Manager Cleanup | ported (batch 6e) | credential-manager |
| 66 | Local Profile Size & Roaming Cache Cleanup | ported (batch 6e) | profile-cache |
| 95 | Temporary Profile Repair | ported (batch 6e) | temp-profile-repair |
```
(b) Update the header count line from `73 of ~111 items ported` to `77 of ~111 items ported` and add `, 58, 60, 66, 95` to the ported-items list. (Tool 26 was already listed as consolidated -> 60; no change needed there.)

- [ ] **Step 4: Commit the docs**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add docs/parity-checklist.md
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "docs: batch 6e complete - parity checklist (77/106 ported)"
```

- [ ] **Step 5: Final review + finish the branch**

Review focus: temp-profile-repair exports a ProfileList backup BEFORE any edit and aborts if export fails; uses `reg copy` (type-correct) not PS recreate; typed CONFIRM + logged-off warning + admin + Disruptive. credential-manager re-queries `cmdkey /list` at action time and ClearAll is typed-CLEAR gated; ClearOffice365 (folded tool 26) targets MicrosoftOffice only. profile-cache NEVER cleans OneDrive or Downloads (report-only) and clears CONTENTS only. network-drives RemapDrive validates the UNC and does not duplicate credential clearing. -Silent is safe on all four (report-only / Refused for temp-profile-repair).

Then invoke the **superpowers:finishing-a-development-branch** skill to merge `port/batch-6e-profile-cred-network` to master. **Use a simple single-line `-m` merge message** (here-string mangles git args). Verify the suite on the merged result before deleting the branch.

---

## Self-review (completed by plan author)

- **Spec coverage:** 4 tools -> Tasks 1-4; retired 26 fold-in -> Task 2 ClearOffice365; Downloads never cleaned + OneDrive report-only (hardening) -> Task 3; gated ProfileList auto-repair with reg-export backup -> Task 4 (reg copy used instead of the fragile PS recreate); no credential-clear duplication in network-drives -> Task 1 (cross-reference in summary); dropped free-text remove-specific -> Task 2 action set; 77-tool/User verify -> Task 5.
- **Placeholder scan:** none - every step has complete code, exact commands, expected output.
- **Type/name consistency:** registry Function names (`Repair-NetworkDrives`, `Clear-SavedCredentials`, `Clear-ProfileCache`, `Repair-TemporaryProfile`) match the defined functions and the `New-ToolRun -Id` literals match each registry Id (`network-drives`, `credential-manager`, `profile-cache`, `temp-profile-repair`). All four use approved verbs (Repair/Clear) and declare `[switch]$Silent`. The nested `Get-CredTargets` in Clear-SavedCredentials is not registry-scanned (top-level enumeration only), matching the Test-TcpEndpoint precedent.
- **Deviations flagged:** profile-cache OneDrive report-only and temp-profile-repair reg-copy surgery are documented at the top of this plan as intentional hardenings over v8/spec.
