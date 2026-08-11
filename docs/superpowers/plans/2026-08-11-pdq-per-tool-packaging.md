# PDQ Per-Tool Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit one self-contained, PDQ-deployable `.ps1` per opted-in registry tool, so each tool gets its own PDQ Deploy package, its own review surface, and an artifact that runs with no toolkit present.

**Architecture:** A fourth output sink (`Pdq`) writes through `[Console]::Out` so output survives PDQ's redirected stdout. A new registry field (`PdqDeployable`) opts tools in. `build.ps1 -Pdq` then emits `dist\pdq\<tool-id>.ps1` for each flagged tool: provenance header, param block, the seven headless core files verbatim, a single-entry registry, the tool function, and a generated entry point mapping tool status to distinct exit codes.

**Tech Stack:** PowerShell 5.1, Pester 5.x, PSScriptAnalyzer.

**Spec:** `docs\superpowers\specs\2026-08-11-pdq-per-tool-packaging-design.md` (Approved).

**Prerequisite (already shipped):** version tracking, merged at `e7ecd61`. `build.ps1` already captures `$buildDate` and `$commit` once, before any emission, so the emitter reuses them directly.

## Global Constraints

- PowerShell 5.1 is the target. No PS7-only syntax: no ternary `?:`, no `??`, no `?.`.
- Never `(if ($x) { 'a' } else { 'b' })` as an inline argument. Always `$(if ($x) { 'a' } else { 'b' })`. The parser accepts the former and it throws `CommandNotFoundException` at runtime.
- ASCII only in all source files. No em dashes, smart quotes, or box-drawing characters.
- Files read by anything other than PowerShell, and all generated artifacts, are written with
  `[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))`.
  Never `Set-Content -Encoding UTF8`: it means "with BOM" on 5.1 and "without BOM" on 7.
- Inside double-quoted strings, a literal `$` must be backtick-escaped. Never use `${}`.
- `src\` files use `Write-ToolOutput`, never `Write-Host`. `build.ps1` is exempt.
- Every code path in a tool ends in exactly one `Complete-ToolRun`. This plan adds no tools.
- The three provenance variables are exactly `$script:ToolkitVersion`, `$script:ToolkitCommit`, `$script:ToolkitBuildDate`.
- Full gate before any commit is considered done: `.\build.ps1` then `Invoke-Pester .\tests`.
- Baseline entering this plan: **157 passing, 0 failing.**

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `src\core\02-output.ps1` | Modify | Add the `Pdq` sink to `Set-OutputSink`'s ValidateSet and a matching branch in `Write-ToolOutput` |
| `src\registry\tools.psd1` | Modify (115 entries) | Add `PdqDeployable` after `SilentCapable`; seed `system-info` as the only `$true` |
| `CLAUDE.md` | Modify | Document the new registry field in the "Adding a tool" contract |
| `build.ps1` | Modify | Add `-Pdq` switch and the per-tool emitter with its own parse/analyzer gates |
| `tests\output.tests.ps1` | Modify | Cover the `Pdq` sink, including that it does not emit on the success stream |
| `tests\registry.tests.ps1` | Modify | Require `PdqDeployable` on every entry |
| `tests\pdq-emit.tests.ps1` | Create | Structural and behavioural coverage of the generated scripts |

Four tasks. Each is independently reviewable: the sink is useful and testable before any emitter exists; the registry field is inert data until the emitter reads it; the emitter produces files; the behavioural tests prove those files run under PDQ conditions.

---

### Task 1: Add the `Pdq` output sink

**Files:**
- Modify: `src\core\02-output.ps1` (the `Set-OutputSink` ValidateSet, and `Write-ToolOutput`'s sink branches)
- Test: `tests\output.tests.ps1`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Set-OutputSink -Sink Pdq` becomes valid. With that sink active, `Write-ToolOutput -Message <string> -Level <Info|Success|Warning|Error|Detail>` writes one line to process stdout in the form `[Level  ] Message` (Level left-padded to 7 characters) and returns nothing on the PowerShell success stream. Task 3's generated entry point calls `Set-OutputSink -Sink Pdq -LogDirectory $LogPath`.

- [ ] **Step 1: Write the failing tests**

Add this `Describe` block to the end of `tests\output.tests.ps1`:

