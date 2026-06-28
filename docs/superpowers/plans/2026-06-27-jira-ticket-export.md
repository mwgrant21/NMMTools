# Jira Ticket Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Send to Jira" action to the GUI Ticket Export dialog that posts the session summary as a comment on an existing Jira Cloud issue.

**Architecture:** A new core module `src/core/10-jira.ps1` holds all logic: config load (`%PROGRAMDATA%\NMMTools\jira.json` with a DPAPI-LocalMachine token at rest), issue-key validation, and a `Send-NmmJiraComment` function that calls Jira Cloud REST v2. The Ticket Export dialog (`09-ui-wpf.ps1`) gets a key field + Send button, and runs the network call on a background runspace (reusing `New-NmmToolRunspace` + a `DispatcherTimer` poll, exactly like `Invoke-GuiToolRun`) so the UI never freezes.

**Tech Stack:** Windows PowerShell 5.1 (runtime target) / pwsh 7 (test host), WPF, Pester 5, PSScriptAnalyzer, Jira Cloud REST API v2, DPAPI (`System.Security.Cryptography.ProtectedData`).

## Global Constraints

- **Source encoding:** every `src\*.ps1` must be ASCII-only (BOM excepted) - the `encoding.tests.ps1` gate enforces it. Use `-` not em-dash, no smart quotes, no box-drawing glyphs.
- **PS floor:** `#Requires -Version 5.1`; avoid PS7-only syntax (no ternary, no `??`). DPAPI must work on both 5.1 and pwsh 7 (verified).
- **Never throw across the boundary:** config-load and network functions return values/result-hashtables and swallow their own exceptions; configuration or network failure must never crash the dialog.
- **No new core HTTP/secret framework beyond this file:** all Jira logic lives in `10-jira.ps1`. Follow the `06-usage.ps1` persistence pattern (path function + `$script:...Override` hook + defensive IO).
- **Build:** `build.ps1` globs `src\core\*.ps1` by name, so `10-jira.ps1` is included automatically - no `build.ps1` change. The artifact must pass parse + PSScriptAnalyzer (errors).
- **Test runner (use verbatim for every test step):**
  ```
  pwsh -NoProfile -Command "Get-Module Pester | Remove-Module -Force -EA 0; Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path tests\jira.tests.ps1 -Output Detailed"
  ```
  Run from the repo root `C:\Users\Matt\projects\nmmtools`.

---

## File Structure

- **Create** `src/core/10-jira.ps1` - all Jira logic (config, validation, send). One responsibility: Jira ticket export.
- **Create** `tests/jira.tests.ps1` - Pester 5 unit tests for the above.
- **Modify** `src/core/09-ui-wpf.ps1` - the `$script:TicketExportDialogXaml` string (add a Jira row) and `Invoke-TicketExportDialog` (wire the field + button).

---

## Task 1: Module scaffold - config path + key validation

**Files:**
- Create: `src/core/10-jira.ps1`
- Test: `tests/jira.tests.ps1`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `$script:JiraConfigPathOverride` (string; tests set it to a temp path)
  - `Get-NmmJiraConfigPath()` -> string
  - `Test-NmmJiraKey -Key [string]` -> bool

- [ ] **Step 1: Write the failing test**

Create `tests/jira.tests.ps1`:

```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\10-jira.ps1')
}

Describe 'Test-NmmJiraKey' {
    It 'accepts well-formed keys' {
        Test-NmmJiraKey -Key 'DESK-12345' | Should -BeTrue
        Test-NmmJiraKey -Key 'ABC1-7'     | Should -BeTrue
    }
    It 'rejects malformed keys' {
        Test-NmmJiraKey -Key 'desk-12345' | Should -BeFalse   # lowercase
        Test-NmmJiraKey -Key 'DESK12345'  | Should -BeFalse   # no dash
        Test-NmmJiraKey -Key '12-34'      | Should -BeFalse   # no leading letter
        Test-NmmJiraKey -Key ''           | Should -BeFalse
        Test-NmmJiraKey -Key $null        | Should -BeFalse
    }
}

Describe 'Get-NmmJiraConfigPath' {
    It 'honors the override' {
        $script:JiraConfigPathOverride = 'C:\temp\fake-jira.json'
        Get-NmmJiraConfigPath | Should -Be 'C:\temp\fake-jira.json'
        $script:JiraConfigPathOverride = $null
    }
    It 'defaults under ProgramData when no override' {
        $script:JiraConfigPathOverride = $null
        Get-NmmJiraConfigPath | Should -Match 'NMMTools.jira\.json$'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the Test runner command (above).
Expected: FAIL - `Test-NmmJiraKey` / `Get-NmmJiraConfigPath` not recognized (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `src/core/10-jira.ps1`:

```powershell
# Jira Cloud ticket export. Pushes the session summary onto an existing issue as a
# comment. Config + shared service-account token live in %PROGRAMDATA%\NMMTools\jira.json;
# the token is DPAPI-encrypted (LocalMachine) at rest. All config/network failures are
# returned, never thrown - the Ticket Export dialog must never crash on them.

