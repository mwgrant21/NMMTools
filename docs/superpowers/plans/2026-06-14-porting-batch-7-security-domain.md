# Batch 7 (Security/Domain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port v8 Security/Domain tools 51, 91, 92, 93, 101 into v9 as five new `Security`-category tools, each following the report-then-action pattern.

**Architecture:** One tool = one file in a NEW `src/tools/security/` folder defining one top-level function, plus one entry in `src/registry/tools.psd1`. `build.ps1` already recurses `src/tools`, so the new folder builds automatically; the landing menu letters categories alphabetically, so `Security` auto-inserts with no menu code change. Destructive/credentialed arms are gated behind `Read-ToolChoice -Default 'None' -Silent:$Silent` so `-Silent` is report-only.

**Tech Stack:** PowerShell 5.1; Pester 5.x; single-file build via `build.ps1`; PSScriptAnalyzer (errors gate the build).

**Spec:** `docs/superpowers/specs/2026-06-14-batch-7-security-domain-design.md`

---

## Conventions every task must follow

- **PS 5.1 only:** no ternary, `??`, `&&`/`||`. Never ASSIGN `$input`/`$matches`/`$profile`. Approved verbs only.
- **`New-ToolRun -Id '<id>'`** literal MUST equal the registry `Id`.
- **Nested helper functions** (e.g. `Get-LastSyncLine`) are defined *inside* the tool function so the registry scanner (top-level only) ignores them.
- **Encoding:** ASCII-only source, UTF-8 **with BOM**, trailing newline. Write the file, then run the encoding fix (shown in Task 1 Step 3).
- **Status enum:** `Complete-ToolRun -Status` accepts only `Success | Failed | Warning | Skipped`. `Error` is a `Write-ToolOutput -Level`, not a status. `Write-ToolOutput -Level` accepts `Info | Success | Warning | Error | Detail`.
- **Interactive-only prompts:** `Read-Host` (typed confirms) and `Get-Credential` are reached ONLY after an interactive action selection; under `-Silent` the action defaults to `None`, so they never run unattended. This is the sanctioned free-text exception.
- **Build + test after every tool:**
  ```powershell
  Import-Module Pester -MinimumVersion 5.0
  & "$env:USERPROFILE\Desktop\NMMToolkit\build.ps1"
  Invoke-Pester -Path "$env:USERPROFILE\Desktop\NMMToolkit\tests" -Output Minimal
  ```
  Expected: build succeeds, all tests green, the registry/template counts rise by one each tool.
- **Commit message:** single-line `-m` only (never a here-string).

## File Structure

- Create: `src/tools/security/Repair-DomainTrust.ps1` (Task 1)
- Create: `src/tools/security/Repair-TimeSync.ps1` (Task 2)
- Create: `src/tools/security/Get-LocalAdminAudit.ps1` (Task 3)
- Create: `src/tools/security/Get-DefenderStatus.ps1` (Task 4)
- Create: `src/tools/security/Set-RemoteDesktop.ps1` (Task 5)
- Modify: `src/registry/tools.psd1` — append one entry per tool, inserted before the closing `    )` that follows the LAST current entry (`outlook-addin-repair`).
- Modify: `docs/parity-checklist.md` (Task 6)

---

### Task 1: domain-trust-repair (v8 51)