```powershell
Describe 'Pdq output sink' {
    AfterEach { Set-OutputSink -Sink Console }

    It 'accepts Pdq as a sink' {
        { Set-OutputSink -Sink Pdq } | Should -Not -Throw
    }

    It 'writes nothing to the PowerShell success stream' {
        # This is the whole reason the sink uses [Console]::Out.WriteLine rather
        # than Write-Output. Invoke-NmmTool ends with `return $run.Status`, so if
        # Write-ToolOutput emitted on the success stream every log line would ride
        # back as part of that return value and the status-to-exit-code mapping in
        # a generated PDQ script would receive an array instead of a string.
        Set-OutputSink -Sink Pdq
        $captured = Write-ToolOutput 'must not reach the pipeline' -Level Info
        $captured | Should -BeNullOrEmpty
    }

    It 'still writes to the log file when a log directory is set' {
        $script:tmpDir = Join-Path $env:TEMP "nmm-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $script:tmpDir | Out-Null
        Set-OutputSink -Sink Pdq -LogDirectory $script:tmpDir
        Write-ToolOutput 'pdq line to log' -Level Warning
        $logFile = Get-ChildItem $script:tmpDir -Filter *.log | Select-Object -First 1
        $logFile | Should -Not -BeNullOrEmpty
        Get-Content $logFile.FullName -Raw | Should -Match 'pdq line to log'
        Set-OutputSink -Sink Console
        Remove-Item $script:tmpDir -Recurse -Force
        $script:tmpDir = $null
    }

    It 'reaches redirected stdout of a child process' {
        # [Console]::Out and Write-Host are indistinguishable in-process: both
        # appear on the console and both look correct. The sink exists for its
        # behaviour under redirection, which only exists when something redirects.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $core     = Join-Path $repoRoot 'src\core\02-output.ps1'
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
            ". '$core'; Set-OutputSink -Sink Pdq; Write-ToolOutput 'child stdout probe' -Level Info"
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'child stdout probe'
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester .\tests\output.tests.ps1`

Expected: FAIL. `Set-OutputSink -Sink Pdq` throws a ValidateSet error, so all four fail. Every pre-existing test in the file must still pass.

- [ ] **Step 3: Extend the ValidateSet**

In `src\core\02-output.ps1`, in `Set-OutputSink`, change:

```powershell
        [Parameter(Mandatory)][ValidateSet('Console','Silent','GUI')][string]$Sink,
```

to:

```powershell
        [Parameter(Mandatory)][ValidateSet('Console','Silent','GUI','Pdq')][string]$Sink,
```

- [ ] **Step 4: Add the sink branch to Write-ToolOutput**

In `src\core\02-output.ps1`, in `Write-ToolOutput`, the sink branches currently read
`if ($script:OutputSink -eq 'Console') { ... } elseif ($script:OutputSink -eq 'GUI') { ... } elseif ($script:OutputSink -eq 'Capture') { ... }`.

Add a new branch immediately after the `'Console'` branch closes and before `elseif ($script:OutputSink -eq 'GUI')`:

```powershell
    } elseif ($script:OutputSink -eq 'Pdq') {
        # PDQ Deploy captures the step's stdout. Write-Host goes to the host UI,
        # so with no host there is nothing to capture; Write-Output goes to the
        # success stream, which would corrupt Invoke-NmmTool's returned status.
        # [Console]::Out is process stdout directly - captured, and never on the
        # pipeline.
        [Console]::Out.WriteLine(('[{0,-7}] {1}' -f $Level, $Message))
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Invoke-Pester .\tests\output.tests.ps1`

Expected: PASS, all tests in the file.

- [ ] **Step 6: Run the full gate**

Run: `.\build.ps1` then `Invoke-Pester .\tests`

Expected: build succeeds, suite passes. 157 + 4 = **161 passing, 0 failing**.

- [ ] **Step 7: Commit**

```bash
git add src/core/02-output.ps1 tests/output.tests.ps1
git commit -m "feat(core): add a Pdq output sink that writes to process stdout

PDQ Deploy captures a step's stdout, but the Console sink emits through
Write-Host, which goes to the host UI - so a script using it produces no
captured output under PDQ. The new sink writes via [Console]::Out.

Write-Output would have been worse than Write-Host here: Invoke-NmmTool
ends with 'return \$run.Status', so log lines on the success stream would
ride back as part of that return value and any status-to-exit-code
mapping would receive an array instead of a string. [Console]::Out is
process stdout directly and never touches the pipeline.

Tested in a child process with redirected stdout, because in-process
[Console]::Out and Write-Host are indistinguishable."
```

