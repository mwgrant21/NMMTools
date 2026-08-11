# PDQ Per-Tool Packaging - Design Spec
**Date:** 2026-08-11
**Status:** Approved
**Scope:** A second build target that emits one self-contained, PDQ-deployable `.ps1`
per opted-in registry tool, plus the shared-core changes that make those scripts
behave correctly under PDQ Deploy. No existing tool's behavior changes.
**Depends on:** `2026-08-04-version-tracking-design.md` (must be implemented first).

---

## Background

The artifact already supports running a single tool headlessly:
`NMMTools.ps1 -Tool wmi-repair -Silent -Mode Console`. That is enough to deploy a tool
via PDQ, but it is the wrong unit of deployment for three reasons:

1. **Package hygiene.** Every PDQ Deploy package would point at the same 658 KB file.
   Nothing in PDQ tells you what a package actually does, or when the logic behind it
   last changed.
2. **Blast radius.** A technician deploying a print-spooler fix pushes a file that also
   contains 114 other tools, 26 of them `Disruptive`. The review surface for a one-line
   change is the whole toolkit.
3. **Standalone handoff.** There is no artifact you can hand to another person or team
   that does one job with no toolkit, no registry, and no dependencies.

Size is explicitly not a driver. The 658 KB is not a transfer problem; it is a
provenance and review problem.

A supporting observation from the field: an environment probe run on 2026-08-11
(`tools\Get-NmmEnvironmentProbe.ps1`) found the deployed `Desktop\NMMTools.ps1` on
MATTHEWGR_L3 was built 2026-06-29, six weeks stale, and nothing on the machine revealed
that. Per-tool packages multiply that problem across dozens of independently deployed
artifacts, which is why build provenance is a hard prerequisite rather than a nice-to-have.

---

## Prerequisite: version tracking

`docs\superpowers\specs\2026-08-04-version-tracking-design.md` is approved but
unimplemented. It must ship first. It provides the `git rev-parse --short HEAD` capture,
the `-dirty` working-tree suffix, and the single build-timestamp variable that this
spec's generated headers reuse. Implementing it second would mean writing the same git
capture twice, or refactoring the emitter immediately after building it.

---

## Architecture

The chosen approach is a **fixed headless core**: every generated script contains the
same seven core files verbatim, and differs only in its provenance header, its
single-entry registry, and its tool function.

Two approaches were considered and rejected:

- **Per-tool dependency slicing** (compute each tool's core needs from its AST). Saves
  roughly 15 KB per script on a project where size is not a driver, costs a dependency
  analyzer to build and test, and makes every generated script structurally different so
  that reviewing one tells you nothing about the next.
- **Full flattening** (no core at all; inline equivalents of `Write-ToolOutput` and the
  gates). Most readable to an outsider, but it forks the contract. `New-ToolRun` and
  `Complete-ToolRun` produce the status that drives the exit code, so flattening means
  reimplementing status tracking, and a tool's PDQ behavior could then drift from its
  toolkit behavior. That drift would surface only on the fleet.

### Why a fixed core is safe

Verified 2026-08-11 against the current tree: **no file under `src\tools\` references any
function defined in `05-ui-console.ps1`, `06-usage.ps1`, `09-ui-wpf.ps1`, or
`10-jira.ps1`.** The only hits in the retained cores are at `02-output.ps1:58` and
`02-output.ps1:115`, and both are comment text explaining runspace affinity, not calls.
The live GUI paths are guarded behind `$script:OutputSink -eq 'GUI'`.

This holds because tools were written against the output interface (`Write-ToolOutput`,
`Read-ToolChoice`) rather than against `Write-Host`/`Read-Host`. The discipline that
made PDQ log capture work is the same discipline that makes the GUI detachable.

### Core partition

| Included (headless) | Lines | Excluded | Lines |
|---|---|---|---|
| `01-bootstrap.ps1` | 32 | `05-ui-console.ps1` | 267 |
| `02-output.ps1` | 157 | `06-usage.ps1` | 86 |
| `03-results.ps1` | 87 | `09-ui-wpf.ps1` | 1554 |
| `04-dispatch.ps1` | 57 | `10-jira.ps1` | 245 |
| `07-repair-helpers.ps1` | 108 | | |
| `08-browser-helpers.ps1` | 87 | | |
| `11-diagnostic-bundle-helpers.ps1` | 34 | | |
| **Total** | **562** | **Total** | **2152** |

The three helper cores (07, 08, 11) are included unconditionally even though only some
tools use them. They total 229 lines; conditionally including them would reintroduce
dependency analysis for no meaningful benefit.

`04-dispatch.ps1` is retained rather than inlined. `Invoke-NmmTool` holds the silent,
disruptive, and admin gates plus status resolution; keeping it means those rules have
exactly one implementation, already covered by `tests\dispatch.tests.ps1`.

---

## Source changes

### 1. New output sink: `Pdq`

`src\core\02-output.ps1:51` emits console output with `Write-Host`. Under PDQ Deploy that
produces no captured output, which would make every generated package close to useless.

`Set-OutputSink`'s `ValidateSet` gains `'Pdq'`, and `Write-ToolOutput` gains a branch
alongside the existing `Console`/`GUI`/`Capture` branches:

```powershell
} elseif ($script:OutputSink -eq 'Pdq') {
    [Console]::Out.WriteLine(('[{0,-7}] {1}' -f $Level, $Message))
}
```

`[Console]::Out.WriteLine` is required here; both obvious alternatives fail:

- `Write-Host` writes to the host UI. With no host, there is nothing to capture.
- `Write-Output` writes to the success stream. `Invoke-NmmTool` ends with
  `return $run.Status`, so every log line would ride back as part of that return value
  and the status-to-exit-code mapping would receive an array instead of a string. This
  is the "Write-Log via Write-Output poisons value-returning functions" class from the
  codex.

`[Console]::Out` is process stdout directly: PDQ captures it, and it never touches the
pipeline.

The existing `$script:LogFilePath` branch is unchanged, so `-LogPath` still produces a
file log in addition to stdout.

### 2. New registry field: `PdqDeployable`

Added to all 115 entries in `src\registry\tools.psd1`, positioned immediately after
`SilentCapable`:

```powershell
    RequiresAdmin = $false
    SilentCapable = $true
    PdqDeployable = $false
    Risk          = 'ReadOnly'
```

This changes the registry field contract. `CLAUDE.md`'s "Adding a tool" registry block
and `tests\registry.tests.ps1` are both updated to require the field, so a new tool
cannot be added without an explicit decision about whether it ships to PDQ.

The implementation adds the field as `$false` on all 115 entries and flips exactly one
to `$true`: `system-info` (ReadOnly, no admin, silent-capable), which serves as the seed
for the child-process smoke test. Choosing the operational set of deployable tools is a
data change to `tools.psd1`, made separately by the user; it is not part of this
implementation.

### 3. New build target: `build.ps1 -Pdq`

A `[switch]$Pdq` parameter, off by default so the inner development loop stays fast.
`/nmm-ship` passes it as part of the sanctioned release path.

When set, after the main artifact is built and gated, the emitter:

1. Deletes and recreates `dist\pdq\`, so a tool that loses its flag leaves no stale
   script behind for someone to deploy.
2. For each entry with `PdqDeployable = $true`, writes `dist\pdq\<tool-id>.ps1`.
3. Runs the same two gates over each emitted script that the artifact already gets:
   `[Parser]::ParseFile` with zero errors, and `Invoke-ScriptAnalyzer -Severity Error`
   with no findings. A failure throws and names the tool.
4. Throws if a flagged entry's `Function` does not resolve to a file under `src\tools\`.

Files are written with
`[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))`
to guarantee UTF-8 without BOM.

`dist\` is gitignored, so generated scripts are release artifacts, not committed source.

---

## Generated script anatomy

```powershell
#Requires -Version 5.1
# NMM PDQ tool: system-info -> Get-SystemInformation
# NMM System Toolkit v9.1.0 (a1b2c3d) | built 2026-08-11 10:32
# GENERATED by build.ps1 -Pdq - DO NOT EDIT
# Source: NMMToolkit repo, src\tools\diagnostics\Get-SystemInformation.ps1

[CmdletBinding()]
param(
    [switch]$Force,      # required for Disruptive tools
    [string]$LogPath,    # optional file log in addition to stdout
    [switch]$Version     # print provenance and exit 0
)

