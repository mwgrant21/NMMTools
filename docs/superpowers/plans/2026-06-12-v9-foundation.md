# NMM Toolkit v9 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v9 core architecture — tool registry, output sinks, run tracking, registry-driven dispatch with CLI mode, console menu, and single-file build system — proven end-to-end with two pilot tools.

**Architecture:** Modular source under `src/` compiles via `build.ps1` into one self-contained `dist/NMMTools.ps1`. A data-only registry (`tools.psd1`) drives the menu, search, CLI dispatch, and ticket export. Tools follow one template: `New-ToolRun` → work via `Write-ToolOutput`/`Read-ToolChoice` → `Complete-ToolRun`.

**Tech Stack:** Windows PowerShell 5.1 (target baseline), Pester 5 (tests), PSScriptAnalyzer (build gate), git.

**Repo:** `C:\Users\IT\Desktop\NMMToolkit` (exists; contains `docs/` with spec, committed).

**Reference:** v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` — read-only reference, never modified.

**Scope:** Foundation + 2 pilot tools only. Porting the remaining ~104 tools (7 category batches), the GUI launcher, and cutover are separate follow-up plans.

**PowerShell 5.1 gotchas for all tasks:** no `&&`/`||`, no ternary, no `??`. `$input` and `$matches` are automatic variables — never assign to them. `Set-Content -Encoding UTF8` writes UTF-8 with BOM (correct for PS scripts).

---

### Task 0: Tooling prerequisites

**Files:** none (machine setup)

- [ ] **Step 1: Install Pester 5 and PSScriptAnalyzer for the current user**

Run in PowerShell:
```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

- [ ] **Step 2: Verify versions**

Run: `Get-Module Pester, PSScriptAnalyzer -ListAvailable | Select-Object Name, Version`
Expected: Pester ≥ 5.5.0 and PSScriptAnalyzer listed. (Pester 3.4.0 will also be listed — that's the Windows built-in; `Import-Module Pester -MinimumVersion 5.0` in test runs avoids it.)

---

### Task 1: Repo scaffold

**Files:**
- Create: `C:\Users\IT\Desktop\NMMToolkit\.gitignore`
- Create: `C:\Users\IT\Desktop\NMMToolkit\README.md`
- Create folders: `src\core`, `src\entry`, `src\registry`, `src\tools\diagnostics`, `tests`, `dist`

- [ ] **Step 1: Create folder structure**

```powershell
$root = 'C:\Users\IT\Desktop\NMMToolkit'
'src\core','src\entry','src\registry','src\tools\diagnostics','tests','dist' |
    ForEach-Object { New-Item -ItemType Directory -Force (Join-Path $root $_) | Out-Null }
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
dist/
*.log
```

- [ ] **Step 3: Create `README.md`**

```markdown
# NMM Toolkit v9

Modular source for the NMM System Toolkit. Develop here; ship `dist\NMMTools.ps1`.

## Build

    .\build.ps1              # full build: concatenate + parse gate + analyzer gate
    .\build.ps1 -SkipAnalyzer

## Test

    Import-Module Pester -MinimumVersion 5.0
    Invoke-Pester .\tests

## Layout

- `src\entry\` — artifact param block (first) and main entry (last)
- `src\core\` — output sinks, run tracking, dispatch, console UI (numeric prefix = build order)
- `src\registry\tools.psd1` — THE tool registry (pure data, one entry per tool)
- `src\tools\<category>\` — one file per tool, named after its function
- `tests\` — Pester: registry consistency + artifact smoke tests
- `docs\superpowers\specs\` — approved design spec

## Adding a tool

1. Create `src\tools\<category>\<Verb-Noun>.ps1` following the template (see spec §3).
2. Add a registry entry in `src\registry\tools.psd1`.
3. `.\build.ps1` — registry tests fail if the two don't match.

v8 monolith (`C:\Users\IT\Desktop\NMMTools.ps1`) is the feature-frozen reference.
```

- [ ] **Step 4: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "chore: scaffold v9 repo layout"
```

---

### Task 2: Tool registry + consistency tests

**Files:**
- Create: `src\registry\tools.psd1`
- Test: `tests\registry.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests\registry.tests.ps1`:
```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:Registry = Import-PowerShellDataFile (Join-Path $repoRoot 'src\registry\tools.psd1')
    $script:Tools = @($script:Registry.Tools)
}