**Files:**
- Create: `src/tools/security/Repair-DomainTrust.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Repair-DomainTrust {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'domain-trust-repair'
        $domain = $env:USERDNSDOMAIN

        # --- Report ---
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        Write-ToolOutput ('Computer: {0}' -f $cs.Name) -Level Info
        Write-ToolOutput ('Domain: {0}  (PartOfDomain={1})' -f $cs.Domain, $cs.PartOfDomain) -Level Detail

        if (-not $cs.PartOfDomain) {
            Write-ToolOutput 'This computer is not joined to a domain; domain-trust repair does not apply.' -Level Warning
            Complete-ToolRun $run -Status Success -Summary 'Not domain-joined; no action'
            return
        }

        $sc = $false
        try { $sc = [bool](Test-ComputerSecureChannel -ErrorAction Stop) } catch { $sc = $false }
        if ($sc) { Write-ToolOutput 'Secure channel: OK' -Level Detail }
        else     { Write-ToolOutput 'Secure channel: BROKEN' -Level Warning }

        $dc = nltest ('/dclist:{0}' -f $domain) 2>$null
        if ($LASTEXITCODE -eq 0 -and $dc) {
            Write-ToolOutput 'Domain controllers:' -Level Detail
            foreach ($line in ($dc | Select-String '^\s+\w')) { Write-ToolOutput ('  {0}' -f ([string]$line).Trim()) -Level Detail }
        } else {
            Write-ToolOutput 'Domain controller list unavailable (nltest failed).' -Level Warning
        }

        $dns = $false
        try { $null = Resolve-DnsName -Name $domain -Type A -ErrorAction Stop; $dns = $true } catch { $dns = $false }
        if ($dns) { Write-ToolOutput ('DNS resolution of {0}: OK' -f $domain) -Level Detail }
        else      { Write-ToolOutput ('DNS resolution of {0}: FAILED' -f $domain) -Level Warning }

        $null = w32tm /query /status 2>$null
        if ($LASTEXITCODE -eq 0) { Write-ToolOutput 'Time service: responding' -Level Detail }
        else { Write-ToolOutput 'Time service: not responding (see time-sync-repair)' -Level Warning }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Domain trust action' `
            -Choices @('None','TestSecureChannel','RepairSecureChannel','ResetMachinePassword','ResyncTime','PurgeKerberos','RejoinDomain','ShowDetails') -Default 'None' -Silent:$Silent

        switch ($action) {

            'TestSecureChannel' {
                $ok = $false
                try { $ok = [bool](Test-ComputerSecureChannel -ErrorAction Stop) } catch { $ok = $false }
                if ($ok) { Complete-ToolRun $run -Status Success -Summary 'Secure channel OK' }
                else     { Complete-ToolRun $run -Status Warning -Summary 'Secure channel BROKEN - try RepairSecureChannel or ResetMachinePassword' }
            }

            'RepairSecureChannel' {
                $cred = Get-Credential -Message 'Enter domain admin credentials to repair the secure channel'
                if (-not $cred) { Complete-ToolRun $run -Status Skipped -Summary 'RepairSecureChannel cancelled (no credentials)'; return }
                try {
                    $ok = [bool](Test-ComputerSecureChannel -Repair -Credential $cred -ErrorAction Stop)
                    if ($ok) { Complete-ToolRun $run -Status Success -Summary 'Secure channel repaired' }
                    else     { Complete-ToolRun $run -Status Warning -Summary 'Secure channel repair returned false' }
                } catch { Complete-ToolRun $run -Status Failed -Summary ('Repair failed: {0}' -f $_.Exception.Message) }
            }

            'ResetMachinePassword' {
                $cred = Get-Credential -Message 'Enter domain admin credentials to reset the computer account password'
                if (-not $cred) { Complete-ToolRun $run -Status Skipped -Summary 'ResetMachinePassword cancelled (no credentials)'; return }
                try {
                    Reset-ComputerMachinePassword -Credential $cred -ErrorAction Stop
                    Complete-ToolRun $run -Status Success -Summary 'Computer account password reset; restart recommended'
                } catch { Complete-ToolRun $run -Status Failed -Summary ('Reset failed: {0}' -f $_.Exception.Message) }
            }

            'ResyncTime' {
                w32tm /resync /force 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Complete-ToolRun $run -Status Success -Summary 'Time resynced (see time-sync-repair for deep repair)' }
                else { Complete-ToolRun $run -Status Warning -Summary 'w32tm /resync failed; try time-sync-repair' }
            }

            'PurgeKerberos' {
                klist purge 2>$null | Out-Null
                Complete-ToolRun $run -Status Success -Summary 'Kerberos tickets purged; user may need to re-authenticate'
            }

            'RejoinDomain' {
                $typed = Read-Host 'WARNING: this unjoins then rejoins the domain and needs a restart. Type REJOIN to proceed'
                if ($typed -ne 'REJOIN') { Complete-ToolRun $run -Status Skipped -Summary 'RejoinDomain cancelled (confirmation not typed)'; return }
                $cred = Get-Credential -Message 'Enter domain admin credentials to rejoin the domain'
                if (-not $cred) { Complete-ToolRun $run -Status Skipped -Summary 'RejoinDomain cancelled (no credentials)'; return }
                try {
                    Remove-Computer -UnjoinDomainCredential $cred -WorkgroupName 'WORKGROUP' -Force -ErrorAction Stop
                    Start-Sleep -Seconds 3
                    Add-Computer -DomainName $cs.Domain -Credential $cred -Force -ErrorAction Stop
                    Write-ToolOutput 'Domain rejoin complete; a restart is required to finish.' -Level Success
                    $restart = Read-ToolChoice -Prompt 'Restart now?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                    if ($restart -eq 'Yes') { shutdown /r /t 10 /c 'Restarting after domain rejoin' | Out-Null }
                    Complete-ToolRun $run -Status Success -Summary 'Domain rejoined; restart required'
                } catch { Complete-ToolRun $run -Status Failed -Summary ('Rejoin failed: {0}' -f $_.Exception.Message) }
            }

            'ShowDetails' {
                Write-ToolOutput 'Device join status (dsregcmd):' -Level Detail
                foreach ($l in (dsregcmd /status 2>$null | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined')) { Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail }
                Write-ToolOutput 'Domain controller (nltest /dsgetdc):' -Level Detail
                foreach ($l in (nltest ('/dsgetdc:{0}' -f $domain) 2>$null)) { Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail }
                Complete-ToolRun $run -Status Success -Summary 'Domain details displayed'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Domain trust state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** in `src/registry/tools.psd1`, immediately after the `outlook-addin-repair` entry's closing `}` and before the closing `    )`:

```powershell
        @{
            Id            = 'domain-trust-repair'
            LegacyId      = '51'
            Name          = 'Domain Trust and Connection Repair'
            Category      = 'Security'
            Function      = 'Repair-DomainTrust'
            Description   = 'Report domain join, secure channel, DC list, DNS and time, then test/repair the secure channel, reset the machine password, resync time, purge Kerberos tickets, rejoin the domain (typed REJOIN), or show detailed domain info'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('domain','kerberos','securechannel','nltest','ad')
        }
```

- [ ] **Step 3: Fix encoding** (BOM + CRLF + trailing newline). Run:

```powershell
$f = "$env:USERPROFILE\Desktop\NMMToolkit\src\tools\security\Repair-DomainTrust.ps1"
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

Expected: build succeeds; all tests pass; registry reports 87 tools; a new `F=Security` category appears in `-ListTools`.

- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): domain-trust-repair (port v8 51)"
```

---

### Task 2: time-sync-repair (v8 91)

**Files:**
- Create: `src/tools/security/Repair-TimeSync.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Repair-TimeSync {
    [CmdletBinding()]
    param([switch]$Silent)

    # Return the "Last Successful Sync Time" line from w32tm status, or $null.
    function Get-LastSyncLine {
        $st = w32tm /query /status 2>$null
        $line = $st | Select-String 'Last Successful Sync Time'
        if ($line) { return ([string]$line).Trim() }
        return $null
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'time-sync-repair'

        # --- Report ---
        Write-ToolOutput ('System time: {0}' -f (Get-Date)) -Level Info
        $status = w32tm /query /status 2>$null
        if ($LASTEXITCODE -eq 0 -and $status) {
            foreach ($l in ($status | Select-String 'Source|Stratum|Last Successful Sync Time')) {
                Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail
            }
        } else {
            Write-ToolOutput 'w32tm /query /status did not respond (W32Time may be stopped).' -Level Warning
        }
        $peers = w32tm /query /peers 2>$null
        $peer = $peers | Select-String 'Peer:' | Select-Object -First 1
        if ($peer) { Write-ToolOutput ('NTP peer: {0}' -f ([string]$peer).Trim()) -Level Detail }
        else { Write-ToolOutput 'No NTP peers configured/reachable.' -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Time sync action' -Choices @('None','Resync','FullRepair') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success -Summary 'Time sync state reported; no action taken'
            return
        }

        $w32 = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
        if ($w32 -and $w32.Status -ne 'Running') { Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue }

        if ($action -eq 'FullRepair') {
            w32tm /unregister 2>$null | Out-Null
            w32tm /register 2>$null | Out-Null
            Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue
            $dom = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain
            if ($dom -and $dom -ne 'WORKGROUP') {
                w32tm /config /syncfromflags:domhier /update 2>$null | Out-Null
                Write-ToolOutput ('Configured to sync from domain hierarchy ({0}).' -f $dom) -Level Detail
            } else {
                w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update 2>$null | Out-Null
                Write-ToolOutput 'Configured to sync from time.windows.com.' -Level Detail
            }
        }

        w32tm /resync /force 2>$null | Out-Null
        $resyncOk = ($LASTEXITCODE -eq 0)
        Start-Sleep -Seconds 2

        $last = Get-LastSyncLine
        if ($last) { Write-ToolOutput ('After resync: {0}' -f $last) -Level Detail }
        Write-ToolOutput 'NOTE: Kerberos auth fails when clock drift exceeds 5 minutes.' -Level Detail

        if ($resyncOk) {
            Complete-ToolRun $run -Status Success -Summary ('{0} complete; time resynced' -f $action)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('{0} ran but w32tm /resync did not confirm sync (source may be unreachable)' -f $action)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `domain-trust-repair`, before the closing `    )`):

```powershell
        @{
            Id            = 'time-sync-repair'
            LegacyId      = '91'
            Name          = 'Time Sync Repair'
            Category      = 'Security'
            Function      = 'Repair-TimeSync'
            Description   = 'Report w32tm status and NTP peers, then resync the clock or full-repair the Windows Time service (re-register, configure source, resync); Kerberos fails past 5 min drift'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('time','w32tm','ntp','kerberos','sync')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, with `$f` = `Repair-TimeSync.ps1`.
- [ ] **Step 4: Build and test** — Expected: 88 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): time-sync-repair (port v8 91)"
```

---

### Task 3: local-admin-audit (v8 92)

**Files:**
- Create: `src/tools/security/Get-LocalAdminAudit.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Get-LocalAdminAudit {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'local-admin-audit'
        $expected = @('Administrator','Domain Admins','Enterprise Admins')

        # --- Report ---
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop)
        Write-ToolOutput ('Local Administrators members: {0}' -f $admins.Count) -Level Info
        $unexpected = New-Object System.Collections.Generic.List[object]
        foreach ($a in $admins) {
            $short = $a.Name -replace '.*\\', ''
            $isExpected = $false
            foreach ($e in $expected) { if ($short -like $e) { $isExpected = $true } }
            $disabled = $false
            $pwdNeverExp = $false
            $lastLogon = 'N/A'
            if ($a.PrincipalSource -eq 'Local') {
                $lu = Get-LocalUser -Name $short -ErrorAction SilentlyContinue
                if ($lu) {
                    $disabled = -not $lu.Enabled
                    $pwdNeverExp = $lu.PasswordNeverExpires
                    if ($lu.LastLogon) { $lastLogon = $lu.LastLogon.ToString('yyyy-MM-dd HH:mm') } else { $lastLogon = 'Never' }
                }
            }
            $flags = @()
            if ($disabled) { $flags += 'DISABLED' }
            if ($pwdNeverExp) { $flags += 'PWD-NEVER-EXPIRES' }
            $isUnexpected = (-not $isExpected) -and (-not $disabled)
            if ($isUnexpected) { $flags += 'UNEXPECTED'; $unexpected.Add($a) }
            $flagStr = ''
            if ($flags.Count -gt 0) { $flagStr = ('  [{0}]' -f ($flags -join ', ')) }
            $lvl = 'Detail'
            if ($isUnexpected) { $lvl = 'Warning' }
            Write-ToolOutput ('  {0}  ({1})  last logon: {2}{3}' -f $a.Name, $a.PrincipalSource, $lastLogon, $flagStr) -Level $lvl
        }

        $builtin = Get-LocalUser -Name 'Administrator' -ErrorAction SilentlyContinue
        if ($builtin) {
            if ($builtin.Enabled) { Write-ToolOutput 'Built-in Administrator: ENABLED (consider disabling if not required)' -Level Warning }
            else { Write-ToolOutput 'Built-in Administrator: disabled (good)' -Level Detail }
        }

        # --- Action menu ---
        if ($unexpected.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary ('{0} admin(s); all expected' -f $admins.Count)
            return
        }

        Write-ToolOutput ('{0} unexpected active admin account(s) found.' -f $unexpected.Count) -Level Warning
        $action = Read-ToolChoice -Prompt 'Disable unexpected LOCAL admin accounts?' -Choices @('None','DisableUnexpected') -Default 'None' -Silent:$Silent

        if ($action -ne 'DisableUnexpected') {
            Complete-ToolRun $run -Status Warning -Summary ('{0} unexpected active admin(s); no action taken' -f $unexpected.Count)
            return
        }

        $disabledCount = 0
        foreach ($a in $unexpected) {
            $short = $a.Name -replace '.*\\', ''
            if ($a.PrincipalSource -eq 'Local') {
                $lu = Get-LocalUser -Name $short -ErrorAction SilentlyContinue
                if ($lu -and $lu.Enabled) {
                    try {
                        Disable-LocalUser -Name $short -ErrorAction Stop
                        $disabledCount++
                        Write-ToolOutput ('  Disabled: {0}' -f $short) -Level Detail
                    } catch {
                        Write-ToolOutput ('  Could not disable {0}: {1}' -f $short, $_.Exception.Message) -Level Warning
                    }
                }
            } else {
                Write-ToolOutput ('  {0} is a domain account - cannot disable locally.' -f $a.Name) -Level Detail
            }
        }
        Complete-ToolRun $run -Status Success -Summary ('Disabled {0} of {1} unexpected admin account(s)' -f $disabledCount, $unexpected.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `time-sync-repair`, before the closing `    )`):

```powershell
        @{
            Id            = 'local-admin-audit'
            LegacyId      = '92'
            Name          = 'Local Admin Account Audit'
            Category      = 'Security'
            Function      = 'Get-LocalAdminAudit'
            Description   = 'Audit the local Administrators group, flag unexpected active accounts and the built-in Administrator, then optionally disable the unexpected LOCAL accounts'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('admin','audit','localgroup','security','accounts')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Get-LocalAdminAudit.ps1`.
- [ ] **Step 4: Build and test** — Expected: 89 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): local-admin-audit (port v8 92)"
```

---

### Task 4: defender-status (v8 93)

**Files:**
- Create: `src/tools/security/Get-DefenderStatus.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Get-DefenderStatus {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'defender-status'

        # --- Report ---
        $d = $null
        try { $d = Get-MpComputerStatus -ErrorAction Stop } catch { $d = $null }
        if (-not $d) {
            Write-ToolOutput 'Could not query Windows Defender - a third-party AV may be active.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'Defender not queryable (third-party AV may be active)'
            return
        }

        if ($d.RealTimeProtectionEnabled) { Write-ToolOutput 'Real-Time Protection: Enabled' -Level Info }
        else { Write-ToolOutput 'Real-Time Protection: DISABLED' -Level Warning }

        $defAgeH = $null
        if ($d.AntivirusSignatureLastUpdated) { $defAgeH = [math]::Round(((Get-Date) - $d.AntivirusSignatureLastUpdated).TotalHours, 1) }
        Write-ToolOutput ('Definitions: {0} (age {1} h)' -f $d.AntivirusSignatureVersion, $defAgeH) -Level Detail
        if ($d.LastQuickScanEndTime) {
            $scanDays = [math]::Round(((Get-Date) - $d.LastQuickScanEndTime).TotalDays, 1)
            Write-ToolOutput ('Last quick scan: {0} ({1} days ago)' -f $d.LastQuickScanEndTime.ToString('yyyy-MM-dd HH:mm'), $scanDays) -Level Detail
        }
        Write-ToolOutput ('AV={0}  AntiSpyware={1}  BehaviorMonitor={2}  NIS={3}  Tamper={4}' -f $d.AntivirusEnabled, $d.AntispywareEnabled, $d.BehaviorMonitorEnabled, $d.NisEnabled, $d.IsTamperProtected) -Level Detail

        $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue)
        if ($threats.Count -gt 0) {
            Write-ToolOutput ('ACTIVE THREATS: {0}' -f $threats.Count) -Level Warning
            foreach ($t in $threats) { Write-ToolOutput ('  - {0} (severity {1})' -f $t.ThreatName, $t.SeverityID) -Level Warning }
        } else {
            Write-ToolOutput 'No active threats detected.' -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Defender action' -Choices @('None','UpdateSignatures') -Default 'None' -Silent:$Silent

        if ($action -eq 'UpdateSignatures') {
            try {
                Update-MpSignature -ErrorAction Stop
                Complete-ToolRun $run -Status Success -Summary 'Defender signature update initiated'
            } catch {
                Complete-ToolRun $run -Status Warning -Summary ('Signature update failed: {0}' -f $_.Exception.Message)
            }
            return
        }

        $rtpOff = -not $d.RealTimeProtectionEnabled
        $stale = ($null -ne $defAgeH) -and ($defAgeH -gt 72)
        if ($rtpOff -or $stale -or ($threats.Count -gt 0)) {
            Complete-ToolRun $run -Status Warning -Summary ('Attention: RTP-on={0} stale-defs={1} threats={2}' -f $d.RealTimeProtectionEnabled, $stale, $threats.Count)
        } else {
            Complete-ToolRun $run -Status Success -Summary 'Defender healthy: RTP on, defs current, no threats'
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `local-admin-audit`, before the closing `    )`). Note `RequiresAdmin = $false`:

```powershell
        @{
            Id            = 'defender-status'
            LegacyId      = '93'
            Name          = 'Windows Defender Security Status'
            Category      = 'Security'
            Function      = 'Get-DefenderStatus'
            Description   = 'Report Windows Defender real-time protection, definition age, last scan, threats and tamper protection, then optionally update signatures; warns if a third-party AV is active'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('defender','antivirus','security','threats','signatures')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Get-DefenderStatus.ps1`.
- [ ] **Step 4: Build and test** — Expected: 90 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): defender-status (port v8 93)"
```

---

### Task 5: rdp-config (v8 101)

**Files:**
- Create: `src/tools/security/Set-RemoteDesktop.ps1`
- Modify: `src/registry/tools.psd1`

- [ ] **Step 1: Create the tool file** with exactly this content:

```powershell
function Set-RemoteDesktop {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'rdp-config'
        $tsKey  = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
        $rdpKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

        # --- Report ---
        $deny = (Get-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
        if ($deny -eq 0) { Write-ToolOutput 'Remote Desktop: ENABLED (fDenyTSConnections=0)' -Level Info }
        else { Write-ToolOutput 'Remote Desktop: disabled (fDenyTSConnections=1)' -Level Info }
        $nla = (Get-ItemProperty -LiteralPath $rdpKey -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
        Write-ToolOutput ('NLA (UserAuthentication): {0}' -f $nla) -Level Detail
        $fw = @(Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue)
        $fwEnabled = @($fw | Where-Object { $_.Enabled -eq 'True' }).Count
        Write-ToolOutput ('Remote Desktop firewall rules enabled: {0} of {1}' -f $fwEnabled, $fw.Count) -Level Detail
        $svc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
        if ($svc) { Write-ToolOutput ('TermService: {0} (StartType {1})' -f $svc.Status, $svc.StartType) -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Remote Desktop action' -Choices @('None','Enable','Disable') -Default 'None' -Silent:$Silent

        switch ($action) {

            'Enable' {
                $typed = Read-Host 'Enabling RDP increases this machine''s attack surface. Type ENABLE to proceed'
                if ($typed -ne 'ENABLE') { Complete-ToolRun $run -Status Skipped -Summary 'Enable cancelled (confirmation not typed)'; return }
                Set-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -Value 0 -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $rdpKey -Name 'UserAuthentication' -Value 1 -Force -ErrorAction SilentlyContinue
                Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
                Set-Service -Name 'TermService' -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name 'TermService' -ErrorAction SilentlyContinue
                $now = (Get-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
                if ($now -eq 0) { Complete-ToolRun $run -Status Success -Summary 'Remote Desktop enabled (NLA on, firewall opened)' }
                else { Complete-ToolRun $run -Status Warning -Summary 'fDenyTSConnections did not update to 0' }
            }

            'Disable' {
                Set-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -Value 1 -Force -ErrorAction SilentlyContinue
                Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
                $now = (Get-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
                if ($now -eq 1) { Complete-ToolRun $run -Status Success -Summary 'Remote Desktop disabled (firewall group disabled)' }
                else { Complete-ToolRun $run -Status Warning -Summary 'fDenyTSConnections did not update to 1' }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Remote Desktop state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Append the registry entry** (after `defender-status`, before the closing `    )`). Note `Risk = 'Disruptive'`:

```powershell
        @{
            Id            = 'rdp-config'
            LegacyId      = '101'
            Name          = 'Remote Desktop Configuration'
            Category      = 'Security'
            Function      = 'Set-RemoteDesktop'
            Description   = 'Report Remote Desktop state (fDenyTSConnections, NLA, firewall, TermService), then enable RDP (typed ENABLE - increases exposure) or disable it (re-deny + close firewall)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('rdp','remotedesktop','firewall','nla','termservice')
        }
```

- [ ] **Step 3: Fix encoding** — Task 1 Step 3 command, `$f` = `Set-RemoteDesktop.ps1`.
- [ ] **Step 4: Build and test** — Expected: 91 tools, all green.
- [ ] **Step 5: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "feat(7): rdp-config (port v8 101)"
```

---

### Task 6: Update parity checklist

**Files:**
- Modify: `docs/parity-checklist.md`

- [ ] **Step 1: Update the header count.** Change the header line to read `updated batch 7 close-out. **91 of ~111 items ported**` and append `51, 91, 92, 93, 101` to the ported list. (Consolidated list is unchanged.)

- [ ] **Step 2: Update the Security & Domain table rows** for 51, 91, 92, 93, 101:

| v8 # | new Status | v9 Id |
|---|---|---|
| 51 | `ported (batch 7)` | `domain-trust-repair` |
| 91 | `ported (batch 7)` | `time-sync-repair` |
| 92 | `ported (batch 7)` | `local-admin-audit` |
| 93 | `ported (batch 7)` | `defender-status` |
| 101 | `ported (batch 7)` | `rdp-config` |

- [ ] **Step 3: Commit.**

```powershell
cd "$env:USERPROFILE\Desktop\NMMToolkit"; git add -A; git commit -m "docs(7): parity checklist - 91 tools, only Quick Fixes Q1-Q9 remain"
```

---

## Self-Review (controller, after all tasks)

- **Spec coverage:** five tool files (51/91/92/93/101) under the new `Security` category — all present. Every report field and action arm in the spec maps to a `switch`/`if` branch above.
- **Type/name consistency:** every `New-ToolRun -Id '<id>'` literal matches its registry `Id`; each file's function name matches the registry `Function` (`Repair-DomainTrust`, `Repair-TimeSync`, `Get-LocalAdminAudit`, `Get-DefenderStatus`, `Set-RemoteDesktop`).
- **Status enum:** no `Complete-ToolRun -Status Error` anywhere; `Error` appears only as `Write-ToolOutput -Level` where used.
- **Admin/Risk:** domain-trust & rdp = Disruptive; defender = RequiresAdmin $false; others admin/Modifies — matches the spec table.
- **Interactive prompts:** `Get-Credential` and `Read-Host` only inside action branches, never in the always-run report; `-Silent` defaults every action to None.

## Final review + finish

After Task 6, dispatch a whole-batch reviewer (constrained `general-purpose`: "output ONLY your review; do not modify files/memory/commit") over the five new tool files + registry diff (focus on the credentialed/rejoin paths in domain-trust and the RDP enable path), fix anything it flags, then use **superpowers:finishing-a-development-branch** to merge `batch-7-security-domain` to master locally (single-line `-m` merge message).