$script:ToolkitVersion   = '9.1.0'
$script:ToolkitCommit    = 'a1b2c3d'
$script:ToolkitBuildDate = '2026-08-11 10:32'
$script:PdqToolId        = 'system-info'

#region core        (the seven headless files, verbatim, in numeric order)
#region registry    $script:RegistryData = @{ Tools = @( <the single entry> ) }
#region tool        function Get-SystemInformation { ... }   (verbatim)

# ---- Entry point ----
Set-OutputSink -Sink Pdq -LogDirectory $LogPath

if ($Version) {
    Write-ToolOutput ('NMM PDQ tool: {0}' -f $script:PdqToolId) -Level Info
    Write-ToolOutput ('Toolkit v{0}' -f $script:ToolkitVersion) -Level Info
    Write-ToolOutput ('Commit: {0}' -f $script:ToolkitCommit) -Level Info
    Write-ToolOutput ('Built: {0}' -f $script:ToolkitBuildDate) -Level Info
    exit 0
}

$script:IsAdmin = Test-IsAdmin

$tool = Resolve-NmmTool -Query $script:PdqToolId
if (-not $tool) {
    Write-ToolOutput ('Generated script is corrupt: tool {0} not in its own registry.' -f $script:PdqToolId) -Level Error
    exit 1
}

$status = Invoke-NmmTool -Tool $tool -Silent -Force:$Force

switch ($status) {
    'Success' { exit 0 }
    'Failed'  { exit 1 }
    'Warning' { exit 2 }
    'Skipped' { exit 3 }
    'Refused' { exit 4 }
    default   { exit 1 }   # 'Unknown' - dispatcher found no completed run
}
```

Two details in the entry point are load-bearing:

**`Set-OutputSink` runs before the `-Version` check**, not after. The version-tracking
spec puts `-Version` first in the monolith because it is the lowest-risk path, but that
reasoning does not transfer here: the default sink is `Console`, which emits via
`Write-Host`, so a `-Version` call under PDQ would produce no captured output. Since the
whole point of baking provenance in is answering "what is actually deployed on this
box", the provenance path in particular must reach PDQ's log. `Set-OutputSink` is a
straight-line assignment with no dependencies, so putting it first costs no risk.

**The tool is resolved through `Resolve-NmmTool`, not indexed out of the registry.**
Writing `$script:RegistryData.Tools[0]` would invite the array-unroll trap from the
codex: with exactly one entry, if `Tools` ever reaches the indexing expression as a bare
`hashtable` rather than a one-element array, `[0]` is a key lookup that returns `$null`
rather than the entry, and the script would fail with a confusing dispatcher error.
`Resolve-NmmTool` goes through `Get-NmmTools`, which already wraps in `@()`, and returns
either the entry or `$null` explicitly. Reusing it also keeps the resolution path
identical to the monolith's.

### Deliberate deviations from the standing PDQ rules

Three choices here contradict defaults in `~\.claude\rules\` or the codex. Each is
deliberate and load-bearing:

1. **No `$ErrorActionPreference = 'Stop'`.** The toolkit never sets it; only `build.ps1`
   does, for the build itself. All 115 tools run today under the default `Continue`,
   relying on their own `try`/`catch` plus explicit `-ErrorAction Stop` where it matters.
   Setting `Stop` in generated scripts only would mean the same tool takes a different
   path in PDQ than in the toolkit: a call that quietly returned `$null` in the menu
   becomes a terminating error on 200 endpoints, and only the fleet finds out.
   Behavioral parity with the toolkit wins. Converging both on `Stop` is a legitimate
   future change, but it is a behavior change across all 115 tools and needs its own
   spec and testing pass.

2. **No `#Requires -RunAsAdministrator`.** The dispatcher's admin gate returns `Refused`,
   which maps to exit 4 and tells you in the PDQ results grid why the tool did not run.
   `#Requires` would hard-fail with a generic error instead. Under PDQ this is moot
   (SYSTEM is admin); it matters for the standalone-handoff case.

3. **`Invoke-ElevationCheck` is never called.** It calls `Start-Process -Verb RunAs`,
   which raises a UAC prompt and would hang an unattended deployment until it timed out.
   `01-bootstrap.ps1`'s header already documents this, and the monolith's `-Tool` path
   skips it too; the generated entry inherits the behavior by construction.

### Parameter choices