Describe 'Tool registry structure' {
    It 'has at least one tool' {
        $script:Tools.Count | Should -BeGreaterThan 0
    }

    It 'every entry has all required keys' {
        $required = 'Id','LegacyId','Name','Category','Function','Description',
                    'RequiresAdmin','SilentCapable','Risk','Tags'
        foreach ($t in $script:Tools) {
            foreach ($k in $required) {
                $t.ContainsKey($k) | Should -BeTrue -Because "entry '$($t.Id)' must define $k"
            }
        }
    }

    It 'has unique Ids' {
        $dupes = $script:Tools | Group-Object { $_.Id } | Where-Object Count -gt 1
        $dupes | Should -BeNullOrEmpty
    }

    It 'has unique LegacyIds' {
        $dupes = $script:Tools | Group-Object { $_.LegacyId } | Where-Object Count -gt 1
        $dupes | Should -BeNullOrEmpty
    }

    It 'uses only valid Risk values' {
        foreach ($t in $script:Tools) {
            $t.Risk | Should -BeIn @('ReadOnly','Modifies','Disruptive')
        }
    }

    It 'uses kebab-case slugs for Id' {
        foreach ($t in $script:Tools) {
            $t.Id | Should -Match '^[a-z0-9]+(-[a-z0-9]+)*$'
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```powershell
Import-Module Pester -MinimumVersion 5.0
Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\registry.tests.ps1 -Output Detailed
```
Expected: FAIL — `Import-PowerShellDataFile` cannot find `tools.psd1`.

- [ ] **Step 3: Create the registry with the two pilot entries**

`src\registry\tools.psd1`:
```powershell
@{
    Tools = @(
        @{
            Id            = 'system-uptime'
            LegacyId      = '20'
            Name          = 'System Uptime and Boot Info'
            Category      = 'Diagnostics'
            Function      = 'Get-SystemUptime'
            Description   = 'Shows last boot time and uptime duration; flags stale uptime'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('uptime','boot','restart','reboot')
        }
        @{
            Id            = 'temp-cleanup'
            LegacyId      = '11'
            Name          = 'Temp Files Cleanup'
            Category      = 'Diagnostics'
            Function      = 'Start-TempFilesCleanup'
            Description   = 'Clears user and system temp folders and reports space reclaimed'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('temp','cleanup','disk','space')
        }
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\registry.tests.ps1 -Output Detailed`
Expected: 6 PASS, 0 FAIL.

- [ ] **Step 5: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: tool registry with pilot entries and consistency tests"
```

---

### Task 3: Output layer (sinks + silent-safe prompting)

**Files:**
- Create: `src\core\02-output.ps1`
- Test: `tests\output.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests\output.tests.ps1`:
```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
}

Describe 'Write-ToolOutput' {
    It 'appends to the log file when a log path is set' {
        $dir = Join-Path $env:TEMP "nmm-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $dir | Out-Null
        Set-OutputSink -Sink Console -LogDirectory $dir
        Write-ToolOutput 'hello from test' -Level Info
        $logFile = Get-ChildItem $dir -Filter *.log | Select-Object -First 1
        $logFile | Should -Not -BeNullOrEmpty
        Get-Content $logFile.FullName -Raw | Should -Match 'hello from test'
        Remove-Item $dir -Recurse -Force
        Set-OutputSink -Sink Console   # reset: no log directory
    }
}

Describe 'Read-ToolChoice' {
    It 'returns the default without prompting in silent mode' {
        Read-ToolChoice -Prompt 'Continue?' -Default 'No' -Silent | Should -Be 'No'
    }

    It 'returns the default when the user just presses Enter' {
        Mock Read-Host { '' }
        Read-ToolChoice -Prompt 'Continue?' -Default 'Yes' | Should -Be 'Yes'
    }

    It 'matches a partial answer to a choice' {
        Mock Read-Host { 'y' }
        Read-ToolChoice -Prompt 'Continue?' -Choices @('Yes','No') -Default 'No' | Should -Be 'Yes'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\output.tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, `02-output.ps1` does not exist.

- [ ] **Step 3: Implement the output layer**

`src\core\02-output.ps1`:
```powershell
# Output layer. Tools never call Write-Host/Read-Host directly; they use
# Write-ToolOutput and Read-ToolChoice so console, log, and silent modes
# are one code path. (Replaces the v8 GUI's Write-Host-override hack.)

$script:OutputSink = 'Console'
$script:LogFilePath = $null

function Set-OutputSink {
    param(
        [Parameter(Mandatory)][ValidateSet('Console','Silent')][string]$Sink,
        [string]$LogDirectory
    )
    $script:OutputSink = $Sink
    if ($LogDirectory) {
        if (-not (Test-Path $LogDirectory)) {
            New-Item -ItemType Directory -Force $LogDirectory | Out-Null
        }
        $name = 'NMMTools-{0}-{1:yyyyMMdd-HHmmss}.log' -f $env:COMPUTERNAME, (Get-Date)
        $script:LogFilePath = Join-Path $LogDirectory $name
    } else {
        $script:LogFilePath = $null
    }
}

function Write-ToolOutput {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info','Success','Warning','Error','Detail')][string]$Level = 'Info'
    )
    if ($script:LogFilePath) {
        $line = '[{0:HH:mm:ss}] [{1,-7}] {2}' -f (Get-Date), $Level, $Message
        Add-Content -Path $script:LogFilePath -Value $line
    }
    if ($script:OutputSink -eq 'Console') {
        $color = switch ($Level) {
            'Success' { 'Green' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            'Detail'  { 'Gray' }
            default   { 'White' }
        }
        Write-Host $Message -ForegroundColor $color
    }
}

function Read-ToolChoice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string[]]$Choices = @('Yes','No'),
        [Parameter(Mandatory)][string]$Default,
        [switch]$Silent
    )
    if ($Silent -or $script:OutputSink -eq 'Silent') {
        Write-ToolOutput "$Prompt -> $Default (auto-selected, silent mode)" -Level Detail
        return $Default
    }
    $choiceText = $Choices -join '/'
    while ($true) {
        $answer = Read-Host "$Prompt [$choiceText] (default: $Default)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $hit = $Choices | Where-Object { $_ -like "$answer*" } | Select-Object -First 1
        if ($hit) { return $hit }
        Write-ToolOutput "Invalid choice. Enter one of: $choiceText" -Level Warning
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\output.tests.ps1 -Output Detailed`
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: output layer with sinks and silent-safe Read-ToolChoice"
```

---

### Task 4: Run tracking + ticket summary

**Files:**
- Create: `src\core\03-results.ps1`
- Test: `tests\results.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests\results.tests.ps1`:
```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    Set-OutputSink -Sink Silent
    # Minimal registry stand-in so New-ToolRun can resolve names
    $script:RegistryData = @{
        Tools = @(
            @{ Id = 'fake-tool'; Name = 'Fake Tool'; LegacyId = '0'; Category = 'Test'
               Function = 'Invoke-Fake'; Description = 'x'; RequiresAdmin = $false
               SilentCapable = $true; Risk = 'ReadOnly'; Tags = @('fake') }
        )
    }
}

Describe 'Tool run tracking' {
    It 'records a completed run with status and duration' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'all good'
        $run.Status | Should -Be 'Success'
        $run.Summary | Should -Be 'all good'
        $run.Duration | Should -Not -BeNullOrEmpty
        $script:ToolRuns | Should -Contain $run
    }

    It 'resolves the display name from the registry' {
        $run = New-ToolRun -Id 'fake-tool'
        $run.Name | Should -Be 'Fake Tool'
        Complete-ToolRun $run -Status Skipped -Summary ''
    }
}

Describe 'Export-TicketSummary' {
    It 'renders machine, user, and each run line' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Failed -Summary 'simulated failure'
        $text = Export-TicketSummary
        $text | Should -Match [regex]::Escape($env:COMPUTERNAME)
        $text | Should -Match [regex]::Escape($env:USERNAME)
        $text | Should -Match 'FAILED.*Fake Tool'
        $text | Should -Match 'simulated failure'
    }

    It 'writes the summary to a file when -Path is given' {
        $file = Join-Path $env:TEMP "nmm-ticket-$(Get-Random).txt"
        Export-TicketSummary -Path $file | Out-Null
        Test-Path $file | Should -BeTrue
        Remove-Item $file -Force
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\results.tests.ps1 -Output Detailed`
Expected: FAIL — `03-results.ps1` does not exist.

- [ ] **Step 3: Implement run tracking**

`src\core\03-results.ps1`:
```powershell
# Session run tracking. Every tool run starts with New-ToolRun and ends with
# Complete-ToolRun (success OR failure), so the transcript is always complete.

$script:ToolRuns = New-Object System.Collections.ArrayList
$script:SessionStart = Get-Date

function New-ToolRun {
    param([Parameter(Mandatory)][string]$Id)
    $tool = @($script:RegistryData.Tools) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    $name = $Id
    if ($tool) { $name = $tool.Name }
    $run = [PSCustomObject]@{
        Id       = $Id
        Name     = $name
        Started  = Get-Date
        Duration = $null
        Status   = 'Running'
        Summary  = ''
    }
    [void]$script:ToolRuns.Add($run)
    Write-ToolOutput ''
    Write-ToolOutput ('=== {0} ===' -f $name)
    return $run
}

function Complete-ToolRun {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][ValidateSet('Success','Failed','Warning','Skipped')][string]$Status,
        [string]$Summary = ''
    )
    $Run.Status = $Status
    $Run.Summary = $Summary
    $Run.Duration = (Get-Date) - $Run.Started
    $level = switch ($Status) {
        'Success' { 'Success' }
        'Failed'  { 'Error' }
        'Warning' { 'Warning' }
        default   { 'Detail' }
    }
    Write-ToolOutput ('[{0}] {1}' -f $Status.ToUpper(), $Summary) -Level $level
}

function Export-TicketSummary {
    param([string]$Path)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('NMM Toolkit Session Summary')
    [void]$sb.AppendLine(('Computer: {0}    User: {1}' -f $env:COMPUTERNAME, $env:USERNAME))
    [void]$sb.AppendLine(('Session:  {0:g} - {1:g}' -f $script:SessionStart, (Get-Date)))
    [void]$sb.AppendLine('')
    if ($script:ToolRuns.Count -eq 0) {
        [void]$sb.AppendLine('No tools were run this session.')
    }
    foreach ($run in $script:ToolRuns) {
        $dur = '--:--'
        if ($run.Duration) { $dur = '{0:mm\:ss}' -f $run.Duration }
        [void]$sb.AppendLine(('[{0}] {1} ({2})' -f $run.Status.ToUpper(), $run.Name, $dur))
        if ($run.Summary) { [void]$sb.AppendLine('    ' + $run.Summary) }
    }
    $text = $sb.ToString()
    if ($Path) { Set-Content -Path $Path -Value $text -Encoding UTF8 }
    return $text
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\results.tests.ps1 -Output Detailed`
Expected: 4 PASS.

- [ ] **Step 5: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: tool run tracking and ticket summary export"
```

---

### Task 5: Registry dispatch + CLI guards

**Files:**
- Create: `src\core\04-dispatch.ps1`
- Test: `tests\dispatch.tests.ps1`

- [ ] **Step 1: Write the failing tests**

`tests\dispatch.tests.ps1`:
```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    Set-OutputSink -Sink Silent
    $script:IsAdmin = $true
    $script:RegistryData = @{
        Tools = @(
            @{ Id = 'safe-tool'; LegacyId = '20'; Name = 'Safe Tool'; Category = 'Test'
               Function = 'Invoke-SafeTool'; Description = 'reads things'
               RequiresAdmin = $false; SilentCapable = $true; Risk = 'ReadOnly'
               Tags = @('safe','reading') }
            @{ Id = 'loud-tool'; LegacyId = '99'; Name = 'Loud Tool'; Category = 'Test'
               Function = 'Invoke-LoudTool'; Description = 'needs a human'
               RequiresAdmin = $false; SilentCapable = $false; Risk = 'Disruptive'
               Tags = @('loud') }
        )
    }
    function Invoke-SafeTool {
        param([switch]$Silent)
        $run = New-ToolRun -Id 'safe-tool'
        Complete-ToolRun $run -Status Success -Summary 'ran fine'
    }
    function Invoke-LoudTool { param([switch]$Silent) }
}

Describe 'Resolve-NmmTool' {
    It 'resolves by slug' {
        (Resolve-NmmTool -Query 'safe-tool').Name | Should -Be 'Safe Tool'
    }
    It 'resolves by legacy menu number' {
        (Resolve-NmmTool -Query '20').Name | Should -Be 'Safe Tool'
    }
    It 'returns nothing for an unknown query' {
        Resolve-NmmTool -Query 'no-such-tool' | Should -BeNullOrEmpty
    }
}

Describe 'Search-NmmTools' {
    It 'matches by tag' {
        @(Search-NmmTools -Term 'reading').Id | Should -Contain 'safe-tool'
    }
    It 'matches by partial name' {
        @(Search-NmmTools -Term 'loud').Id | Should -Contain 'loud-tool'
    }
}

Describe 'Invoke-NmmTool guards' {
    It 'runs a silent-capable tool and reports its run status' {
        $tool = Resolve-NmmTool -Query 'safe-tool'
        Invoke-NmmTool -Tool $tool -Silent | Should -Be 'Success'
    }
    It 'refuses -Silent for a non-silent-capable tool' {
        $tool = Resolve-NmmTool -Query 'loud-tool'
        Invoke-NmmTool -Tool $tool -Silent | Should -Be 'Refused'
    }
    It 'refuses a tool that requires admin when not elevated' {
        $script:IsAdmin = $false
        $tools = @($script:RegistryData.Tools)
        $needsAdmin = $tools[0].Clone()
        $needsAdmin.RequiresAdmin = $true
        Invoke-NmmTool -Tool $needsAdmin | Should -Be 'Refused'
        $script:IsAdmin = $true
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\dispatch.tests.ps1 -Output Detailed`
Expected: FAIL — `04-dispatch.ps1` does not exist.

- [ ] **Step 3: Implement dispatch**

`src\core\04-dispatch.ps1`:
```powershell
# Registry-driven dispatch. The menu, search, and CLI all resolve tools here.

function Get-NmmTools {
    @($script:RegistryData.Tools)
}

function Resolve-NmmTool {
    param([Parameter(Mandatory)][string]$Query)
    $tools = Get-NmmTools
    $hit = $tools | Where-Object { $_.Id -eq $Query } | Select-Object -First 1
    if (-not $hit) {
        $hit = $tools | Where-Object { $_.LegacyId -eq $Query } | Select-Object -First 1
    }
    return $hit
}

function Search-NmmTools {
    param([Parameter(Mandatory)][string]$Term)
    Get-NmmTools | Where-Object {
        $_.Name -like "*$Term*" -or
        $_.Description -like "*$Term*" -or
        $_.Tags -contains $Term.ToLower()
    }
}

function Invoke-NmmTool {
    param(
        [Parameter(Mandatory)][hashtable]$Tool,
        [switch]$Silent,
        [switch]$Force
    )
    if ($Silent -and -not $Tool.SilentCapable) {
        Write-ToolOutput ("'{0}' requires interaction and cannot run silently." -f $Tool.Name) -Level Error
        return 'Refused'
    }
    if ($Silent -and $Tool.Risk -eq 'Disruptive' -and -not $Force) {
        Write-ToolOutput ("'{0}' is disruptive; add -Force to run it silently." -f $Tool.Name) -Level Error
        return 'Refused'
    }
    if ($Tool.RequiresAdmin -and -not $script:IsAdmin) {
        Write-ToolOutput ("'{0}' requires administrator rights. Re-launch elevated." -f $Tool.Name) -Level Error
        return 'Refused'
    }
    & $Tool.Function -Silent:$Silent
    $run = $script:ToolRuns | Where-Object { $_.Id -eq $Tool.Id } | Select-Object -Last 1
    if ($run) { return $run.Status }
    return 'Unknown'
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\dispatch.tests.ps1 -Output Detailed`
Expected: 8 PASS.

- [ ] **Step 5: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: registry dispatch with silent/admin/disruptive guards"
```

---

### Task 6: Pilot tools + registry↔function mapping tests

**Files:**
- Create: `src\tools\diagnostics\Get-SystemUptime.ps1`
- Create: `src\tools\diagnostics\Start-TempFilesCleanup.ps1`
- Modify: `tests\registry.tests.ps1` (append a Describe block)

The v8 originals are at `C:\Users\IT\Desktop\NMMTools.ps1` lines 1124 (`Get-SystemUptime`) and 881 (`Start-TempFilesCleanup`) — read them for behavioral reference; the implementations below are template-shaped rewrites of the same behavior.

- [ ] **Step 1: Append the failing mapping tests to `tests\registry.tests.ps1`**

Append this Describe block at the end of the file:
```powershell
Describe 'Registry-to-function mapping' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $toolFiles = Get-ChildItem (Join-Path $repoRoot 'src\tools') -Recurse -Filter *.ps1
        $script:DefinedFunctions = foreach ($f in $toolFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                ForEach-Object { $_.Name }
        }
    }

    It 'every registry Function exists in a tools file' {
        foreach ($t in $script:Tools) {
            $script:DefinedFunctions | Should -Contain $t.Function `
                -Because "registry entry '$($t.Id)' points at $($t.Function)"
        }
    }

    It 'every tool-file function has a registry entry' {
        foreach ($fn in $script:DefinedFunctions) {
            @($script:Tools | Where-Object { $_.Function -eq $fn }).Count |
                Should -Be 1 -Because "$fn must be registered exactly once"
        }
    }
}
```

- [ ] **Step 2: Run tests to verify the new block fails**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\registry.tests.ps1 -Output Detailed`
Expected: structure tests PASS; both mapping tests FAIL (no tool files exist yet).

- [ ] **Step 3: Implement `Get-SystemUptime`**

`src\tools\diagnostics\Get-SystemUptime.ps1`:
```powershell
function Get-SystemUptime {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = New-ToolRun -Id 'system-uptime'
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime
        Write-ToolOutput ('Last boot: {0:g}' -f $os.LastBootUpTime)
        Write-ToolOutput ('Uptime:    {0} days, {1} hours, {2} minutes' -f
            $uptime.Days, $uptime.Hours, $uptime.Minutes)
        if ($uptime.Days -ge 14) {
            Write-ToolOutput 'Uptime exceeds 14 days - a reboot is recommended.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary ('Up {0} days - reboot recommended' -f $uptime.Days)
        } else {
            Complete-ToolRun $run -Status Success -Summary ('Up {0}d {1}h since {2:g}' -f
                $uptime.Days, $uptime.Hours, $os.LastBootUpTime)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 4: Implement `Start-TempFilesCleanup`**

`src\tools\diagnostics\Start-TempFilesCleanup.ps1`:
```powershell
function Start-TempFilesCleanup {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = New-ToolRun -Id 'temp-cleanup'
    try {
        $targets = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) |
            Sort-Object -Unique | Where-Object { Test-Path $_ }

        $measure = {
            param($paths)
            $total = [int64]0
            foreach ($p in $paths) {
                $sum = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum
                if ($sum) { $total += $sum }
            }
            $total
        }

        $before = & $measure $targets
        Write-ToolOutput ('Temp folders hold {0:N1} MB across {1} locations' -f
            ($before / 1MB), $targets.Count)

        $choice = Read-ToolChoice -Prompt 'Delete temp files now?' -Default 'Yes' -Silent:$Silent
        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined cleanup'
            return
        }

        $locked = 0
        foreach ($t in $targets) {
            $items = Get-ChildItem $t -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    Remove-Item $item.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop
                } catch {
                    $locked++   # in-use files are expected; count and move on
                }
            }
        }

        $after = & $measure $targets
        $freedMB = [math]::Max(0, ($before - $after) / 1MB)
        Complete-ToolRun $run -Status Success -Summary ('Freed {0:N1} MB ({1} items in use, skipped)' -f
            $freedMB, $locked)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

- [ ] **Step 5: Run all tests to verify everything passes**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests -Output Detailed`
Expected: all tests PASS (registry structure, mapping, output, results, dispatch).

- [ ] **Step 6: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: pilot tools (system-uptime, temp-cleanup) in template shape"
```

---

### Task 7: Bootstrap, entry param block, and main entry

**Files:**
- Create: `src\core\01-bootstrap.ps1`
- Create: `src\entry\00-param.ps1`
- Create: `src\entry\99-main.ps1`

These three files only make sense assembled (param block must be the artifact's first statement), so they're tested via the build in Task 8 — no unit tests here.

- [ ] **Step 1: Create `src\core\01-bootstrap.ps1`** (elevation logic ported from v8 lines 46-84, gated to interactive mode)

```powershell
# Admin detection and interactive elevation. CLI/PDQ mode never auto-elevates;
# PDQ runs as SYSTEM, and a UAC prompt would hang an unattended deployment.

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-ElevationCheck {
    if (Test-IsAdmin) { return }
    Write-Host 'Requesting administrator privileges...' -ForegroundColor Yellow
    try {
        $scriptPath = $PSCommandPath
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            throw 'Unable to determine script path for elevation.'
        }
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process -FilePath 'PowerShell.exe' -ArgumentList $arguments -Verb RunAs
    } catch {
        Write-Host 'ERROR: Failed to request administrator privileges.' -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host 'Run PowerShell as Administrator and re-launch the script.' -ForegroundColor Yellow
        if ([Environment]::UserInteractive) { Read-Host 'Press Enter to exit' | Out-Null }
    }
    exit
}
```

- [ ] **Step 2: Create `src\entry\00-param.ps1`** (becomes the artifact's param block)

```powershell
[CmdletBinding()]
param(
    [string]$Tool,        # run one tool by slug or legacy number, then exit
    [switch]$Silent,      # no prompts; Read-ToolChoice returns declared defaults
    [switch]$Force,       # allow Disruptive tools under -Silent
    [switch]$ListTools,   # print the tool inventory and exit
    [string]$LogPath      # directory for the session log file
)
```

- [ ] **Step 3: Create `src\entry\99-main.ps1`**

```powershell
# ---- Entry point ------------------------------------------------------------
$script:IsAdmin = Test-IsAdmin

if ($LogPath) {
    Set-OutputSink -Sink Console -LogDirectory $LogPath
}

if ($ListTools) {
    Get-NmmTools | ForEach-Object { [PSCustomObject]$_ } |
        Sort-Object Category, Name |
        Format-Table Id, LegacyId, Name, Category, Risk, SilentCapable -AutoSize
    exit 0
}

if ($Tool) {
    $resolved = Resolve-NmmTool -Query $Tool
    if (-not $resolved) {
        Write-ToolOutput "No tool matches '$Tool'. Use -ListTools to see available tools." -Level Error
        exit 1
    }
    $status = Invoke-NmmTool -Tool $resolved -Silent:$Silent -Force:$Force
    if ($status -eq 'Success' -or $status -eq 'Skipped' -or $status -eq 'Warning') { exit 0 }
    exit 1
}

# Interactive mode: elevate, then menu
Invoke-ElevationCheck
Start-ConsoleMenu
```

- [ ] **Step 4: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: bootstrap elevation, artifact param block, main entry"
```

---

### Task 8: Build script + artifact smoke tests

**Files:**
- Create: `build.ps1`
- Test: `tests\artifact.tests.ps1`

- [ ] **Step 1: Write the failing artifact tests**

`tests\artifact.tests.ps1`:
```powershell
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    & (Join-Path $repoRoot 'build.ps1') -SkipAnalyzer | Out-Null
    $script:Artifact = Join-Path $repoRoot 'dist\NMMTools.ps1'
}

Describe 'Built artifact' {
    It 'exists' {
        Test-Path $script:Artifact | Should -BeTrue
    }

    It 'parses with zero errors under the PS 5.1 parser' {
        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:Artifact, [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }

    It 'contains the core functions and pilot tools' {
        $content = Get-Content $script:Artifact -Raw
        foreach ($fn in 'Write-ToolOutput','Read-ToolChoice','New-ToolRun','Complete-ToolRun',
                        'Resolve-NmmTool','Invoke-NmmTool','Get-SystemUptime','Start-TempFilesCleanup',
                        'Start-ConsoleMenu') {
            $content | Should -Match ("function {0}" -f [regex]::Escape($fn))
        }
    }

    It 'lists tools when run with -ListTools' {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact -ListTools
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'system-uptime'
        ($out -join "`n") | Should -Match 'temp-cleanup'
    }

    It 'runs a read-only tool silently with exit code 0' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact `
            -Tool system-uptime -Silent | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 for an unknown tool' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact `
            -Tool does-not-exist -Silent | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\artifact.tests.ps1 -Output Detailed`
Expected: FAIL — `build.ps1` does not exist. (Note: `Start-ConsoleMenu` is built in Task 9; the "contains core functions" test will keep failing until then — that is expected, see Step 4.)

- [ ] **Step 3: Implement `build.ps1`**

```powershell
[CmdletBinding()]
param(
    [string]$Version = '9.0.0-dev',
    [switch]$SkipAnalyzer
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$artifact = Join-Path $dist 'NMMTools.ps1'

$parts = New-Object System.Collections.Generic.List[string]
$parts.Add('#Requires -Version 5.1')
$parts.Add(('# NMM System Toolkit v{0} | built {1:yyyy-MM-dd HH:mm} | GENERATED by build.ps1 - DO NOT EDIT' -f $Version, (Get-Date)))
$parts.Add('# Source: NMMToolkit repo. Edit src\, then rebuild.')

# 1. Param block must be the first statement in the artifact
$parts.Add((Get-Content (Join-Path $root 'src\entry\00-param.ps1') -Raw))

# 2. Core, in numeric-prefix order
foreach ($f in (Get-ChildItem (Join-Path $root 'src\core') -Filter *.ps1 | Sort-Object Name)) {
    $parts.Add(('#region core\{0}' -f $f.Name))
    $parts.Add((Get-Content $f.FullName -Raw))
    $parts.Add('#endregion')
}

# 3. Registry: psd1 content is a valid hashtable literal, assigned directly
$parts.Add('#region registry')
$parts.Add('$script:RegistryData =')
$parts.Add((Get-Content (Join-Path $root 'src\registry\tools.psd1') -Raw))
$parts.Add('#endregion')

# 4. Tools
foreach ($f in (Get-ChildItem (Join-Path $root 'src\tools') -Recurse -Filter *.ps1 | Sort-Object FullName)) {
    $parts.Add(('#region tools\{0}\{1}' -f $f.Directory.Name, $f.Name))
    $parts.Add((Get-Content $f.FullName -Raw))
    $parts.Add('#endregion')
}

# 5. Entry point last
$parts.Add((Get-Content (Join-Path $root 'src\entry\99-main.ps1') -Raw))

Set-Content -Path $artifact -Value ($parts -join "`r`n") -Encoding UTF8

# Gate 1: parse
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($artifact, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    $parseErrors | ForEach-Object { Write-Host ('{0} (line {1})' -f $_.Message, $_.Extent.StartLineNumber) -ForegroundColor Red }
    throw ('Artifact has {0} parse error(s) - build failed' -f $parseErrors.Count)
}

# Gate 2: analyzer (errors only; warnings like PSAvoidUsingWriteHost are accepted)
if (-not $SkipAnalyzer) {
    Import-Module PSScriptAnalyzer
    $findings = Invoke-ScriptAnalyzer -Path $artifact -Severity Error
    if ($findings) {
        $findings | Format-Table RuleName, Line, Message -AutoSize | Out-String | Write-Host
        throw ('PSScriptAnalyzer found {0} error(s) - build failed' -f @($findings).Count)
    }
}

$sizeKB = [math]::Round((Get-Item $artifact).Length / 1KB)
Write-Host ('Built {0} ({1} KB, v{2})' -f $artifact, $sizeKB, $Version) -ForegroundColor Green
```

- [ ] **Step 4: Run artifact tests — expect one remaining failure**

Run: `Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests\artifact.tests.ps1 -Output Detailed`
Expected: all PASS **except** "contains the core functions" (no `Start-ConsoleMenu` yet — Task 9 supplies it). The `-Tool`/`-ListTools` CLI tests must PASS now. If the parse test fails, fix before continuing.

- [ ] **Step 5: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: single-file build with parse and analyzer gates"
```

---

### Task 9: Console menu

**Files:**
- Create: `src\core\05-ui-console.ps1`

Menu logic is interactive; it's verified by the artifact tests (function presence) plus a scripted manual check in Step 3. Input precedence inside the menu: **category number → legacy/slug match → search**. (Legacy numbers 1-7 collide with category indexes; category browse wins there, and those seven tools remain reachable via the category listing or search — accepted trade-off.)

- [ ] **Step 1: Implement `src\core\05-ui-console.ps1`**

```powershell
# Console UI. Landing screen = categories + search; everything is driven by
# the registry, so new tools appear automatically.

function Show-LandingMenu {
    $tools = Get-NmmTools
    $categories = $tools | ForEach-Object { $_.Category } | Sort-Object -Unique
    Write-Host ''
    Write-Host ('=' * 66) -ForegroundColor Cyan
    Write-Host (' NMM System Toolkit v9      {0}\{1}' -f $env:COMPUTERNAME, $env:USERNAME) -ForegroundColor Cyan
    Write-Host ('=' * 66) -ForegroundColor Cyan
    if ($script:ToolRuns.Count -gt 0) {
        $recent = @($script:ToolRuns | Select-Object -Last 3 | ForEach-Object { $_.Name })
        Write-Host (' Recent: {0}' -f ($recent -join ' | ')) -ForegroundColor DarkGray
    }
    $index = 1
    $map = @{}
    foreach ($c in $categories) {
        $count = @($tools | Where-Object { $_.Category -eq $c }).Count
        Write-Host (' {0}. {1} ({2} tools)' -f $index, $c, $count)
        $map["$index"] = $c
        $index++
    }
    Write-Host ''
    Write-Host ' Enter: category number | tool number/name | search text' -ForegroundColor Gray
    Write-Host '        T = ticket summary   X = exit' -ForegroundColor Gray
    return $map
}

function Show-CategoryTools {
    param([Parameter(Mandatory)][string]$Category)
    $tools = Get-NmmTools | Where-Object { $_.Category -eq $Category } | Sort-Object Name
    Write-Host ''
    Write-Host (' --- {0} ---' -f $Category) -ForegroundColor Cyan
    foreach ($t in $tools) {
        $admin = ''
        if ($t.RequiresAdmin) { $admin = ' [admin]' }
        Write-Host (' {0,4}. {1}{2}' -f $t.LegacyId, $t.Name, $admin)
        Write-Host ('       {0}' -f $t.Description) -ForegroundColor Gray
    }
    Write-Host ''
    $selection = Read-Host ' Tool number to run (Enter to go back)'
    if (-not [string]::IsNullOrWhiteSpace($selection)) {
        Invoke-MenuSelection -Selection $selection.Trim()
    }
}

function Invoke-MenuSelection {
    param([Parameter(Mandatory)][string]$Selection)
    $tool = Resolve-NmmTool -Query $Selection
    if ($tool) {
        Invoke-NmmTool -Tool $tool | Out-Null
        Read-Host 'Press Enter to continue' | Out-Null
        return
    }
    $found = @(Search-NmmTools -Term $Selection)
    if ($found.Count -eq 0) {
        Write-Host (" Nothing matches '{0}'." -f $Selection) -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host (' Matches for "{0}":' -f $Selection) -ForegroundColor Cyan
    foreach ($t in $found) {
        Write-Host (' {0,4}. {1}  ({2})' -f $t.LegacyId, $t.Name, $t.Category)
    }
    $pick = Read-Host ' Tool number to run (Enter to cancel)'
    if (-not [string]::IsNullOrWhiteSpace($pick)) {
        $tool = Resolve-NmmTool -Query $pick.Trim()
        if ($tool) {
            Invoke-NmmTool -Tool $tool | Out-Null
            Read-Host 'Press Enter to continue' | Out-Null
        }
    }
}

function Start-ConsoleMenu {
    while ($true) {
        $map = Show-LandingMenu
        $selection = Read-Host ' Select'
        if ([string]::IsNullOrWhiteSpace($selection)) { continue }
        $selection = $selection.Trim()
        if ($selection -match '^[Xx]$') { return }
        if ($selection -match '^[Tt]$') {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $path = Join-Path $env:USERPROFILE ('Desktop\NMM-TicketSummary-{0}.txt' -f $stamp)
            $text = Export-TicketSummary -Path $path
            Write-Host $text
            Write-Host (' Saved to {0}' -f $path) -ForegroundColor Green
            Read-Host ' Press Enter to continue' | Out-Null
            continue
        }
        if ($map.ContainsKey($selection)) {
            Show-CategoryTools -Category $map[$selection]
            continue
        }
        Invoke-MenuSelection -Selection $selection
    }
}
```

- [ ] **Step 2: Rebuild and run the full test suite**

Run:
```powershell
& C:\Users\IT\Desktop\NMMToolkit\build.ps1
Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests -Output Detailed
```
Expected: build succeeds (both gates), ALL tests pass including the Task 8 "contains core functions" test.

- [ ] **Step 3: Manual interactive smoke test**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\IT\Desktop\NMMToolkit\dist\NMMTools.ps1` (accept the UAC prompt)
Verify, then exit with X:
1. Landing menu shows `Diagnostics (2 tools)`
2. Entering `1` lists both pilot tools with descriptions
3. Entering `20` runs System Uptime and returns to the menu
4. Entering `uptime` finds System Uptime via search
5. Entering `T` prints the session summary listing the runs from steps 3-4 and saves the file to the Desktop

- [ ] **Step 4: Commit**

```powershell
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "feat: registry-driven console menu with search and ticket export"
```

---

### Task 10: PDQ-style end-to-end verification + wrap-up

**Files:**
- Modify: `README.md` (add CLI examples section)

- [ ] **Step 1: Verify the full CLI surface as PDQ would call it**

Run each and check exit codes:
```powershell
$a = 'C:\Users\IT\Desktop\NMMToolkit\dist\NMMTools.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $a -ListTools; $LASTEXITCODE                       # expect 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $a -Tool system-uptime -Silent; $LASTEXITCODE     # expect 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $a -Tool 20 -Silent; $LASTEXITCODE                # expect 0 (legacy id)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $a -Tool temp-cleanup -Silent -LogPath $env:TEMP; $LASTEXITCODE  # expect 0; check %TEMP% for NMMTools-*.log
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $a -Tool nope -Silent; $LASTEXITCODE              # expect 1
```
Confirm the `-LogPath` run created `NMMTools-<computer>-<stamp>.log` in `%TEMP%` containing the temp-cleanup output, and that `-Silent` auto-answered the "Delete temp files now?" prompt with Yes.

- [ ] **Step 2: Append CLI examples to `README.md`**

Append:
```markdown
## CLI / PDQ usage

    NMMTools.ps1 -ListTools
    NMMTools.ps1 -Tool system-uptime -Silent
    NMMTools.ps1 -Tool 20 -Silent                      # legacy v8 menu number
    NMMTools.ps1 -Tool temp-cleanup -Silent -LogPath C:\Logs

Exit code 0 = Success/Warning/Skipped, 1 = Failed/Refused/unknown tool.
`-Silent` refuses tools registered `SilentCapable = $false`, and refuses
`Risk = 'Disruptive'` tools unless `-Force` is added.
```

- [ ] **Step 3: Final full test run and commit**

```powershell
& C:\Users\IT\Desktop\NMMToolkit\build.ps1
Invoke-Pester C:\Users\IT\Desktop\NMMToolkit\tests -Output Detailed
git -C C:\Users\IT\Desktop\NMMToolkit add -A
git -C C:\Users\IT\Desktop\NMMToolkit commit -m "docs: CLI usage; foundation milestone complete"
```
Expected: build green, all tests pass.

---

## After this plan

Separate follow-up plans (in order):
1. **Porting batches 1-7** — one plan per category from the v8 monolith (Diagnostics remainder, Cloud, Repair, Laptop, Browser, UserIssues, Security), each tool rewritten to the template + registry entry + rebuild + smoke test. Parity checklist tracks ported/consolidated/retired per spec §8.
2. **GUI launcher** (`src\core\06-ui-gui.ps1`) — reads the same registry, swaps the output sink.
3. **Cutover** — parity review, share/PDQ swap, v8 archived as fallback.