---

### Task 2: Add the `PdqDeployable` registry field

**Files:**
- Modify: `src\registry\tools.psd1` (all 115 entries)
- Modify: `CLAUDE.md` (the registry field contract in "Adding a tool")
- Test: `tests\registry.tests.ps1`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: every entry in `$script:RegistryData.Tools` has a `PdqDeployable` key holding a `[bool]`. Exactly one entry is `$true`: `system-info`. Task 3's emitter filters on this field.

- [ ] **Step 1: Write the failing test**

Add this `It` block to `tests\registry.tests.ps1`, inside its existing top-level `Describe`:

```powershell
    It 'declares PdqDeployable as a boolean on every tool' {
        $offenders = @()
        foreach ($tool in @($script:Registry.Tools)) {
            if (-not $tool.ContainsKey('PdqDeployable')) {
                $offenders += ('{0} (missing)' -f $tool.Id)
            } elseif ($tool.PdqDeployable -isnot [bool]) {
                $offenders += ('{0} (not a bool)' -f $tool.Id)
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty -Because 'every tool must make an explicit decision about PDQ deployment'
    }

    It 'has at least one PdqDeployable tool and system-info is one of them' {
        $flagged = @(@($script:Registry.Tools) | Where-Object { $_.PdqDeployable })
        $flagged.Count | Should -BeGreaterThan 0
        $flagged.Id | Should -Contain 'system-info'
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\registry.tests.ps1`

Expected: FAIL. The first new test lists all 115 tool ids as `(missing)`; the second fails because no tool is flagged.

- [ ] **Step 3: Add the field to all 115 entries**

Every entry has a `    SilentCapable = $true` line (all 115 are `$true`; confirm with
`Select-String -Path src\registry\tools.psd1 -Pattern 'SilentCapable' | Measure-Object` before and after). Insert `PdqDeployable = $false` immediately after each, preserving the file's column alignment. Run this from the repo root:

```powershell
$path    = 'src\registry\tools.psd1'
$content = [System.IO.File]::ReadAllText($path)
$before  = ([regex]::Matches($content, 'SilentCapable = \$true')).Count
$content = $content -replace '(?m)^(\s*)SilentCapable = \$true\r?$', "`$1SilentCapable = `$true`r`n`$1PdqDeployable = `$false"
$after   = ([regex]::Matches($content, 'PdqDeployable = \$false')).Count
Write-Output "SilentCapable lines: $before ; PdqDeployable inserted: $after"
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
```

Both counts must print 115. If they differ, stop and report it rather than hand-patching - a mismatch means an entry has a different `SilentCapable` value or spacing than assumed.

Note this rewrite also strips the file's existing UTF-8 BOM, which is fine and consistent with the project's stated encoding rule. `Import-PowerShellDataFile` and `Get-Content -Raw -Encoding UTF8` both handle either form.

- [ ] **Step 4: Seed system-info as the only deployable tool**

In `src\registry\tools.psd1`, find the entry with `Id            = 'system-info'` and change its `PdqDeployable = $false` to `PdqDeployable = $true`. It is ReadOnly, needs no admin, and is silent-capable, which makes it the safe seed for the smoke test in Task 4.

Leave all other entries `$false`. Choosing the operational set is a separate data change, not part of this work.

- [ ] **Step 5: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\registry.tests.ps1`

Expected: PASS, all tests in the file.

- [ ] **Step 6: Update the tool contract in CLAUDE.md**

In `CLAUDE.md`, in the "Adding a tool (the contract)" section, the registry entry code block lists the fields in order. Add `PdqDeployable` between `SilentCapable` and `Risk`:

```powershell
    SilentCapable = $true                # $false only if tool cannot run headless
    PdqDeployable = $false               # $true emits dist\pdq\<id>.ps1 via build.ps1 -Pdq
    Risk          = 'ReadOnly'           # ReadOnly | Modifies | Disruptive
```

- [ ] **Step 7: Run the full gate**

Run: `.\build.ps1` then `Invoke-Pester .\tests`

Expected: build succeeds, suite passes. 161 + 2 = **163 passing, 0 failing**.

- [ ] **Step 8: Commit**

```bash
git add src/registry/tools.psd1 tests/registry.tests.ps1 CLAUDE.md
git commit -m "feat(registry): add PdqDeployable opt-in field to every tool