- **`-Silent` is baked in, not exposed.** There is no interactive host. Every tool is
  `SilentCapable = $true`, so declared defaults apply.
- **`-Force` stays a parameter and is not baked out.** A `Disruptive` tool marked
  `PdqDeployable` still refuses unless the PDQ step passes `-Force`. The speed bump
  survives packaging.
- **`-Tool`, `-ListTools`, and `-Mode` are absent.** A per-tool script has one tool and
  no menu.

---

## Exit codes

| Code | Status | Meaning |
|---|---|---|
| 0 | Success | Tool ran and completed cleanly |
| 1 | Failed | Tool ran and failed, or the dispatcher caught an unhandled exception, or status was `Unknown` |
| 2 | Warning | Tool ran and completed with findings |
| 3 | Skipped | Tool determined there was nothing to do |
| 4 | Refused | A gate blocked the run (not silent-capable, disruptive without `-Force`, or admin required) |

This deliberately diverges from the artifact's `0 = Success/Warning/Skipped, 1 =
Failed/Refused` contract. In a fleet rollout the distinction between "fixed it",
"already clean", and "found problems" is the most useful signal available, and
collapsing it to red/green throws it away.

PDQ Deploy treats any non-zero code as a failed step by default. Packages for tools that
can legitimately return 2 or 3 must configure those as additional success codes. This is
a per-package setting and is documented rather than worked around, because suppressing
it in the script would recreate the collapse this contract exists to avoid.

---

## Testing

One new file, `tests\pdq-emit.tests.ps1`, plus two extensions to existing suites.

| Test | Guards against |
|---|---|
| Every registry entry has a `[bool] PdqDeployable` | A tool added without an explicit PDQ decision |
| Every flagged tool emits exactly one script; unflagged tools emit none | Emitter selection logic |
| Each emitted script parses with zero errors | Same gate the artifact gets |
| Each emitted script passes `Invoke-ScriptAnalyzer -Severity Error` | Same gate the artifact gets |
| No emitted script references a function defined in `05`, `06`, `09`, or `10` | A tool later gaining a UI, usage, or Jira dependency and silently breaking every PDQ package |
| Emitted scripts are UTF-8 without BOM and ASCII-only | The encoding rules in `CLAUDE.md` |
| `tests\ps51-runtime.tests.ps1` extended to scan `dist\pdq\` | The keyword-as-command class reaching generated output |
| Child-process smoke test (below) | The `Pdq` sink failing to reach redirected stdout |
| Child-process `-Version` returns 0 with the commit hash on captured stdout | Provenance being unreadable in exactly the unattended context it exists for |

### The child-process smoke test

Run the seed script in a real child process with redirected stdout, following the
pattern already used in `tests\artifact.tests.ps1` for `-ListTools` and `-Tool`:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File dist\pdq\system-info.ps1
```

Assert `$LASTEXITCODE -eq 0` and that captured stdout is non-empty.

This must be a child process. Run in-process, `[Console]::Out.WriteLine` and
`Write-Host` are indistinguishable: both appear in the console and both look correct.
The entire reason the `Pdq` sink exists is behavior under redirection, which only exists
when something is actually redirecting.

### Regression check for the sink

Before implementing the `Pdq` sink, confirm the smoke test fails against a build that
uses the `Console` sink instead. A test that cannot fail is not a test.

### Full gate

`.\build.ps1 -Pdq` then `Invoke-Pester .\tests`, as with every prior change.

---

## Non-goals

- **No fleet-wide inventory or auditing.** Generated scripts carry provenance and
  support `-Version`, which makes a future PDQ Inventory audit possible, but building
  that audit is out of scope, consistent with the version-tracking spec's own non-goals.
- **No change to the artifact's exit-code contract.** `NMMTools.ps1` keeps `0/1`. Only
  the generated per-tool scripts use the five-code contract.
- **No change to any tool's behavior**, in the toolkit or in PDQ. Every tool function is
  emitted verbatim.
- **No dependency analysis or per-tool core slicing**, now or later, unless artifact size
  becomes an actual constraint.
- **No PDQ package creation or automation.** This spec produces `.ps1` files. Building
  the PDQ Deploy packages around them is a manual step.
- **No choice of which tools to deploy.** The implementation adds the field defaulted to
  `$false` and seeds one tool for testing. Selecting the operational set is a separate
  data change.
