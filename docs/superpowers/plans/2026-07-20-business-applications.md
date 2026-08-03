# Business Applications Category Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `Business` tool category with three read-only diagnostic tools —
`Get-GlobalProtectStatus`, `Get-NitroProStatus`, `Get-RingCentralStatus` — following the design
in `docs/superpowers/specs/2026-07-20-business-applications-design.md`.

**Architecture:** Each tool is an independent, registry-listed PowerShell function in
`src\tools\business\`, following the standard five-element tool template used by every other
tool in this toolkit. No core files, GUI, or console menu changes are needed (both are
registry-driven).

**Tech Stack:** PowerShell 5.1, Pester >= 5.0, this repo's `New-ToolRun` / `Write-ToolOutput` /
`Complete-ToolRun` core API (`src\core\`).

## Global Constraints

- PowerShell 5.1 target. No PS7-only syntax (ternary, `??`, `?.`).
- `$var = if (...) { 'a' } else { 'b' }` is fine; a bare `(if ...)` expression is NOT — it
  throws `CommandNotFoundException` at runtime.
- ASCII only. No em dashes, smart quotes, or box-drawing characters.
- `Write-ToolOutput`, never `Write-Host`. Valid `-Level` values: `Info`, `Success`, `Warning`,
  `Error`, `Detail`.
- Every code path ends in exactly one `Complete-ToolRun` call with `Status` one of `Success`,
  `Warning`, `Failed`, `Skipped`. Never pass `Refused` (dispatcher-issued only).
- New category dir: `src\tools\business\` (lowercase). Registry `Category = 'Business'`
  (capitalized, single word).
- All three tools: `Risk = 'ReadOnly'`, `RequiresAdmin = $false`, `SilentCapable = $true`.
- LegacyId: next free numbers, `117`, `118`, `119` in task order below.
- Diagnostics only — no repair/fix behavior in any of these three tools.
- Prefer `DisplayName -match` scans over the registry `Uninstall\*` keys for install detection
  (see `Get-InstalledSoftware.ps1` for the existing pattern) rather than hardcoding a
  version-specific product GUID — more resilient across app versions, and avoids the exact-GUID
  verification risk called out in the design spec.
- `.\build.ps1` then `Invoke-Pester .\tests -CI` after every task. Registry tests fail the build
  if file, function, and registry entry disagree.

---

### Task 1: `Get-GlobalProtectStatus` tool

**Files:**
- Create: `src\tools\business\Get-GlobalProtectStatus.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Produces: `Get-GlobalProtectStatus -Silent:$Silent`, registry `Id = 'globalprotect-status'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\business\Get-GlobalProtectStatus.ps1`:

```powershell
function Get-GlobalProtectStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'globalprotect-status'

        # --- Install detection ---
        $regPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $installed = $null
        foreach ($path in $regPaths) {
            $installed = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'GlobalProtect' } |
                Select-Object -First 1
            if ($installed) { break }
        }
        if (-not $installed) {
            Write-ToolOutput 'GlobalProtect is not installed (no matching uninstall registry entry found)' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'GlobalProtect not installed'
            return
        }
        Write-ToolOutput ('Installed: {0} (version {1})' -f $installed.DisplayName, $installed.DisplayVersion) -Level Info

        # --- Service status ---
        $service = Get-Service -Name 'PanGPS' -ErrorAction SilentlyContinue
        $serviceLevel = 'Warning'
        $serviceText  = 'PanGPS service not found'
        if ($service) {
            $serviceText  = 'PanGPS service: {0}' -f $service.Status
            $serviceLevel = if ($service.Status -eq 'Running') { 'Info' } else { 'Warning' }
        }
        Write-ToolOutput $serviceText -Level $serviceLevel

        # --- Process check ---
        $process = Get-Process -Name 'PanGPA' -ErrorAction SilentlyContinue
        $processLevel = if ($process) { 'Info' } else { 'Warning' }
        $processText  = if ($process) { 'Running' } else { 'Not running' }
        Write-ToolOutput ('PanGPA process: {0}' -f $processText) -Level $processLevel

        # --- Active VPN adapter ---
        $vpnAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.InterfaceDescription -match 'GlobalProtect|Palo Alto' -and $_.Status -eq 'Up'
        } | Select-Object -First 1
        $connected = $null -ne $vpnAdapter
        $adapterLevel = if ($connected) { 'Info' } else { 'Warning' }
        $adapterText  = if ($connected) { 'Up ({0})' -f $vpnAdapter.Name } else { 'Not connected' }
        Write-ToolOutput ('VPN tunnel adapter: {0}' -f $adapterText) -Level $adapterLevel

        # --- Portal config ---
        $settingsKey = 'HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\Settings'
        $portal = $null
        if (Test-Path -LiteralPath $settingsKey) {
            $settings = Get-ItemProperty -LiteralPath $settingsKey -ErrorAction SilentlyContinue
            if ($settings -and $settings.PSObject.Properties.Name -contains 'Portal') {
                $portal = $settings.Portal
            }
        }
        $portalLevel = if ($portal) { 'Info' } else { 'Warning' }
        $portalText  = if ($portal) { $portal } else { 'Not found' }
        Write-ToolOutput ('Configured portal: {0}' -f $portalText) -Level $portalLevel

        # --- Log scan ---
        $logCandidates = @(
            'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.log',
            (Join-Path $env:LOCALAPPDATA 'Palo Alto Networks\GlobalProtect\PanGPA.log')
        )
        $logErrors = New-Object System.Collections.Generic.List[string]
        foreach ($logPath in $logCandidates) {
            if (Test-Path -LiteralPath $logPath) {
                try {
                    $tail = Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Last 300
                    $hits = @($tail | Where-Object { $_ -match 'fail|error|unreachable|denied|timeout' })
                    foreach ($h in ($hits | Select-Object -Last 5)) {
                        $logErrors.Add($h.Trim())
                    }
                } catch { }
            }
        }
        if ($logErrors.Count -gt 0) {
            Write-ToolOutput ('Recent log errors ({0}):' -f $logErrors.Count) -Level Warning
            foreach ($e in $logErrors) { Write-ToolOutput ('  {0}' -f $e) -Level Detail }
        } else {
            Write-ToolOutput 'No recent log errors found' -Level Detail
        }

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if ($serviceLevel -eq 'Warning') { $issues.Add('PanGPS service not running') }
        if (-not $connected)             { $issues.Add('VPN tunnel not connected') }
        if (-not $portal)                { $issues.Add('no portal configured') }
        if ($logErrors.Count -gt 0)      { $issues.Add('{0} recent log error(s)' -f $logErrors.Count) }

        $verdict = if ($issues.Count -eq 0) {
            'Connected, service healthy, no recent errors'
        } else {
            'Issues: ' + ($issues -join '; ')
        }
        Write-ToolOutput ('Verdict: {0}' -f $verdict) -Level Info

        $status = if ($issues.Count -eq 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status -Summary $verdict
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1`:

```powershell
        @{
            Id            = 'globalprotect-status'
            LegacyId      = '117'
            Name          = 'GlobalProtect VPN Status'
            Category      = 'Business'
            Function      = 'Get-GlobalProtectStatus'
            Description   = 'Checks GlobalProtect VPN connection state, service health, and recent log errors'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('globalprotect', 'vpn', 'paloalto', 'business')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green (structural registry/template tests confirm file,
function name, and registry entry agree).

- [ ] **Step 4: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool globalprotect-status -Silent -Mode Console`
Expected: exit code 0. On a machine without GlobalProtect installed (the normal dev box), output
shows the "not installed" Warning line and summary; exit code is still 0 per the Warning
exit-code contract.

- [ ] **Step 5: Commit**

```bash
git add src/tools/business/Get-GlobalProtectStatus.ps1 src/registry/tools.psd1
git commit -m "feat(business): add globalprotect-status tool"
```