$script:JiraConfigPathOverride = $null   # tests set this to a temp file

function Get-NmmJiraConfigPath {
    if ($script:JiraConfigPathOverride) { return $script:JiraConfigPathOverride }
    $base = [Environment]::GetFolderPath('CommonApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:ProgramData }
    return (Join-Path $base 'NMMTools\jira.json')
}

function Test-NmmJiraKey {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return ($Key -cmatch '^[A-Z][A-Z0-9]+-\d+$')
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Test runner command.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/10-jira.ps1 tests/jira.tests.ps1
git commit -m "feat(jira): add config path resolver and issue-key validation"
```

---

## Task 2: Config load + DPAPI token at rest

**Files:**
- Modify: `src/core/10-jira.ps1`
- Test: `tests/jira.tests.ps1`

**Interfaces:**
- Consumes: `Get-NmmJiraConfigPath`, `$script:JiraConfigPathOverride`.
- Produces:
  - `Protect-NmmJiraToken -Plain [string]` -> Base64 DPAPI ciphertext (LocalMachine)
  - `Unprotect-NmmJiraToken -Cipher [string]` -> plaintext
  - `Import-NmmJiraConfig()` -> `@{ BaseUrl; Email; Token }` or `$null`. On a plaintext config (`TokenProtected` false/absent) it re-saves the file with the token encrypted and `TokenProtected=true`. Never throws.

- [ ] **Step 1: Write the failing test**

Append to `tests/jira.tests.ps1`:

```powershell
Describe 'Jira config' {
    BeforeEach {
        $script:JiraConfigPathOverride = Join-Path $env:TEMP ('nmm-jira-test-{0}.json' -f (Get-Random))
    }
    AfterEach {
        if ($script:JiraConfigPathOverride -and (Test-Path $script:JiraConfigPathOverride)) {
            Remove-Item $script:JiraConfigPathOverride -Force -ErrorAction SilentlyContinue
        }
        $script:JiraConfigPathOverride = $null
    }

    It 'returns null for a missing file' {
        Import-NmmJiraConfig | Should -BeNullOrEmpty
    }
    It 'returns null and does not throw on corrupt json' {
        Set-Content -Path $script:JiraConfigPathOverride -Value '{ not json' -Encoding UTF8
        { Import-NmmJiraConfig } | Should -Not -Throw
        Import-NmmJiraConfig | Should -BeNullOrEmpty
    }
    It 'returns null when a required field is missing' {
        '{ "BaseUrl": "https://x.atlassian.net", "Email": "a@b.c" }' |
            Set-Content -Path $script:JiraConfigPathOverride -Encoding UTF8
        Import-NmmJiraConfig | Should -BeNullOrEmpty
    }
    It 'loads a plaintext config, encrypts it at rest, and round-trips the token' {
        @{ BaseUrl='https://acme.atlassian.net/'; Email='svc@acme.com'; Token='secret-123'; TokenProtected=$false } |
            ConvertTo-Json | Set-Content -Path $script:JiraConfigPathOverride -Encoding UTF8

        $cfg = Import-NmmJiraConfig
        $cfg.BaseUrl | Should -Be 'https://acme.atlassian.net'   # trailing slash trimmed
        $cfg.Email   | Should -Be 'svc@acme.com'
        $cfg.Token   | Should -Be 'secret-123'

        # File must now be encrypted at rest.
        $raw = Get-Content $script:JiraConfigPathOverride -Raw | ConvertFrom-Json
        $raw.TokenProtected | Should -BeTrue
        $raw.Token | Should -Not -Be 'secret-123'

        # Second load decrypts back to the original token.
        (Import-NmmJiraConfig).Token | Should -Be 'secret-123'
    }
    It 'protect/unprotect round-trips' {
        $c = Protect-NmmJiraToken -Plain 'abc-xyz'
        $c | Should -Not -Be 'abc-xyz'
        Unprotect-NmmJiraToken -Cipher $c | Should -Be 'abc-xyz'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the Test runner command.
Expected: FAIL - `Import-NmmJiraConfig` / `Protect-NmmJiraToken` not recognized.

- [ ] **Step 3: Write minimal implementation**

Append to `src/core/10-jira.ps1`:

```powershell
function Protect-NmmJiraToken {
    param([Parameter(Mandatory)][string]$Plain)
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Plain)
    $enc   = [System.Security.Cryptography.ProtectedData]::Protect(
                $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Convert]::ToBase64String($enc)
}

function Unprotect-NmmJiraToken {
    param([Parameter(Mandatory)][string]$Cipher)
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $enc = [Convert]::FromBase64String($Cipher)
    $dec = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $enc, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

function Import-NmmJiraConfig {
    $path = Get-NmmJiraConfigPath
    if (-not (Test-Path $path -PathType Leaf)) { return $null }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }
    if (-not $json) { return $null }

    $baseUrl  = [string]$json.BaseUrl
    $email    = [string]$json.Email
    $rawToken = [string]$json.Token
    if ([string]::IsNullOrWhiteSpace($baseUrl) -or
        [string]::IsNullOrWhiteSpace($email)   -or
        [string]::IsNullOrWhiteSpace($rawToken)) { return $null }

    $protected = $false
    if ($null -ne $json.TokenProtected) { $protected = [bool]$json.TokenProtected }

    if ($protected) {
        try { $token = Unprotect-NmmJiraToken -Cipher $rawToken } catch { return $null }
    } else {
        $token = $rawToken
        # First run after deployment: re-save with the token encrypted. Non-fatal on failure.
        try {
            $cipher = Protect-NmmJiraToken -Plain $token
            $out = [ordered]@{ BaseUrl = $baseUrl; Email = $email; Token = $cipher; TokenProtected = $true }
            $dir = Split-Path $path -Parent
            if ($dir -and -not (Test-Path $dir -PathType Container)) {
                New-Item -ItemType Directory -Force $dir | Out-Null
            }
            ($out | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }
    return @{ BaseUrl = $baseUrl.TrimEnd('/'); Email = $email; Token = $token }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Test runner command.
Expected: PASS (all Task 1 + Task 2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/core/10-jira.ps1 tests/jira.tests.ps1
git commit -m "feat(jira): load config with DPAPI-encrypted token at rest"
```

---

## Task 3: Send-NmmJiraComment (HTTP)

**Files:**
- Modify: `src/core/10-jira.ps1`
- Test: `tests/jira.tests.ps1`

**Interfaces:**
- Consumes: `Test-NmmJiraKey`, `Import-NmmJiraConfig`.
- Produces:
  - `ConvertTo-NmmJiraError -ErrorRecord <err> -Key [string]` -> `@{ Success=$false; Message }`
  - `Send-NmmJiraComment -Key [string] -Body [string]` -> `@{ Success=[bool]; Message=[string] }`. Validates the key, loads config, GETs the issue to verify, POSTs a `{code}`-wrapped comment. Never throws.

- [ ] **Step 1: Write the failing test**

Append to `tests/jira.tests.ps1`:

```powershell
Describe 'Send-NmmJiraComment' {
    BeforeEach {
        $script:JiraConfigPathOverride = Join-Path $env:TEMP ('nmm-jira-send-{0}.json' -f (Get-Random))
        @{ BaseUrl='https://acme.atlassian.net'; Email='svc@acme.com'; Token='t'; TokenProtected=$false } |
            ConvertTo-Json | Set-Content -Path $script:JiraConfigPathOverride -Encoding UTF8
    }
    AfterEach {
        if (Test-Path $script:JiraConfigPathOverride) { Remove-Item $script:JiraConfigPathOverride -Force -EA SilentlyContinue }
        $script:JiraConfigPathOverride = $null
    }

    It 'rejects an invalid key before any network call' {
        $r = Send-NmmJiraComment -Key 'bad' -Body 'x'
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'valid issue key'
    }
    It 'returns not-configured when config is absent' {
        Remove-Item $script:JiraConfigPathOverride -Force
        $r = Send-NmmJiraComment -Key 'DESK-1' -Body 'x'
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'not configured'
    }
    It 'reports success when verify and post both succeed' {
        Mock Invoke-RestMethod -MockWith { return @{ ok = $true } }
        $r = Send-NmmJiraComment -Key 'DESK-12345' -Body 'session summary'
        $r.Success | Should -BeTrue
        $r.Message | Should -Match 'DESK-12345'
        Should -Invoke Invoke-RestMethod -Exactly -Times 2   # verify GET + comment POST
    }
    It 'returns a friendly failure when the request throws' {
        Mock -CommandName Invoke-RestMethod -MockWith { throw 'boom' }
        $r = Send-NmmJiraComment -Key 'DESK-12345' -Body 'x'
        $r.Success | Should -BeFalse
        [string]::IsNullOrWhiteSpace($r.Message) | Should -BeFalse
    }
}
```

> Note: `Mock Invoke-RestMethod` intercepts the real HTTP. The happy-path mock returns for both the GET and POST. Exact 401/404 status-text mapping is best-effort in `ConvertTo-NmmJiraError` and is verified manually against live Jira in Task 4; the unit test only asserts that a thrown request yields a non-empty failure message.

- [ ] **Step 2: Run test to verify it fails**

Run the Test runner command.
Expected: FAIL - `Send-NmmJiraComment` not recognized.

- [ ] **Step 3: Write minimal implementation**

Append to `src/core/10-jira.ps1`:

```powershell
function ConvertTo-NmmJiraError {
    param($ErrorRecord, [string]$Key)
    $status = $null
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and ($resp.PSObject.Properties.Name -contains 'StatusCode')) {
            $status = [int]$resp.StatusCode
        }
    } catch { $status = $null }

    if ($null -eq $status) {
        return @{ Success = $false; Message = ('Could not reach Jira ({0}).' -f $ErrorRecord.Exception.Message) }
    }
    switch ($status) {
        401     { return @{ Success = $false; Message = 'Authentication failed - check the Jira service account token.' } }
        403     { return @{ Success = $false; Message = 'Authentication failed - check the Jira service account token.' } }
        404     { return @{ Success = $false; Message = ('Issue {0} not found or not accessible.' -f $Key) } }
        default { return @{ Success = $false; Message = ('Jira returned an error ({0}).' -f $status) } }
    }
}

function Send-NmmJiraComment {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Body
    )
    if (-not (Test-NmmJiraKey -Key $Key)) {
        return @{ Success = $false; Message = 'Enter a valid issue key, e.g. DESK-12345.' }
    }
    $cfg = Import-NmmJiraConfig
    if ($null -eq $cfg) {
        return @{ Success = $false; Message = 'Jira is not configured on this machine.' }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pair    = '{0}:{1}' -f $cfg.Email, $cfg.Token
    $b64     = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    $headers = @{ Authorization = ('Basic {0}' -f $b64) }

    $verifyUrl = '{0}/rest/api/2/issue/{1}?fields=key' -f $cfg.BaseUrl, $Key
    try {
        Invoke-RestMethod -Method Get -Uri $verifyUrl -Headers $headers -TimeoutSec 30 -ErrorAction Stop | Out-Null
    } catch {
        return (ConvertTo-NmmJiraError -ErrorRecord $_ -Key $Key)
    }

    $commentUrl = '{0}/rest/api/2/issue/{1}/comment' -f $cfg.BaseUrl, $Key
    $wrapped    = "{{code}}`n{0}`n{{code}}" -f $Body
    $payload    = @{ body = $wrapped } | ConvertTo-Json
    try {
        Invoke-RestMethod -Method Post -Uri $commentUrl -Headers $headers `
            -ContentType 'application/json' -Body $payload -TimeoutSec 30 -ErrorAction Stop | Out-Null
    } catch {
        return (ConvertTo-NmmJiraError -ErrorRecord $_ -Key $Key)
    }
    return @{ Success = $true; Message = ('Added comment to {0}.' -f $Key) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Test runner command.
Expected: PASS (all jira.tests.ps1).

- [ ] **Step 5: Verify the whole suite + build still pass**

Run:
```
pwsh -NoProfile -Command "Get-Module Pester | Remove-Module -Force -EA 0; Import-Module Pester -RequiredVersion 5.7.1 -Force; Invoke-Pester -Path tests -Output Detailed" ; .\build.ps1
```
Expected: only the known-flaky `Usage store > breaks ties by most recent use` may fail; everything else passes. `build.ps1` prints `Built ... NMMTools.ps1`.

- [ ] **Step 6: Commit**

```bash
git add src/core/10-jira.ps1 tests/jira.tests.ps1
git commit -m "feat(jira): post session summary as a comment via Jira Cloud REST"
```

---

## Task 4: Wire into the Ticket Export dialog

**Files:**
- Modify: `src/core/09-ui-wpf.ps1` - `$script:TicketExportDialogXaml` and `Invoke-TicketExportDialog`

**Interfaces:**
- Consumes: `Import-NmmJiraConfig`, `Test-NmmJiraKey`, `Send-NmmJiraComment`, `New-NmmToolRunspace`, `ConvertTo-WpfBrush`.
- Produces: GUI behavior only (no new callable surface).

- [ ] **Step 1: Add the Jira row to the dialog XAML**

In `src/core/09-ui-wpf.ps1`, in `$script:TicketExportDialogXaml`, change the `Grid.RowDefinitions` from three rows to four, insert the Jira row at `Grid.Row="2"`, and move the status label to `Grid.Row="3"`.

Replace:
```xml
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
```
with:
```xml
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
```

Then, immediately before the `<TextBlock ... x:Name="SaveStatusLabel" ...>` line, insert:
```xml
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,4,0,4">
      <TextBlock Text="Jira issue:" Foreground="#858585" FontSize="11"
                 VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox x:Name="JiraKeyBox" Width="140" Background="#0C0C0C" Foreground="#CCCCCC"
               BorderBrush="#3E3E42" BorderThickness="1" Padding="6,3,6,3"
               VerticalContentAlignment="Center" Margin="0,0,8,0"/>
      <Button x:Name="SendJiraButton" Content="Send to Jira"
              Background="#5C8DDF" Foreground="#FFFFFF" BorderThickness="0"
              Padding="14,6,14,6" Cursor="Hand"/>
    </StackPanel>
```

And change the status label's row:
```xml
    <TextBlock Grid.Row="2" x:Name="SaveStatusLabel" Foreground="#858585"
```
to:
```xml
    <TextBlock Grid.Row="3" x:Name="SaveStatusLabel" Foreground="#858585"
```

- [ ] **Step 2: Wire the handlers in `Invoke-TicketExportDialog`**

In `Invoke-TicketExportDialog`, after the existing `$closeBtn.Add_Click(...)` / `Add_KeyDown` block and BEFORE `$dlg.ShowDialog() | Out-Null`, insert:

```powershell
    # ---- Jira export ----
    $jiraKeyBox = $dlg.FindName('JiraKeyBox')
    $sendJira   = $dlg.FindName('SendJiraButton')
    $jiraCfg    = Import-NmmJiraConfig

    if ($null -eq $jiraCfg) {
        $jiraKeyBox.IsEnabled = $false
        $sendJira.IsEnabled   = $false
        $statusLbl.Text       = 'Jira not configured on this machine.'
    } else {
        $sendJira.IsEnabled = $false   # enabled only once a valid key is typed

        $jiraKeyBox.Add_TextChanged({
            $upper = $jiraKeyBox.Text.ToUpper()
            if ($jiraKeyBox.Text -cne $upper) {
                $jiraKeyBox.Text = $upper
                $jiraKeyBox.CaretIndex = $upper.Length
            }
            $sendJira.IsEnabled = (Test-NmmJiraKey -Key $jiraKeyBox.Text)
        }.GetNewClosure())

        $sendJira.Add_Click({
            $key  = $jiraKeyBox.Text
            $body = $ticketBox.Text
            $sendJira.IsEnabled   = $false
            $sendJira.Content     = 'Sending...'
            $statusLbl.Foreground = ConvertTo-WpfBrush '#858585'
            $statusLbl.Text       = ('Sending to {0}...' -f $key)

            $rs = New-NmmToolRunspace
            $ps = [System.Management.Automation.PowerShell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddScript({ param($k, $b) Send-NmmJiraComment -Key $k -Body $b })
            [void]$ps.AddParameter('k', $key)
            [void]$ps.AddParameter('b', $body)
            $handle = $ps.BeginInvoke()

            $capturedPs     = $ps
            $capturedHandle = $handle
            $capturedRs     = $rs
            $capturedSend   = $sendJira
            $capturedStatus = $statusLbl
            $capturedKeyBox = $jiraKeyBox

            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [System.TimeSpan]::FromMilliseconds(150)
            $timer.Add_Tick({
                if ($capturedPs.InvocationStateInfo.State -ne [System.Management.Automation.PSInvocationState]::Running) {
                    $timer.Stop()
                    $result = $null
                    try { $result = $capturedPs.EndInvoke($capturedHandle) | Select-Object -Last 1 } catch { }
                    $capturedPs.Dispose()
                    $capturedRs.Close(); $capturedRs.Dispose()

                    $capturedSend.Content = 'Send to Jira'
                    if ($result -and $result.Success) {
                        $capturedStatus.Foreground = ConvertTo-WpfBrush '#4EC94E'
                        $capturedStatus.Text       = [string]$result.Message
                    } else {
                        $capturedStatus.Foreground = ConvertTo-WpfBrush '#F44747'
                        $capturedStatus.Text = if ($result) { [string]$result.Message } else { 'Send failed (no response).' }
                    }
                    $capturedSend.IsEnabled = (Test-NmmJiraKey -Key $capturedKeyBox.Text)
                }
            }.GetNewClosure())
            $timer.Start()
        }.GetNewClosure())
    }
```

- [ ] **Step 3: Build and verify it compiles**

Run from the repo root:
```
.\build.ps1
```
Expected: `Built ... NMMTools.ps1` (parse + analyzer pass). If parse fails, fix the XAML/handler edit before continuing.

- [ ] **Step 4: Manual smoke test (no config)**

Launch the GUI elevated:
```
Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\Matt\projects\nmmtools\dist\NMMTools.ps1" -Mode GUI'
```
Run any tool, click **Export Ticket**. Expected: the Jira row is visible; key box + Send button are **disabled**; status reads "Jira not configured on this machine." Copy/Save/Close still work.

- [ ] **Step 5: Manual smoke test (with config + real issue)**

Create `%PROGRAMDATA%\NMMTools\jira.json` with the real service-account `BaseUrl`/`Email`/`Token` and `"TokenProtected": false`. Re-open the dialog. Expected:
- Send button stays disabled until a valid key (e.g. `DESK-12345`) is typed; lowercase auto-uppercases.
- Clicking Send shows "Sending...", the dialog stays responsive, then a green "Added comment to DESK-12345." appears and the comment shows on the issue in Jira.
- Verify `jira.json` is now `"TokenProtected": true` with an opaque token (encrypted at rest).
- Test a bad key (e.g. `DESK-999999` that doesn't exist) -> red "Issue ... not found or not accessible."

- [ ] **Step 6: Commit**

```bash
git add src/core/09-ui-wpf.ps1
git commit -m "feat(jira): add Send to Jira to the Ticket Export dialog"
```

---

## Self-Review Notes

- **Spec coverage:** config file + DPAPI (Task 2), key validation (Task 1), v2 verify+comment + error mapping (Task 3), dialog UI + non-blocking send (Task 4), tests (Tasks 1-3). Non-goals untouched. All §s covered.
- **Type consistency:** `Send-NmmJiraComment` / `Import-NmmJiraConfig` / `Test-NmmJiraKey` / `ConvertTo-NmmJiraError` names and `@{ Success; Message }` / `@{ BaseUrl; Email; Token }` shapes are used identically across tasks.
- **Non-blocking:** Task 4 reuses the proven `New-NmmToolRunspace` + `DispatcherTimer` poll from `Invoke-GuiToolRun`; the config load (fast, local) stays on the UI thread, only the HTTP runs in the runspace.
