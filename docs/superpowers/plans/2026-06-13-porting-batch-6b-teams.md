# Porting Batch 6B: Teams Tools - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 Teams tools 83, 85, and merged 84+97 into v9 as three report-then-action tools in Category 'User'.

**Architecture:** Each tool runs a read-only report first, then `Read-ToolChoice -Choices @('None', <actions>) -Default 'None' -Silent:$Silent`. Actions that close Outlook or browsers/meeting apps warn + list + confirm (Default No). teams-deep-diagnostic's report IS an 11-check diagnostic and reuses a nested timeout-bounded `Test-TcpEndpoint` for network checks. No new core helper - each tool is self-contained.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs\superpowers\specs\2026-06-13-batch-6b-teams-design.md`.

**v8 reference (READ-ONLY):** `C:\Users\IT\Desktop\NMMTools.ps1` - `Repair-TeamsAddin` L9643, `Reset-TeamsPermissions` L9721, `Diagnose-TeamsDeep` L9830, `Reset-TeamsCameraMediaStack` L11423.

---

## Standing rules (carried from batches 1-6c)

- PS 5.1: no ternary / `??` / `&&`; never ASSIGN `$input`, `$matches`, or `$profile` (reading `$Matches[1]` after `-match` is fine). **ASCII-only source** (encoding test fails build on non-ASCII), UTF-8 BOM + trailing newline.
- Tools use `Write-ToolOutput` / `Read-ToolChoice` only - never `Write-Host`/`Read-Host`. (Native reads like `dsregcmd`, `cmdkey /list`, `netsh` are data queries, allowed.)
- Every tool function: approved verb (`Repair`), `[switch]$Silent`, calls `New-ToolRun` + `Complete-ToolRun`, `New-ToolRun -Id` literal == registry Id.
- `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`.
- One tool file per registered function in `src\tools\user\`; one registry entry each (add BOTH per task).
- v8's verb `Diagnose` is NOT approved - tool 85 uses `Repair-TeamsDeep`.

## Registry entries (added per task)

| Id | LegacyId | Name | Function | Category | Admin | Risk | SilentCapable |
|---|---|---|---|---|---|---|---|
| teams-addin-repair | 83 | Teams Meeting Add-in Repair | Repair-TeamsAddin | User | $false | Modifies | $true |
| teams-deep-diagnostic | 85 | Teams Deep Diagnostic and Repair | Repair-TeamsDeep | User | $false | Modifies | $true |
| teams-camera-repair | 84 | Teams Camera and Mic Repair | Repair-TeamsCamera | User | $true | Modifies | $true |

Tool count **70 -> 73** (3 user added; total User category 4 -> 7). 84/97 merged (LegacyId 84; 97 consolidated).

## Smoke safety (non-elevated dev session)

- `teams-addin-repair -Silent` -> report only (None default), exit 0.
- `teams-deep-diagnostic -Silent` -> runs the read-only 11-check diagnostic + None default (NO repair), exit 0.
- `teams-camera-repair -Silent` -> RequiresAdmin -> dispatcher refuses (Refused / exit 1).
- NEVER run RepairAddin / ApplyRepairs / FixPermissions / ResetMediaStack in dev (they close apps, clear credentials, cycle devices). Verify by reading + the silent report.

---

## Setup: create the batch branch

- [ ] **Step 1: Branch off master**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" checkout -b port/batch-6b-teams
```
Expected: `Switched to a new branch 'port/batch-6b-teams'`

---

## Task 1: teams-addin-repair (83)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-TeamsAddin.ps1`

- [ ] **Step 1: Append the registry entry** (LAST element of the `Tools = @( ... )` array, before its closing `)`):
```powershell
        @{
            Id            = 'teams-addin-repair'
            LegacyId      = '83'
            Name          = 'Teams Meeting Add-in Repair'
            Category      = 'User'
            Function      = 'Repair-TeamsAddin'
            Description   = 'Fix the missing New Teams Meeting button in Outlook: re-register the add-in COM DLL, set LoadBehavior, clear DisabledItems and add-in cache'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','outlook','addin','meeting')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-TeamsAddin.ps1`** with EXACTLY this content:
```powershell
function Repair-TeamsAddin {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-addin-repair'

        # --- Report ---
        $pkg = Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue
        if ($pkg) {
            Write-ToolOutput ('New Teams (MSTeams) installed: v{0}' -f $pkg.Version) -Level Info
        } else {
            Write-ToolOutput 'New Teams (MSTeams) not registered for this user.' -Level Warning
        }

        $addinRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddin'
        $dll = $null
        if (Test-Path -LiteralPath $addinRoot) {
            $dll = Get-ChildItem -LiteralPath $addinRoot -Filter 'Microsoft.Teams.AddinLoader.dll' -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if ($dll) {
            Write-ToolOutput ('Add-in DLL: {0}' -f $dll.FullName) -Level Detail
        } else {
            Write-ToolOutput 'Teams Meeting Add-in DLL not found.' -Level Warning
        }

        $addinKey = 'HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect'
        $lb = (Get-ItemProperty -Path $addinKey -Name 'LoadBehavior' -ErrorAction SilentlyContinue).LoadBehavior
        if ($null -ne $lb) {
            Write-ToolOutput ('Outlook add-in LoadBehavior: {0}' -f $lb) -Level Detail
        } else {
            Write-ToolOutput 'Outlook add-in LoadBehavior: (not set)' -Level Detail
        }

        $disabledKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems'
        Write-ToolOutput ('Outlook DisabledItems key present: {0}' -f (Test-Path -LiteralPath $disabledKey)) -Level Detail

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Teams add-in action' -Choices @('None','RepairAddin') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RepairAddin' {
                Write-ToolOutput 'WARNING: this CLOSES Outlook (save any open drafts first) and restarts Teams.' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Close Outlook and repair the Teams Meeting add-in?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RepairAddin cancelled'
                } else {
                    foreach ($p in @('OUTLOOK','ms-teams','MSTeams','Teams')) {
                        Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Seconds 3
                    if (-not $dll) {
                        Complete-ToolRun $run -Status Warning -Summary 'Add-in DLL not found; reinstall New Teams then retry'
                    } else {
                        $rc = Start-Process -FilePath 'regsvr32.exe' -ArgumentList ('/s "{0}"' -f $dll.FullName) -Wait -PassThru -ErrorAction SilentlyContinue
                        if ($rc -and $rc.ExitCode -ne 0) {
                            Write-ToolOutput ('regsvr32 exit {0} (often a 32/64-bit mismatch; continuing).' -f $rc.ExitCode) -Level Warning
                        } else {
                            Write-ToolOutput 'COM add-in re-registered.' -Level Success
                        }
                        if (-not (Test-Path -LiteralPath $addinKey)) { New-Item -Path $addinKey -Force | Out-Null }
                        Set-ItemProperty -Path $addinKey -Name 'LoadBehavior' -Value 3 -Type DWord -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath $disabledKey) {
                            Remove-Item -Path $disabledKey -Recurse -Force -ErrorAction SilentlyContinue
                            Write-ToolOutput 'Cleared Outlook DisabledItems.' -Level Detail
                        }
                        $cacheDir = Join-Path $addinRoot 'Cache'
                        if (Test-Path -LiteralPath $cacheDir) {
                            Get-ChildItem -LiteralPath $cacheDir -Force -ErrorAction SilentlyContinue |
                                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        Start-Process 'ms-teams:' -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        Complete-ToolRun $run -Status Success -Summary 'Teams Meeting add-in re-registered; relaunch Outlook to see the button'
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Teams add-in state reported; no action taken'
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
. "$r\src\tools\user\Repair-TeamsAddin.ps1"
Set-OutputSink -Sink Silent
Repair-TeamsAddin -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: `teams-addin-repair: Success - Teams add-in state reported; no action taken`. NO Outlook/Teams closed. Paste the run-record line.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-TeamsAddin.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-TeamsAddin.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port teams batch 6b.1 (teams-addin-repair)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 2: teams-deep-diagnostic (85)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-TeamsDeep.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'teams-deep-diagnostic'
            LegacyId      = '85'
            Name          = 'Teams Deep Diagnostic and Repair'
            Category      = 'User'
            Function      = 'Repair-TeamsDeep'
            Description   = '11-check diagnostic for New Teams auth/WAM/network issues; optional deep repair (clears credentials/WAM/MSIX cache, re-registers Teams) - sign-out required'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','wam','msal','auth','diagnostic')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-TeamsDeep.ps1`** with EXACTLY this content:
```powershell
function Repair-TeamsDeep {
    [CmdletBinding()]
    param([switch]$Silent)

    # Timeout-bounded TCP probe (reused pattern) - avoids hangs on blocked endpoints.
    function Test-TcpEndpoint {
        param([string]$HostName, [int]$Port, [int]$TimeoutMs = 3000)
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $null
        try {
            $iar = $client.BeginConnect($HostName, $Port, $null, $null)
            $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok) {
                try { $client.EndConnect($iar) } catch { }
                return $client.Connected
            }
            return $false
        } catch {
            return $false
        } finally {
            if ($iar -and $iar.AsyncWaitHandle) { $iar.AsyncWaitHandle.Dispose() }
            $client.Close()
        }
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-deep-diagnostic'
        $report = @()
        $issues = @()
        $msixPath = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'

        # Check 1: MSTeams AppX registration
        $pkg = Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue
        if ($pkg) {
            Write-ToolOutput ('[PASS] MSTeams registered: v{0}' -f $pkg.Version) -Level Success
            $report += ('MSTeams: v{0}' -f $pkg.Version)
        } else {
            Write-ToolOutput '[FAIL] MSTeams NOT registered for current user' -Level Error
            $report += 'MSTeams: not registered'; $issues += 'teams_not_registered'
        }

        # Check 2: MSIX package folder
        if (Test-Path -LiteralPath $msixPath) {
            $sz = (Get-ChildItem -LiteralPath $msixPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $mb = [math]::Round(($sz / 1MB), 1)
            Write-ToolOutput ('[PASS] MSIX folder present ({0} MB)' -f $mb) -Level Success
            $report += ('MSIX folder: {0} MB' -f $mb)
        } else {
            Write-ToolOutput '[WARN] MSIX package folder missing' -Level Warning
            $report += 'MSIX folder: missing'; $issues += 'msix_folder_missing'
        }

        # Check 3: dsregcmd AAD / WAM / PRT
        $dsreg = (dsregcmd /status 2>&1) -join "`n"
        if ($dsreg -match 'AzureAdJoined\s*:\s*YES') {
            Write-ToolOutput '[PASS] Azure AD Joined: YES' -Level Success; $report += 'AAD Joined: YES'
        } else {
            Write-ToolOutput '[WARN] Azure AD Joined: NO' -Level Warning; $report += 'AAD Joined: NO'; $issues += 'not_aad_joined'
        }
        if ($dsreg -match 'WamDefaultSet\s*:\s*YES') {
            Write-ToolOutput '[PASS] WAM Default Set: YES' -Level Success; $report += 'WAM Default: YES'
        } else {
            Write-ToolOutput '[WARN] WAM Default Set: NO' -Level Warning; $report += 'WAM Default: NO'; $issues += 'wam_not_configured'
        }
        $prt = 'Unknown'
        if ($dsreg -match 'AzureAdPrt\s*:\s*(\w+)') { $prt = $Matches[1] }
        Write-ToolOutput ('[INFO] Azure AD PRT: {0}' -f $prt) -Level Detail
        $report += ('AAD PRT: {0}' -f $prt)
        if ($prt -ne 'YES') { $issues += 'prt_missing' }

        # Check 4: AAD/WAM event log (needs elevation; degrade gracefully)
        try {
            $aadErr = @(Get-WinEvent -LogName 'Microsoft-Windows-AAD/Operational' -MaxEvents 50 -ErrorAction Stop |
                Where-Object { $_.Level -le 3 } | Select-Object -First 5)
            if ($aadErr.Count -gt 0) {
                Write-ToolOutput ('[WARN] {0} recent AAD/WAM error(s) in event log' -f $aadErr.Count) -Level Warning
                $report += ('AAD event log: {0} errors' -f $aadErr.Count); $issues += 'wam_event_errors'
            } else {
                Write-ToolOutput '[PASS] No recent AAD/WAM errors' -Level Success; $report += 'AAD event log: clean'
            }
        } catch {
            Write-ToolOutput '[INFO] Could not read AAD event log (needs elevation)' -Level Detail
            $report += 'AAD event log: not read'
        }

        # Check 5: Credential Manager Teams/M365 entries
        $credOut = (cmdkey /list 2>&1) | Out-String
        $teamsCreds = @(($credOut -split "`n") | Where-Object { $_ -match 'MicrosoftOffice|Teams|microsoftteams|aadg\.windows\.net|login\.microsoft' })
        if ($teamsCreds.Count -gt 0) {
            Write-ToolOutput ('[WARN] {0} Teams/M365 credential entr(ies) (may be stale)' -f $teamsCreds.Count) -Level Warning
            $report += ('Cred Manager: {0} entries' -f $teamsCreds.Count); $issues += 'stale_credentials'
        } else {
            Write-ToolOutput '[PASS] No stale Teams/M365 credentials' -Level Success; $report += 'Cred Manager: clean'
        }

        # Check 6: Network reachability (timeout-bounded)
        $endpoints = @(
            @{ Name = 'Teams';       HostName = 'teams.microsoft.com';       Port = 443 },
            @{ Name = 'Azure AD';    HostName = 'login.microsoftonline.com'; Port = 443 },
            @{ Name = 'MS Graph';    HostName = 'graph.microsoft.com';       Port = 443 },
            @{ Name = 'Teams media'; HostName = 'teams.microsoft.com';       Port = 3478 }
        )
        foreach ($ep in $endpoints) {
            if (Test-TcpEndpoint -HostName $ep.HostName -Port $ep.Port -TimeoutMs 3000) {
                Write-ToolOutput ('[PASS] {0} ({1}:{2})' -f $ep.Name, $ep.HostName, $ep.Port) -Level Success
                $report += ('Net {0}: PASS' -f $ep.Name)
            } else {
                Write-ToolOutput ('[FAIL] {0} ({1}:{2}) unreachable' -f $ep.Name, $ep.HostName, $ep.Port) -Level Error
                $report += ('Net {0}: FAIL' -f $ep.Name); $issues += 'network_blocked'
            }
        }

        # Check 7: TLS issuer (proxy-intercept hint)
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect('login.microsoftonline.com', 443)
            $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
            $ssl.AuthenticateAsClient('login.microsoftonline.com')
            $issuer = $ssl.RemoteCertificate.Issuer
            $ssl.Dispose(); $tcp.Dispose()
            if ($issuer -match 'Microsoft|DigiCert|GlobalSign|Comodo|Sectigo|Baltimore') {
                Write-ToolOutput ('[PASS] TLS issuer legitimate: {0}' -f $issuer) -Level Success
                $report += 'TLS: ok'
            } else {
                Write-ToolOutput ('[WARN] Unexpected TLS issuer (proxy intercept?): {0}' -f $issuer) -Level Warning
                $report += ('TLS: suspect - {0}' -f $issuer); $issues += 'tls_inspection'
            }
        } catch {
            Write-ToolOutput '[INFO] TLS check could not complete' -Level Detail
            $report += 'TLS: check failed'
        }

        # Check 8: Proxy configuration
        $winHttp = (netsh winhttp show proxy 2>&1) | Out-String
        $ieProp = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($ieProp.ProxyEnable -eq 1 -and $ieProp.ProxyServer) {
            Write-ToolOutput ('[WARN] User proxy enabled: {0}' -f $ieProp.ProxyServer) -Level Warning
            $report += ('Proxy: {0}' -f $ieProp.ProxyServer); $issues += 'proxy_configured'
        } elseif ($winHttp -match 'Proxy Server') {
            Write-ToolOutput '[WARN] WinHTTP proxy configured' -Level Warning
            $report += 'Proxy: WinHTTP'; $issues += 'proxy_configured'
        } else {
            Write-ToolOutput '[PASS] No proxy configured' -Level Success; $report += 'Proxy: none'
        }

        # Check 9: Teams firewall BLOCK rules
        $fw = @(Get-NetFirewallRule -DisplayName '*Teams*' -ErrorAction SilentlyContinue)
        $blocked = @($fw | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' })
        if ($blocked.Count -gt 0) {
            Write-ToolOutput ('[WARN] {0} active Teams BLOCK firewall rule(s)' -f $blocked.Count) -Level Warning
            $report += ('Firewall: {0} block rules' -f $blocked.Count); $issues += 'firewall_blocking'
        } else {
            Write-ToolOutput '[PASS] No active Teams BLOCK firewall rules' -Level Success; $report += 'Firewall: ok'
        }

        # Check 10: Teams scheduled tasks
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Teams' -or $_.TaskPath -match 'Teams' })
        Write-ToolOutput ('[INFO] Teams scheduled tasks: {0}' -f $tasks.Count) -Level Detail
        $report += ('Sched tasks: {0}' -f $tasks.Count)

        # Check 11: newest Teams log tail for auth errors
        $logBase = Join-Path $msixPath 'LocalCache\Microsoft\MSTeams\Logs'
        if (Test-Path -LiteralPath $logBase) {
            $latest = Get-ChildItem -LiteralPath $logBase -Filter '*.log' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                $authErr = @(Get-Content -LiteralPath $latest.FullName -Tail 200 -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match 'error|failed|unauthorized|401|403|token|auth' } | Select-Object -Last 5)
                if ($authErr.Count -gt 0) {
                    Write-ToolOutput ('[WARN] auth-related entries in {0}' -f $latest.Name) -Level Warning
                    $report += 'Teams logs: auth errors'; $issues += 'teams_log_auth_errors'
                } else {
                    Write-ToolOutput '[PASS] No recent auth errors in Teams log' -Level Success; $report += 'Teams logs: clean'
                }
            } else {
                Write-ToolOutput '[INFO] No Teams .log files' -Level Detail; $report += 'Teams logs: none'
            }
        } else {
            Write-ToolOutput '[INFO] Teams log dir not found' -Level Detail; $report += 'Teams logs: dir missing'
        }

        # Summary + report file
        $reportPath = Join-Path $env:TEMP ('TeamsDeepDiag_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        try { $report | Out-File -LiteralPath $reportPath -Encoding UTF8 -ErrorAction Stop; Write-ToolOutput ('Report saved: {0}' -f $reportPath) -Level Info } catch { }
        Write-ToolOutput ('Diagnostic complete: 11 checks, {0} issue(s) found.' -f $issues.Count) -Level Info
        if ($issues.Count -gt 0) { Write-ToolOutput ('Issue codes: {0}' -f ($issues -join ', ')) -Level Detail }

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Teams deep-repair action' -Choices @('None','ApplyRepairs') -Default 'None' -Silent:$Silent

        switch ($action) {

            'ApplyRepairs' {
                Write-ToolOutput 'WARNING: this CLOSES Teams and CLEARS its credentials/WAM tokens/cache - you will be signed out and must sign in again.' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Apply deep repairs (sign-out required)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary ('Diagnostic complete ({0} issues); repair cancelled' -f $issues.Count)
                } else {
                    foreach ($p in @('ms-teams','MSTeams','Teams','TeamsMeetingAddin')) {
                        Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Seconds 3
                    $removed = 0
                    $credLines = (cmdkey /list 2>&1) | Out-String
                    $targets = @(($credLines -split "`n") | Where-Object { $_ -match 'Target:' -and $_ -match 'MicrosoftOffice|microsoftteams|Teams|aadg\.windows\.net|login\.microsoft' })
                    foreach ($line in $targets) {
                        $t = ($line -replace '.*Target:\s*', '').Trim()
                        if ($t) { cmdkey /delete:$t 2>&1 | Out-Null; $removed++ }
                    }
                    Write-ToolOutput ('Cleared {0} credential entr(ies).' -f $removed) -Level Detail
                    foreach ($wp in @((Join-Path $msixPath 'Settings'), (Join-Path $msixPath 'AC\TokenBroker'))) {
                        if (Test-Path -LiteralPath $wp) {
                            Get-ChildItem -LiteralPath $wp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    $lc = Join-Path $msixPath 'LocalCache'
                    if (Test-Path -LiteralPath $lc) {
                        Get-ChildItem -LiteralPath $lc -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    $manifest = Join-Path $msixPath 'AppxManifest.xml'
                    if (Test-Path -LiteralPath $manifest) {
                        try {
                            Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
                            Write-ToolOutput 'MSTeams AppX re-registered.' -Level Detail
                        } catch {
                            Write-ToolOutput ('AppX re-register failed: {0} (reinstall Teams)' -f $_.Exception.Message) -Level Warning
                        }
                    } else {
                        Write-ToolOutput 'AppxManifest not found; Teams must be reinstalled.' -Level Warning
                    }
                    try {
                        Restart-Service -Name 'TokenBroker' -Force -ErrorAction Stop
                        Write-ToolOutput 'TokenBroker restarted.' -Level Detail
                    } catch {
                        Write-ToolOutput 'Could not restart TokenBroker (needs elevation; reboot recommended).' -Level Warning
                    }
                    Start-Process 'ms-teams:' -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    Complete-ToolRun $run -Status Success -Summary ('Deep repair applied ({0} creds cleared; WAM/MSIX cache cleared; AppX re-registered)' -f $removed)
                }
            }

            default {
                if ($issues.Count -gt 0) {
                    Complete-ToolRun $run -Status Warning -Summary ('Diagnostic complete: {0} issue(s) found; no repair applied' -f $issues.Count)
                } else {
                    Complete-ToolRun $run -Status Success -Summary 'Diagnostic complete: no issues found'
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same commands as Task 1 Step 3). Expected: `Failed: 0`.

- [ ] **Step 4: Smoke the silent diagnostic (read-only; no repair under None default)**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"
. "$r\src\tools\user\Repair-TeamsDeep.ps1"
Set-OutputSink -Sink Silent
Repair-TeamsDeep -Silent
$script:ToolRuns | ForEach-Object { '{0}: {1} - {2}' -f $_.Id, $_.Status, $_.Summary }
```
Expected: the 11 checks run (read-only; takes a few seconds for network probes), then a run record like `teams-deep-diagnostic: Warning - Diagnostic complete: N issue(s) found; no repair applied` (or `Success - no issues found`). NO Teams closed, NO credentials cleared. Paste the run-record line.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-TeamsDeep.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-TeamsDeep.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port teams batch 6b.2 (teams-deep-diagnostic)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 3: teams-camera-repair (84+97)

**Files:**
- Modify: `src\registry\tools.psd1` (append entry)
- Create: `src\tools\user\Repair-TeamsCamera.ps1`

- [ ] **Step 1: Append the registry entry** (last element of the Tools array):
```powershell
        @{
            Id            = 'teams-camera-repair'
            LegacyId      = '84'
            Name          = 'Teams Camera and Mic Repair'
            Category      = 'User'
            Function      = 'Repair-TeamsCamera'
            Description   = 'Fix Teams camera/mic: set Windows privacy access to Allow (FixPermissions) or reset the media stack - close hogging apps, clear media cache, restart FrameServer, cycle the camera device (ResetMediaStack)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','camera','microphone','media')
        }
```

- [ ] **Step 2: Create `src\tools\user\Repair-TeamsCamera.ps1`** with EXACTLY this content:
```powershell
function Repair-TeamsCamera {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-camera-repair'

        $camStore = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
        $micStore = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'

        # --- Report ---
        $cams = @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue)
        if ($cams.Count -eq 0) { $cams = @(Get-PnpDevice -FriendlyName '*camera*' -ErrorAction SilentlyContinue) }
        if ($cams.Count -gt 0) {
            Write-ToolOutput ('Camera devices: {0}' -f $cams.Count) -Level Info
            foreach ($c in $cams) { Write-ToolOutput ('  {0} [{1}]' -f $c.FriendlyName, $c.Status) -Level Detail }
        } else {
            Write-ToolOutput 'No camera devices found via PnP.' -Level Warning
        }

        $camVal = (Get-ItemProperty -Path $camStore -Name 'Value' -ErrorAction SilentlyContinue).Value
        $micVal = (Get-ItemProperty -Path $micStore -Name 'Value' -ErrorAction SilentlyContinue).Value
        $camLabel = '(unset)'; if ($camVal) { $camLabel = $camVal }
        $micLabel = '(unset)'; if ($micVal) { $micLabel = $micVal }
        Write-ToolOutput ('Camera access: {0}   Microphone access: {1}' -f $camLabel, $micLabel) -Level Detail

        $policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
        $policyBlock = $false
        if (Test-Path -LiteralPath $policyKey) {
            $camPol = (Get-ItemProperty -Path $policyKey -Name 'LetAppsAccessCamera' -ErrorAction SilentlyContinue).LetAppsAccessCamera
            $micPol = (Get-ItemProperty -Path $policyKey -Name 'LetAppsAccessMicrophone' -ErrorAction SilentlyContinue).LetAppsAccessMicrophone
            if ($camPol -eq 2 -or $micPol -eq 2) {
                Write-ToolOutput 'WARNING: camera/mic access is BLOCKED by IT policy (GPO/MDM) - cannot be overridden here.' -Level Warning
                $policyBlock = $true
            } else {
                Write-ToolOutput 'No GPO/MDM camera/mic policy block detected.' -Level Detail
            }
        } else {
            Write-ToolOutput 'No AppPrivacy policy key (no GPO/MDM block).' -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Teams camera action' `
            -Choices @('None','FixPermissions','ResetMediaStack') -Default 'None' -Silent:$Silent

        switch ($action) {

            'FixPermissions' {
                foreach ($store in @($camStore, $micStore)) {
                    if (-not (Test-Path -LiteralPath $store)) { New-Item -Path $store -Force | Out-Null }
                    Set-ItemProperty -Path $store -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
                    $np = Join-Path $store 'NonPackaged'
                    if (-not (Test-Path -LiteralPath $np)) { New-Item -Path $np -Force | Out-Null }
                    Set-ItemProperty -Path $np -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
                }
                $fixed = 0
                foreach ($store in @($camStore, $micStore)) {
                    $np = Join-Path $store 'NonPackaged'
                    if (Test-Path -LiteralPath $np) {
                        Get-ChildItem -LiteralPath $np -ErrorAction SilentlyContinue | ForEach-Object {
                            if ($_.PSChildName -match 'ms-teams|MSTeams|Teams') {
                                $v = (Get-ItemProperty -Path $_.PSPath -Name 'Value' -ErrorAction SilentlyContinue).Value
                                if ($v -eq 'Deny') {
                                    Set-ItemProperty -Path $_.PSPath -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
                                    $fixed++
                                }
                            }
                        }
                    }
                }
                foreach ($p in @('ms-teams','MSTeams','Teams')) { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue }
                Start-Sleep -Seconds 2
                Start-Process 'ms-teams:' -ErrorAction SilentlyContinue
                if ($policyBlock) {
                    Complete-ToolRun $run -Status Warning -Summary ('Camera/mic set to Allow ({0} Teams deny entries fixed) but an IT policy block is in effect' -f $fixed)
                } else {
                    Complete-ToolRun $run -Status Success -Summary ('Camera/mic set to Allow ({0} Teams deny entries fixed); Teams restarted' -f $fixed)
                }
            }

            'ResetMediaStack' {
                $hogs = @('Teams','ms-teams','MSTeams','WebexMeetings','zoom','CiscoCollabHost','lync','communicator','chrome','msedge','firefox','CameraApp')
                $running = @($hogs | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
                Write-ToolOutput 'WARNING: this CLOSES camera-using apps before resetting the media stack.' -Level Warning
                if ($running.Count -gt 0) { Write-ToolOutput ('Will close: {0}' -f ($running -join ', ')) -Level Detail }
                $confirm = Read-ToolChoice -Prompt 'Close those apps and reset the Teams camera/media stack?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ResetMediaStack cancelled'
                } else {
                    foreach ($p in $hogs) { Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
                    Start-Sleep -Seconds 2
                    $cachePaths = @(
                        (Join-Path $env:APPDATA 'Microsoft\Teams\Cache'),
                        (Join-Path $env:APPDATA 'Microsoft\Teams\blob_storage'),
                        (Join-Path $env:APPDATA 'Microsoft\Teams\databases'),
                        (Join-Path $env:APPDATA 'Microsoft\Teams\GPUCache'),
                        (Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB'),
                        (Join-Path $env:APPDATA 'Microsoft\Teams\Local Storage'),
                        (Join-Path $env:APPDATA 'Microsoft\Teams\tmp'),
                        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Cache'),
                        (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView')
                    )
                    $cleared = 0
                    foreach ($cp in $cachePaths) {
                        if (Test-Path -LiteralPath $cp) {
                            Get-ChildItem -LiteralPath $cp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                            $cleared++
                        }
                    }
                    if (Test-Path -LiteralPath $camStore) { Set-ItemProperty -Path $camStore -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue }
                    try {
                        Stop-Service -Name 'FrameServer' -Force -ErrorAction Stop
                        Start-Sleep -Seconds 2
                        Start-Service -Name 'FrameServer' -ErrorAction SilentlyContinue
                        Write-ToolOutput 'Camera Frame Server restarted.' -Level Detail
                    } catch {
                        Write-ToolOutput 'Could not restart FrameServer (needs elevation).' -Level Warning
                    }
                    $cycled = 0
                    foreach ($cam in $cams) {
                        try {
                            if ($cam.Status -eq 'OK') {
                                Disable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                Start-Sleep -Seconds 2
                                Enable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                $cycled++
                            } elseif ($cam.Status -eq 'Error') {
                                Enable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                $cycled++
                            }
                        } catch { }
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Media stack reset: {0} cache location(s) cleared, {1} camera device(s) cycled' -f $cleared, $cycled)
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Teams camera state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 3: Build + full suite** (same as Task 1 Step 3). Expected: `Failed: 0`.

- [ ] **Step 4: Smoke the silent refusal (RequiresAdmin)**
```powershell
$r = "$env:USERPROFILE\Desktop\NMMToolkit"
. "$r\src\core\02-output.ps1"; . "$r\src\core\03-results.ps1"; . "$r\src\core\04-dispatch.ps1"
$script:RegistryData = Import-PowerShellDataFile "$r\src\registry\tools.psd1"; $script:IsAdmin = $false
. "$r\src\tools\user\Repair-TeamsCamera.ps1"
$tool = Resolve-NmmTool -Query 'teams-camera-repair'
Write-Output ("RESULT: " + (Invoke-NmmTool -Tool $tool -Silent))
```
Expected: `RESULT: Refused` (RequiresAdmin + not elevated). Paste that line. Do NOT run the actions.

- [ ] **Step 5: ASCII/BOM/newline check + commit**
```powershell
$b=[IO.File]::ReadAllBytes('C:\Users\IT\Desktop\NMMToolkit\src\tools\user\Repair-TeamsCamera.ps1'); "BOM=$([bool]($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) NL=$($b[-1] -eq 0x0A) NonAscii=$(@($b[3..($b.Length-1)] | Where-Object {$_ -gt 126 -and $_ -ne 13 -and $_ -ne 10 -and $_ -ne 9}).Count)"
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add src/registry/tools.psd1 src/tools/user/Repair-TeamsCamera.ps1
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "feat: port teams batch 6b.3 (teams-camera-repair, 84+97 merged)"
```
Expect `BOM=True NL=True NonAscii=0`.

---

## Task 4: Sub-batch 6B close-out

**Files:**
- Modify: `docs\parity-checklist.md`

- [ ] **Step 1: Verify 73 tools and the User category**
```powershell
$lines = (& "$env:USERPROFILE\Desktop\NMMToolkit\dist\NMMTools.ps1" -ListTools | Out-String) -split "`r?`n"
$toolRows = $lines | Where-Object { $_ -match '\s(Browser|Cloud|Diagnostics|Laptop|Repair|User)\s+(ReadOnly|Modifies|Disruptive)\s' }
Write-Output ("Total tool rows: {0}" -f $toolRows.Count)
'Browser','Cloud','Diagnostics','Laptop','Repair','User' | ForEach-Object {
  $cat = $_
  '{0,-12} {1}' -f $cat, ($toolRows | Where-Object { $_ -match ('\s{0}\s+(ReadOnly|Modifies|Disruptive)\s' -f $cat) }).Count
}
```
Expected: Total = **73**; User = **7** (the 4 shell tools + teams-addin-repair, teams-deep-diagnostic, teams-camera-repair); Browser 2, Cloud 8, Diagnostics 23, Laptop 17, Repair 16. Quote the 3 new Teams rows.

- [ ] **Step 2: Confirm build + full suite are green**
```powershell
& "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
```
Expected: Build OK; `Failed: 0`.

- [ ] **Step 3: Update the parity checklist** in `docs\parity-checklist.md`:

(a) In the Common User Issues table, set the four ported/consolidated rows:
```markdown
| 83 | Teams Meeting Add-in Repair (Outlook button missing) | ported (batch 6b) | teams-addin-repair |
| 84 | Teams Camera/Mic Permissions Reset | ported (batch 6b) | teams-camera-repair |
| 85 | Teams Deep Diagnostic & Repair | ported (batch 6b) | teams-deep-diagnostic |
| 97 | Teams Camera & Media Stack Reset | consolidated -> tool 84 (teams-camera-repair) | — |
```
(b) Update the header count line from `70 of ~111 items ported` to `73 of ~111 items ported`, add `, 83, 84, 85` to the ported-items list, and add `97` to the consolidated list.

- [ ] **Step 4: Commit the docs**
```powershell
git -C "$env:USERPROFILE\Desktop\NMMToolkit" add docs/parity-checklist.md
git -C "$env:USERPROFILE\Desktop\NMMToolkit" commit -m "docs: batch 6b complete - parity checklist (73/106 ported)"
```

- [ ] **Step 5: Final review + finish the branch**

Review focus: every app-closing action is gated (RepairAddin warns+confirms before closing Outlook; ApplyRepairs warns about sign-out + confirms; ResetMediaStack warns + lists apps + confirms); all removals scoped to explicit Teams per-user paths (never a drive root); teams-deep-diagnostic's repair admin-steps (TokenBroker) degrade gracefully and its network checks use the timeout-bounded Test-TcpEndpoint; teams-camera-repair is admin-gated; -Silent is safe (report-only for addin, read-only diagnostic for deep, Refused for camera); FixPermissions reports (does not silently override) a GPO/MDM policy block.

Then invoke the **superpowers:finishing-a-development-branch** skill to merge `port/batch-6b-teams` to master. **NOTE:** use a simple single-line `-m` merge message (a here-string with a quoted word like 'User' previously mangled the git args). Verify the suite on the merged result before deleting the branch.

---

## Self-review (completed by plan author)

- **Spec coverage:** 3 tools -> Tasks 1-3; 84+97 merge -> Task 3 (FixPermissions + ResetMediaStack) + Task 4 parity (97 consolidated); report-then-action None-default -> every tool; process-kill gating -> RepairAddin (Outlook), ApplyRepairs (sign-out), ResetMediaStack (warn+list+confirm); deep-diagnostic 11 checks + Test-TcpEndpoint reuse -> Task 2; admin-graceful degradation (TokenBroker/FrameServer try/catch) -> Tasks 2-3; honest policy-block report -> Task 3 FixPermissions; verb rename Diagnose->Repair -> Task 2; 73-tool/User=7 verify -> Task 4.
- **Placeholder scan:** none - every step has complete code, exact commands, expected output.
- **Type/name consistency:** registry Function names (`Repair-TeamsAddin`, `Repair-TeamsDeep`, `Repair-TeamsCamera`) match the defined functions and the `New-ToolRun -Id` literals match each registry Id (`teams-addin-repair`, `teams-deep-diagnostic`, `teams-camera-repair`). All three use approved verb `Repair` and declare `[switch]$Silent`. The nested `Test-TcpEndpoint` in Repair-TeamsDeep is not registry-scanned (the registry/template tests enumerate top-level tool functions only), matching the existing Test-VPNHealth pattern.