---

### Task 2: `Get-NitroProStatus` tool

**Files:**
- Create: `src\tools\business\Get-NitroProStatus.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Produces: `Get-NitroProStatus -Silent:$Silent`, registry `Id = 'nitro-pro-status'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\business\Get-NitroProStatus.ps1`:

```powershell
function Get-NitroProStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'nitro-pro-status'

        # --- Install detection ---
        $regPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $installed = $null
        foreach ($path in $regPaths) {
            $installed = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'Nitro (PDF|Pro)' } |
                Select-Object -First 1
            if ($installed) { break }
        }
        if (-not $installed) {
            Write-ToolOutput 'Nitro PDF Pro is not installed (no matching uninstall registry entry found)' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'Nitro PDF Pro not installed'
            return
        }
        Write-ToolOutput ('Installed: {0} (version {1})' -f $installed.DisplayName, $installed.DisplayVersion) -Level Info

        # --- License / activation state ---
        $nitroBase     = 'HKLM:\SOFTWARE\Nitro\PDF Pro'
        $licenseFound  = $false
        $licenseStatus = 'Unknown'
        if (Test-Path -LiteralPath $nitroBase) {
            $verKeys = @(Get-ChildItem -LiteralPath $nitroBase -ErrorAction SilentlyContinue)
            foreach ($verKey in $verKeys) {
                $nlsPath = 'HKLM:\SOFTWARE\Nitro\PDF Pro\{0}\settings\NLS' -f $verKey.PSChildName
                if (Test-Path -LiteralPath $nlsPath) {
                    $nls = Get-ItemProperty -LiteralPath $nlsPath -ErrorAction SilentlyContinue
                    if ($nls) {
                        $licenseFound = $true
                        if ($nls.PSObject.Properties.Name -contains 'ActivationState') {
                            $licenseStatus = $nls.ActivationState
                        } elseif ($nls.PSObject.Properties.Name -contains 'IsActivated') {
                            $licenseStatus = if ($nls.IsActivated -eq 1) { 'Activated' } else { 'Trial' }
                        }
                    }
                    break
                }
            }
        }
        $licenseLevel = if ($licenseFound -and $licenseStatus -match 'Activ') { 'Info' } else { 'Warning' }
        $licenseText  = if ($licenseFound) { $licenseStatus } else { 'License registry key not found (unable to confirm activation state)' }
        Write-ToolOutput ('License state: {0}' -f $licenseText) -Level $licenseLevel

        # --- Process check ---
        $process = Get-Process -Name 'NitroPDF*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $processLevel = if ($process) { 'Info' } else { 'Detail' }
        $processText  = if ($process) { 'Running ({0})' -f $process.ProcessName } else { 'Not currently running' }
        Write-ToolOutput ('Process: {0}' -f $processText) -Level $processLevel

        # --- Default PDF handler ---
        $userChoiceKey  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice'
        $defaultHandler = 'Unknown'
        if (Test-Path -LiteralPath $userChoiceKey) {
            $choice = Get-ItemProperty -LiteralPath $userChoiceKey -ErrorAction SilentlyContinue
            if ($choice -and $choice.PSObject.Properties.Name -contains 'ProgId') {
                $defaultHandler = $choice.ProgId
            }
        }
        $isNitroDefault = $defaultHandler -match 'Nitro'
        $handlerLevel   = if ($isNitroDefault) { 'Info' } else { 'Warning' }
        Write-ToolOutput ('Default PDF handler: {0}' -f $defaultHandler) -Level $handlerLevel

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if (-not ($licenseFound -and $licenseStatus -match 'Activ')) { $issues.Add('license not confirmed activated') }
        if (-not $isNitroDefault) { $issues.Add('Nitro is not the default PDF handler') }

        $verdict = if ($issues.Count -eq 0) {
            'Installed, activated, set as default PDF handler'
        } else {
            'Issues: ' + ($issues -join '; ')
        }
        Write-ToolOutput ('Verdict: {0}' -f $verdict) -Level Info

        $status = if ($issues.Count -eq 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status -Summary $verdict
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1`:

```powershell
        @{
            Id            = 'nitro-pro-status'
            LegacyId      = '118'
            Name          = 'Nitro PDF Pro Status'
            Category      = 'Business'
            Function      = 'Get-NitroProStatus'
            Description   = 'Checks Nitro PDF Pro install, license/activation state, and default PDF handler'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('nitro', 'pdf', 'license', 'business')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green.

- [ ] **Step 4: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool nitro-pro-status -Silent -Mode Console`
Expected: exit code 0. On a machine without Nitro installed, output shows the "not installed"
Warning line and summary.

- [ ] **Step 5: Commit**

```bash
git add src/tools/business/Get-NitroProStatus.ps1 src/registry/tools.psd1
git commit -m "feat(business): add nitro-pro-status tool"
```

---

### Task 3: `Get-RingCentralStatus` tool

**Files:**
- Create: `src\tools\business\Get-RingCentralStatus.ps1`
- Modify: `src\registry\tools.psd1`

**Interfaces:**
- Produces: `Get-RingCentralStatus -Silent:$Silent`, registry `Id = 'ringcentral-status'`.

- [ ] **Step 1: Create the tool**

Create `src\tools\business\Get-RingCentralStatus.ps1`:

```powershell
function Get-RingCentralStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'ringcentral-status'

        # --- Install detection ---
        $installPaths = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\RingCentral'),
            (Join-Path $env:LOCALAPPDATA 'Glip')
        )
        $installDir = $null
        foreach ($p in $installPaths) {
            if (Test-Path -LiteralPath $p) { $installDir = $p; break }
        }
        if (-not $installDir) {
            Write-ToolOutput 'RingCentral is not installed (no matching install directory found under AppData\Local)' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'RingCentral not installed'
            return
        }
        Write-ToolOutput ('Installed: {0}' -f $installDir) -Level Info

        # --- Version (from install manifest if present) ---
        $version = 'Unknown'
        $verDir = Get-ChildItem -LiteralPath $installDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^app-\d' } | Sort-Object Name -Descending | Select-Object -First 1
        if ($verDir -and $verDir.Name -match '^app-(.+)$') {
            $version = $Matches[1]
        }
        Write-ToolOutput ('Version: {0}' -f $version) -Level Info

        # --- Process check ---
        $process = Get-Process -Name 'RingCentral' -ErrorAction SilentlyContinue | Select-Object -First 1
        $processLevel = if ($process) { 'Info' } else { 'Warning' }
        $processText  = if ($process) { 'Running' } else { 'Not running' }
        Write-ToolOutput ('Process: {0}' -f $processText) -Level $processLevel

        # --- Default audio device ---
        $audioDevice = Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
        $audioLevel = if ($audioDevice) { 'Info' } else { 'Warning' }
        $audioText  = if ($audioDevice) { $audioDevice.Name } else { 'No working audio device found' }
        Write-ToolOutput ('Audio device: {0}' -f $audioText) -Level $audioLevel

        # --- Log scan ---
        $logDir = Join-Path $env:LOCALAPPDATA 'RingCentral\RingCentralLogs'
        $logErrors = New-Object System.Collections.Generic.List[string]
        if (Test-Path -LiteralPath $logDir) {
            $latestLog = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestLog) {
                try {
                    $tail = Get-Content -LiteralPath $latestLog.FullName -ErrorAction SilentlyContinue | Select-Object -Last 300
                    $hits = @($tail | Where-Object { $_ -match 'error|fail|disconnect|timeout' })
                    foreach ($h in ($hits | Select-Object -Last 5)) {
                        $logErrors.Add($h.Trim())
                    }
                } catch { }
            }
        }
        if ($logErrors.Count -gt 0) {
            Write-ToolOutput ('Recent log errors ({0}):' -f $logErrors.Count) -Level Warning
            foreach ($e in $logErrors) { Write-ToolOutput ('  {0}' -f $e) -Level Detail }
        } else {
            Write-ToolOutput 'No recent log errors found' -Level Detail
        }

        # --- Reachability ---
        $target  = 'app.ringcentral.com'
        $dnsFail = $false
        try {
            [System.Net.Dns]::GetHostAddresses($target) | Out-Null
        } catch { $dnsFail = $true }
        $pingOk = $false
        if (-not $dnsFail) {
            $ping = Test-Connection -ComputerName $target -Count 2 -ErrorAction SilentlyContinue
            $pingOk = ($null -ne $ping) -and (@($ping).Count -gt 0)
        }
        $reachLevel = if (-not $dnsFail) { 'Info' } else { 'Warning' }
        $reachText  = if ($dnsFail) {
            'DNS resolution failed for {0}' -f $target
        } elseif ($pingOk) {
            'Reachable'
        } else {
            'DNS resolved, no ping reply (may be ICMP-blocked)'
        }
        Write-ToolOutput ('Service reachability ({0}): {1}' -f $target, $reachText) -Level $reachLevel

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if (-not $process)           { $issues.Add('app not running') }
        if (-not $audioDevice)       { $issues.Add('no working audio device') }
        if ($logErrors.Count -gt 0)  { $issues.Add('{0} recent log error(s)' -f $logErrors.Count) }
        if ($dnsFail)                { $issues.Add('service unreachable (DNS failure)') }

        $verdict = if ($issues.Count -eq 0) {
            'Installed and running, audio device present, no recent errors'
        } else {
            'Issues: ' + ($issues -join '; ')
        }
        Write-ToolOutput ('Verdict: {0}' -f $verdict) -Level Info

        $status = if ($issues.Count -eq 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status -Summary $verdict
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 2: Add the registry entry**

Append to the `Tools` array in `src\registry\tools.psd1`:

```powershell
        @{
            Id            = 'ringcentral-status'
            LegacyId      = '119'
            Name          = 'RingCentral App Status'
            Category      = 'Business'
            Function      = 'Get-RingCentralStatus'
            Description   = 'Checks RingCentral desktop app install/run state, audio device, and recent log errors'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('ringcentral', 'softphone', 'audio', 'business')
        }
```

- [ ] **Step 3: Build and run the full suite**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green.

- [ ] **Step 4: Manual smoke test**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Tool ringcentral-status -Silent -Mode Console`
Expected: exit code 0. On a machine without RingCentral installed, output shows the "not
installed" Warning line and summary.

- [ ] **Step 5: Commit**

```bash
git add src/tools/business/Get-RingCentralStatus.ps1 src/registry/tools.psd1
git commit -m "feat(business): add ringcentral-status tool"
```

---

### Task 4: Whole-branch verification

**Files:** none (verification only)

- [ ] **Step 1: Full clean build and test run**

Run: `.\build.ps1` then `Invoke-Pester .\tests -CI`
Expected: build succeeds, all tests green, artifact `dist\NMMTools.ps1` regenerated with all
three new tools and a `Business` category present.

- [ ] **Step 2: Confirm registry/category wiring end to end**

Run: `pwsh -NoProfile -File .\dist\NMMTools.ps1 -Mode Console -ListTools` (or the toolkit's
existing menu-listing invocation) and confirm all three `business` tools appear under the
`Business` category with the expected names and tags. If the console menu doesn't expose a
`-ListTools` flag, instead grep the built artifact for the three new `Id` values to confirm they
made it into the concatenated registry data.

- [ ] **Step 3: Report to the user**

Summarize: three tools added, category `Business` created, all tests passing, and the explicit
verification-risk items from the design spec (exact registry keys / log paths for each app) that
still need confirming against a real install of each app before this is trusted in the field.
No commit in this task (nothing changes) — shipping (build -> test -> copy to Desktop -> sync to
the private repo) is a separate, explicit step via the `/nmm-ship` skill per `CLAUDE.md`, not run
as part of this plan.