Adds the field to all 115 entries defaulted to false, and flips
system-info to true as the seed for the emitter's smoke test. A registry
test now requires the field on every entry, so a new tool cannot be added
without an explicit decision about whether it ships as a standalone PDQ
package.

Choosing the operational set of deployable tools is a separate data
change and is deliberately not part of this commit."
```

---

### Task 3: Add the `build.ps1 -Pdq` emitter

**Files:**
- Modify: `build.ps1` (new `[switch]$Pdq` param; new emit section after the artifact's analyzer gate)
- Create: `tests\pdq-emit.tests.ps1`

**Interfaces:**
- Consumes: `PdqDeployable` from Task 2; `$script:ToolkitVersion`/`$script:ToolkitCommit`/`$script:ToolkitBuildDate` conventions and the already-captured `$buildDate`/`$commit` variables in `build.ps1`; the `Pdq` sink from Task 1.
- Produces: `.\build.ps1 -Pdq` writes `dist\pdq\<tool-id>.ps1` for each flagged tool. Each generated script accepts `-Force`, `-LogPath`, `-Version`. Task 4 exercises them.

- [ ] **Step 1: Write the failing tests**

Create `tests\pdq-emit.tests.ps1`:

```powershell
BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    & (Join-Path $script:RepoRoot 'build.ps1') -Pdq -SkipAnalyzer | Out-Null
    $script:PdqDir   = Join-Path $script:RepoRoot 'dist\pdq'
    $script:Registry = Import-PowerShellDataFile (Join-Path $script:RepoRoot 'src\registry\tools.psd1')
    $script:Flagged  = @(@($script:Registry.Tools) | Where-Object { $_.PdqDeployable })
}

Describe 'PDQ per-tool emitter' {
    It 'creates the output directory' {
        Test-Path $script:PdqDir | Should -BeTrue
    }

    It 'emits exactly one script per flagged tool and none for unflagged tools' {
        $emitted  = @(Get-ChildItem $script:PdqDir -Filter *.ps1 | ForEach-Object { $_.BaseName })
        $expected = @($script:Flagged | ForEach-Object { $_.Id })
        ($emitted | Sort-Object) -join ',' | Should -Be (($expected | Sort-Object) -join ',')
    }

    It 'emits scripts that parse with zero errors' {
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0 -Because ('{0} must parse' -f $f.Name)
        }
    }

    It 'emits scripts with no analyzer errors' {
        Import-Module PSScriptAnalyzer
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $findings = Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error
            @($findings).Count | Should -Be 0 -Because ('{0} must be analyzer-clean' -f $f.Name)
        }
    }

    It 'emits scripts that reference no function from the dropped cores' {
        # The headless build omits 05-ui-console, 06-usage, 09-ui-wpf and 10-jira.
        # No tool references them today, but nothing stops one gaining such a call
        # later - and the failure would be a CommandNotFoundException on every
        # endpoint rather than anything visible at build time.
        $dropped = @('05-ui-console.ps1','06-usage.ps1','09-ui-wpf.ps1','10-jira.ps1')
        $names   = @()
        foreach ($d in $dropped) {
            $text   = Get-Content (Join-Path $script:RepoRoot ('src\core\' + $d)) -Raw
            $names += [regex]::Matches($text, '(?m)^function\s+([\w-]+)') |
                      ForEach-Object { $_.Groups[1].Value }
        }
        $offenders = @()
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $content = Get-Content $f.FullName -Raw
            foreach ($n in $names) {
                if ($content -match ('\b' + [regex]::Escape($n) + '\b')) {
                    $offenders += ('{0} references {1}' -f $f.Name, $n)
                }
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty
    }

    It 'emits UTF-8 scripts with no BOM and no non-ASCII bytes' {
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
                Should -BeFalse -Because ('{0} must have no BOM' -f $f.Name)
            @($bytes | Where-Object { $_ -gt 127 }).Count |
                Should -Be 0 -Because ('{0} must be ASCII-only' -f $f.Name)
        }
    }

    It 'carries the same provenance as the main artifact' {
        $artifact = Get-Content (Join-Path $script:RepoRoot 'dist\NMMTools.ps1') -Raw
        $header   = [regex]::Match($artifact, "ToolkitCommit\s*=\s*'([^']+)'")
        $header.Success | Should -BeTrue
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            Get-Content $f.FullName -Raw |
                Should -Match ("ToolkitCommit\s*=\s*'{0}'" -f [regex]::Escape($header.Groups[1].Value))
        }
    }

    It 'emits scripts that never invoke a language keyword as a command' {
        # The spec asks for ps51-runtime.tests.ps1 to cover dist\pdq. It lives
        # here instead: that file scans src\ with no build step, and pointing it
        # at generated output would make it depend on build.ps1 -Pdq having run
        # in another test file. This file already builds with -Pdq in BeforeAll.
        # Same check, same class - `(if ($x) { 'a' } else { 'b' })` parses fine
        # and throws CommandNotFoundException at runtime on PS 5.1.
        $keywords = @('if','else','elseif','switch','foreach','for','while','do',
                      'try','catch','finally','return','throw','param','begin',
                      'process','end','until','trap','data')
        $offenders = @()
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$null)
            $commands = $ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)
            foreach ($c in $commands) {
                $name = $c.GetCommandName()
                if ($name -and $keywords -contains $name) {
                    $offenders += ('{0}:{1} {2}' -f $f.Name, $c.Extent.StartLineNumber, $name)
                }
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty
    }

    It 'removes scripts for tools that lost the flag' {
        $stale = Join-Path $script:PdqDir 'zzz-stale-tool.ps1'
        Set-Content -Path $stale -Value '# stale'
        & (Join-Path $script:RepoRoot 'build.ps1') -Pdq -SkipAnalyzer | Out-Null
        Test-Path $stale | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester .\tests\pdq-emit.tests.ps1`

Expected: FAIL. `build.ps1` has no `-Pdq` parameter, so `BeforeAll` errors with a parameter-binding failure and every test in the file fails.

- [ ] **Step 3: Add the -Pdq switch**

In `build.ps1`, change the param block to:

```powershell
[CmdletBinding()]
param(
    [string]$Version = '9.1.0',
    [switch]$SkipAnalyzer,
    [switch]$Pdq
)
```

- [ ] **Step 4: Add the emitter**

Append this to the very end of `build.ps1`, after the existing final `Write-Host ('Built {0} ...` line:

```powershell
# ---- 6. PDQ per-tool scripts (opt-in) ---------------------------------------
# Each emitted script is self-contained: the seven headless core files, a
# single-entry registry, one tool function, and an entry point. The console
# menu, usage store, WPF GUI and Jira cores are omitted - nothing under
# src\tools references them, and they are 2152 of the 2770 core lines.
if ($Pdq) {
    $pdqDir = Join-Path $dist 'pdq'
    # Wipe and recreate so a tool that loses its flag leaves no stale script
    # behind for someone to deploy.
    if (Test-Path $pdqDir) { Remove-Item $pdqDir -Recurse -Force }
    New-Item -ItemType Directory -Force $pdqDir | Out-Null

    $registryData = Import-PowerShellDataFile (Join-Path $root 'src\registry\tools.psd1')
    $headlessCore = @('01-bootstrap.ps1','02-output.ps1','03-results.ps1','04-dispatch.ps1',
                      '07-repair-helpers.ps1','08-browser-helpers.ps1',
                      '11-diagnostic-bundle-helpers.ps1')

    $emitted = 0
    foreach ($tool in @($registryData.Tools)) {
        if (-not $tool.PdqDeployable) { continue }

        $toolFile = $toolFiles | Where-Object { $_.BaseName -eq $tool.Function } | Select-Object -First 1
        if (-not $toolFile) {
            throw ("PdqDeployable tool '{0}' declares Function '{1}' with no matching file under src\tools" -f $tool.Id, $tool.Function)
        }

        $q = { param([string]$s) $s -replace "'", "''" }

        $g = New-Object System.Collections.Generic.List[string]
        $g.Add('#Requires -Version 5.1')
        $g.Add(('# NMM PDQ tool: {0} -> {1}' -f $tool.Id, $tool.Function))
        $g.Add(('# NMM System Toolkit v{0} ({1}) | built {2:yyyy-MM-dd HH:mm}' -f $Version, $commit, $buildDate))
        $g.Add('# GENERATED by build.ps1 -Pdq - DO NOT EDIT')
        $g.Add(('# Source: NMMToolkit repo, src\tools\{0}\{1}' -f $toolFile.Directory.Name, $toolFile.Name))
        $g.Add('')
        $g.Add('[CmdletBinding()]')
        $g.Add('param(')
        $g.Add('    [switch]$Force,      # required for Disruptive tools')
        $g.Add('    [string]$LogPath,    # optional file log in addition to stdout')
        $g.Add('    [switch]$Version     # print provenance and exit 0')
        $g.Add(')')
        $g.Add('')
        $g.Add('#region provenance')
        $g.Add(("`$script:ToolkitVersion   = '{0}'" -f (& $q $Version)))
        $g.Add(("`$script:ToolkitCommit    = '{0}'" -f (& $q $commit)))
        $g.Add(("`$script:ToolkitBuildDate = '{0:yyyy-MM-dd HH:mm}'" -f $buildDate))
        $g.Add(("`$script:PdqToolId        = '{0}'" -f (& $q $tool.Id)))
        $g.Add('#endregion')

        foreach ($name in $headlessCore) {
            $g.Add(('#region core\{0}' -f $name))
            $g.Add((Get-Content (Join-Path $root ('src\core\' + $name)) -Raw -Encoding UTF8))
            $g.Add('#endregion')
        }

        $g.Add('#region registry')
        $g.Add('$script:RegistryData = @{ Tools = @(')
        $g.Add('    @{')
        $g.Add(("        Id            = '{0}'" -f (& $q $tool.Id)))
        $g.Add(("        LegacyId      = '{0}'" -f (& $q $tool.LegacyId)))
        $g.Add(("        Name          = '{0}'" -f (& $q $tool.Name)))
        $g.Add(("        Category      = '{0}'" -f (& $q $tool.Category)))
        $g.Add(("        Function      = '{0}'" -f (& $q $tool.Function)))
        $g.Add(("        Description   = '{0}'" -f (& $q $tool.Description)))
        $g.Add(("        RequiresAdmin = `${0}" -f $tool.RequiresAdmin))
        $g.Add(("        SilentCapable = `${0}" -f $tool.SilentCapable))
        $g.Add(("        PdqDeployable = `${0}" -f $tool.PdqDeployable))
        $g.Add(("        Risk          = '{0}'" -f (& $q $tool.Risk)))
        $g.Add(("        Tags          = @({0})" -f ((@($tool.Tags) | ForEach-Object { "'" + (& $q $_) + "'" }) -join ',')))
        $g.Add('    }')
        $g.Add(') }')
        $g.Add('#endregion')

        $g.Add(('#region tool\{0}' -f $toolFile.Name))
        $g.Add((Get-Content $toolFile.FullName -Raw -Encoding UTF8))
        $g.Add('#endregion')

        $g.Add('# ---- Entry point ----')
        $g.Add('# Sink first: the default Console sink emits via Write-Host, which PDQ')
        $g.Add('# cannot capture, and -Version exists precisely to be readable here.')
        $g.Add('Set-OutputSink -Sink Pdq -LogDirectory $LogPath')
        $g.Add('')
        $g.Add('if ($Version) {')
        $g.Add("    Write-ToolOutput ('NMM PDQ tool: {0}' -f `$script:PdqToolId) -Level Info")
        $g.Add("    Write-ToolOutput ('Toolkit v{0}' -f `$script:ToolkitVersion) -Level Info")
        $g.Add("    Write-ToolOutput ('Commit: {0}' -f `$script:ToolkitCommit) -Level Info")
        $g.Add("    Write-ToolOutput ('Built: {0}' -f `$script:ToolkitBuildDate) -Level Info")
        $g.Add('    exit 0')
        $g.Add('}')
        $g.Add('')
        $g.Add('$script:IsAdmin = Test-IsAdmin')
        $g.Add('')
        $g.Add('# Resolve rather than index: with one entry, $script:RegistryData.Tools[0]')
        $g.Add('# can be a key lookup on a bare hashtable and return $null.')
        $g.Add('$tool = Resolve-NmmTool -Query $script:PdqToolId')
        $g.Add('if (-not $tool) {')
        $g.Add("    Write-ToolOutput ('Generated script is corrupt: tool {0} not in its own registry.' -f `$script:PdqToolId) -Level Error")
        $g.Add('    exit 1')
        $g.Add('}')
        $g.Add('')
        $g.Add('$status = Invoke-NmmTool -Tool $tool -Silent -Force:$Force')
        $g.Add('')
        $g.Add('switch ($status) {')
        $g.Add("    'Success' { exit 0 }")
        $g.Add("    'Failed'  { exit 1 }")
        $g.Add("    'Warning' { exit 2 }")
        $g.Add("    'Skipped' { exit 3 }")
        $g.Add("    'Refused' { exit 4 }")
        $g.Add('    default   { exit 1 }')
        $g.Add('}')

        $outFile = Join-Path $pdqDir ($tool.Id + '.ps1')
        [System.IO.File]::WriteAllText($outFile, ($g -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

        $pdqParseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($outFile, [ref]$null, [ref]$pdqParseErrors)
        if ($pdqParseErrors.Count -gt 0) {
            $pdqParseErrors | ForEach-Object { Write-Host ('{0} (line {1})' -f $_.Message, $_.Extent.StartLineNumber) -ForegroundColor Red }
            throw ("PDQ script for '{0}' has {1} parse error(s) - build failed" -f $tool.Id, $pdqParseErrors.Count)
        }

        if (-not $SkipAnalyzer) {
            $pdqFindings = Invoke-ScriptAnalyzer -Path $outFile -Severity Error
            if ($pdqFindings) {
                $pdqFindings | Format-Table RuleName, Line, Message -AutoSize | Out-String | Write-Host
                throw ("PDQ script for '{0}' has {1} analyzer error(s) - build failed" -f $tool.Id, @($pdqFindings).Count)
            }
        }

        $emitted++
    }

    Write-Host ('Emitted {0} PDQ script(s) to {1}' -f $emitted, $pdqDir) -ForegroundColor Green
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Invoke-Pester .\tests\pdq-emit.tests.ps1`

Expected: PASS, all nine tests.

If the dropped-core reference test fails, do NOT relax it - read which function name matched. Either a retained core genuinely calls into a dropped one (a real design problem to report), or the name is a substring collision, in which case report the specific name rather than weakening the regex.

- [ ] **Step 6: Confirm the emitted script is what the spec describes**

Run: `Get-Content .\dist\pdq\system-info.ps1 -TotalCount 20`

Expected: the `#Requires` line, four comment lines naming the tool, function, version, commit and source path, then the `param(` block.

Run: `(Get-Item .\dist\pdq\system-info.ps1).Length`

Expected: on the order of 30-60 KB, versus roughly 705 KB for the monolith. Record the actual figure in your report.

- [ ] **Step 7: Run the full gate**

Run: `.\build.ps1 -Pdq` then `Invoke-Pester .\tests`

Expected: build succeeds including the emitter's own gates, suite passes. 163 + 9 = **172 passing, 0 failing**.

- [ ] **Step 8: Commit**

```bash
git add build.ps1 tests/pdq-emit.tests.ps1
git commit -m "feat(build): emit standalone per-tool PDQ scripts with -Pdq

Each flagged tool gets dist\pdq\<id>.ps1 containing the seven headless
core files verbatim, a single-entry registry, the tool function, and a
generated entry point. The console menu, usage store, WPF GUI and Jira
cores are omitted: nothing under src\tools references any function they
define, and they account for 2152 of the 2770 core lines.

Invoke-NmmTool is kept rather than inlining the gates, so the silent,
disruptive and admin rules and the status resolution have exactly one
tested implementation shared with the monolith.

The output directory is wiped each run so a tool that loses its flag
leaves no stale script behind, and every emitted script goes through the
same parse and analyzer gates as the main artifact.

Off by default so the inner development loop stays fast."
```

---

### Task 4: Behavioural tests for the generated scripts

**Files:**
- Modify: `tests\pdq-emit.tests.ps1`

**Interfaces:**
- Consumes: `dist\pdq\system-info.ps1` from Task 3, and `$script:PdqDir` / `$script:RepoRoot` from that file's existing `BeforeAll`.
- Produces: nothing later tasks depend on. This is the final task.

- [ ] **Step 1: Write the failing tests**

Append this `Describe` block to `tests\pdq-emit.tests.ps1`:

```powershell
Describe 'Generated PDQ script behaviour' {
    BeforeAll {
        $script:Seed = Join-Path $script:PdqDir 'system-info.ps1'
    }

    It 'runs the tool and exits 0 with output captured from a child process' {
        # Must be a child process with redirected stdout. In-process,
        # [Console]::Out and Write-Host are indistinguishable - the Pdq sink
        # exists for its behaviour under redirection, which only exists when
        # something is actually redirecting.
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Seed
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n").Trim() | Should -Not -BeNullOrEmpty
    }

    It 'prints provenance and exits 0 with -Version' {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Seed -Version
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'NMM PDQ tool: system-info'
        ($out -join "`n") | Should -Match 'Commit: '
    }

    It 'writes a log file when -LogPath is supplied, in addition to stdout' {
        $tmp = Join-Path $env:TEMP "nmm-pdq-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $tmp | Out-Null
        try {
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Seed -LogPath $tmp
            $LASTEXITCODE | Should -Be 0
            ($out -join "`n").Trim() | Should -Not -BeNullOrEmpty
            $log = Get-ChildItem $tmp -Filter *.log | Select-Object -First 1
            $log | Should -Not -BeNullOrEmpty
            (Get-Content $log.FullName -Raw).Trim() | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'runs without the toolkit present' {
        # The point of the whole feature: copy the script somewhere with no repo
        # and no NMMTools.ps1 alongside it, and it still works.
        $tmp = Join-Path $env:TEMP "nmm-pdq-iso-$(Get-Random)"
        New-Item -ItemType Directory -Force $tmp | Out-Null
        try {
            $copy = Join-Path $tmp 'system-info.ps1'
            Copy-Item $script:Seed $copy
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $copy | Out-Null
            $LASTEXITCODE | Should -Be 0
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail, then pass**

These tests exercise code Task 3 already wrote, so run them once and expect PASS:

Run: `Invoke-Pester .\tests\pdq-emit.tests.ps1`

Expected: PASS, all thirteen tests.

If any fail, that is a real defect in Task 3's emitter, not a test problem. Do not adjust the tests to match the behaviour - report what failed and why.

To confirm these tests are not vacuous, temporarily change the generated entry point's `Set-OutputSink -Sink Pdq -LogDirectory $LogPath` line in `build.ps1` to `Set-OutputSink -Sink Silent -LogDirectory $LogPath`, rebuild with `.\build.ps1 -Pdq -SkipAnalyzer`, and re-run. The first and third tests must fail on empty stdout. Revert the change and rebuild before continuing. Report both outputs.

- [ ] **Step 3: Run the full gate**

Run: `.\build.ps1 -Pdq` then `Invoke-Pester .\tests`

Expected: build succeeds, suite passes. 172 + 4 = **176 passing, 0 failing**.

- [ ] **Step 4: Commit**

```bash
git add tests/pdq-emit.tests.ps1
git commit -m "test(pdq): verify generated scripts run standalone under PDQ conditions

Exercises the seed script in a child process with redirected stdout,
which is the only way to prove the Pdq sink reaches PDQ's log - in
process, [Console]::Out and Write-Host are indistinguishable.

Also covers -Version, -LogPath writing a file alongside stdout, and the
central claim of the feature: the script copied to an empty directory
with no repo and no NMMTools.ps1 still runs and exits 0."
```

---

## Declared coverage gaps

Stated explicitly so they are not mistaken for oversights:

- **Exit codes 1 through 4 are not covered end to end.** Only exit 0 is exercised, via the `system-info` seed. Producing a real `Failed`, `Warning`, `Skipped` or `Refused` from a generated script would require flagging a tool that fails on the test machine, or running the suite non-elevated against an admin-gated tool - both make the suite depend on host state. The status-to-exit-code mapping is a literal `switch` over values that `tests\dispatch.tests.ps1` already covers at the `Invoke-NmmTool` level.
- **Only the seed tool's generated script is behaviourally tested.** The structural tests in Task 3 apply to every emitted script; the behavioural tests in Task 4 run one. Since every generated script shares a byte-identical core and entry point, differing only in provenance, registry entry and tool body, one behavioural run plus per-script structural gates is the intended coverage.
- **PDQ Deploy package configuration is out of scope.** This plan produces `.ps1` files. Creating packages around them, including setting additional success codes for tools that legitimately return 2 or 3, is a manual step in PDQ.

## Out of scope

Carried from the spec's non-goals so an implementer does not helpfully add them:

- No fleet-wide inventory or auditing mechanism.
- No change to the artifact's `0`/`1` exit-code contract. Only generated scripts use the five-code contract.
- No change to any tool's behaviour. Every tool function is emitted verbatim.
- No dependency analysis or per-tool core slicing.
- No choice of which tools to deploy beyond the single `system-info` seed.
