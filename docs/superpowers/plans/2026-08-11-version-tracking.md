# Version Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake build provenance (version, git commit, dirty flag, build date) into the
artifact as runtime-readable variables, and add a `-Version` switch that prints them.

**Architecture:** `build.ps1` captures the commit hash and working-tree state once, reuses
them for both the header comment and a new `#region provenance` block injected between the
param block and the core region. `src\entry\99-main.ps1` gains a `-Version` branch that
prints those variables and exits 0 before any other entry-point logic runs.

**Tech Stack:** PowerShell 5.1, Pester 5.x, PSScriptAnalyzer, git CLI.

**Spec:** `docs\superpowers\specs\2026-08-04-version-tracking-design.md` (Approved).

**Downstream:** `docs\superpowers\specs\2026-08-11-pdq-per-tool-packaging-design.md` declares
this a hard prerequisite and reuses the same provenance capture in generated PDQ scripts.

## Global Constraints

- PowerShell 5.1 is the target. No PS7-only syntax: no ternary `?:`, no `??`, no `?.`.
- Never `(if ($x) { 'a' } else { 'b' })` as an inline argument. Always the subexpression
  form `$(if ($x) { 'a' } else { 'b' })`. The parser accepts the former and it throws
  `CommandNotFoundException` at runtime; `tests\ps51-runtime.tests.ps1` will catch it.
- ASCII only in all source files. No em dashes, smart quotes, or box-drawing characters.
- UTF-8 without BOM.
- Inside double-quoted strings, a literal `$` must be backtick-escaped. Never use `${}`.
- Tools and core use `Write-ToolOutput`, never `Write-Host`. `build.ps1` is exempt: it is a
  developer-facing build script, not shipped code, and already uses `Write-Host` throughout.
- Every code path in a tool ends in exactly one `Complete-ToolRun`. This plan adds no tools.
- Full gate before any commit is considered done: `.\build.ps1` then `Invoke-Pester .\tests`.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `build.ps1` | Modify (4 sites) | Capture provenance once; emit it into the header, into a runtime block, and into the build success message |
| `src\entry\00-param.ps1` | Modify | Declare `[switch]$Version` on the artifact |
| `src\entry\99-main.ps1` | Modify | Print provenance and exit 0 when `-Version` is passed |
| `tests\artifact.tests.ps1` | Modify | Assert the provenance block is present and correctly shaped; assert `-Version` works end to end in a child process |

Two tasks. Task 1 makes the provenance real and asserted but unread; Task 2 exposes it.
A reviewer could reasonably accept Task 1 and reject Task 2's flag ordering, so they split.

---

### Task 1: Bake build provenance into the artifact

**Files:**
- Modify: `build.ps1:6-10` (capture), `build.ps1:14` (header), `build.ps1:18` (inject block), `build.ps1:67` (success message)
- Test: `tests\artifact.tests.ps1`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: three script-scope variables inside the built artifact, read by Task 2 -
  `$script:ToolkitVersion` (string, e.g. `'9.1.0'`),
  `$script:ToolkitCommit` (string, e.g. `'a1b2c3d'`, `'a1b2c3d-dirty'`, or `'unknown'`),
  `$script:ToolkitBuildDate` (string, format `yyyy-MM-dd HH:mm`).

- [ ] **Step 1: Write the failing test**

Add these two `It` blocks to `tests\artifact.tests.ps1`, inside the existing
`Describe 'Built artifact'` block, immediately after the `'parses with zero errors under
the PS 5.1 parser'` test.

Note the regex strings deliberately match on `ToolkitVersion` without the `$script:`
prefix. A `$` inside a double-quoted PowerShell string starts a variable reference, and
escaping it here buys nothing the match needs.

```powershell
    It 'bakes build provenance into the artifact as runtime variables' {
        $content = Get-Content $script:Artifact -Raw
        $content | Should -Match "ToolkitVersion\s*=\s*'\d+\.\d+\.\d+'"
        $content | Should -Match "ToolkitCommit\s*=\s*'([0-9a-f]{7,}(-dirty)?|unknown)'"
        $content | Should -Match "ToolkitBuildDate\s*=\s*'\d{4}-\d{2}-\d{2} \d{2}:\d{2}'"
    }

    It 'keeps the param block ahead of the provenance block' {
        # The param block must remain the first statement in the artifact or the
        # whole file fails to run. Injecting the provenance block above it would
        # parse fine and break every invocation.
        $content = Get-Content $script:Artifact -Raw
        $paramIndex      = $content.IndexOf('param(')
        $provenanceIndex = $content.IndexOf('ToolkitVersion')
        $paramIndex      | Should -BeGreaterThan -1
        $provenanceIndex | Should -BeGreaterThan $paramIndex
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester .\tests\artifact.tests.ps1`

Expected: FAIL. Both new tests fail because nothing writes `ToolkitVersion` into the
artifact yet. The first fails on the `-Match` assertion; the second fails because
`IndexOf` returns `-1`, so `$provenanceIndex` is not greater than `$paramIndex`.
All pre-existing tests in the file must still pass.

- [ ] **Step 3: Capture provenance in build.ps1**

Replace `build.ps1` lines 6-10 (from `$ErrorActionPreference = 'Stop'` through
`$artifact = Join-Path $dist 'NMMTools.ps1'`) with:

```powershell
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$artifact = Join-Path $dist 'NMMTools.ps1'

# Build provenance. Captured once and reused for the header comment, the runtime
# block, and the success message, so the three cannot drift apart.
#
# $ErrorActionPreference is dropped to 'Continue' for the probe. git writes to
# stderr on any failure (not a repo, no git installed), and under 'Stop' a
# captured stderr stream can surface as a terminating error and take down the
# whole build over a cosmetic version string.
$buildDate = Get-Date
$commit    = 'unknown'
$prevEap   = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $rev = git -C $root rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $rev) {
        $commit = ([string]$rev).Trim()
        $dirty = git -C $root status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and $dirty) { $commit = $commit + '-dirty' }
    }
} catch {
    # git missing entirely raises CommandNotFoundException, which is terminating
    # regardless of preference. An unknown commit is not a build failure.
    $commit = 'unknown'
} finally {
    $ErrorActionPreference = $prevEap
}
```

- [ ] **Step 4: Put the commit in the header comment**

Replace `build.ps1` line 14 (now shifted down) - the `$parts.Add(('# NMM System Toolkit
v{0} | built ...` line - with:

```powershell
$parts.Add(('# NMM System Toolkit v{0} ({1}) | built {2:yyyy-MM-dd HH:mm} | GENERATED by build.ps1 - DO NOT EDIT' -f $Version, $commit, $buildDate))
```

Note this also switches the timestamp from an inline `(Get-Date)` to the captured
`$buildDate`, which is the point: the header and the runtime block now render the same
instant.

- [ ] **Step 5: Inject the runtime provenance block**

In `build.ps1`, immediately after the param-block line:

```powershell
# 1. Param block must be the first statement in the artifact
$parts.Add((Get-Content (Join-Path $root 'src\entry\00-param.ps1') -Raw -Encoding UTF8))
```

add:

```powershell
# 1b. Provenance as real variables, readable at runtime by -Version. Must come
# after the param block, which has to remain the first statement in the file.
$parts.Add('#region provenance')
$parts.Add(("`$script:ToolkitVersion   = '{0}'" -f $Version))
$parts.Add(("`$script:ToolkitCommit    = '{0}'" -f $commit))
$parts.Add(("`$script:ToolkitBuildDate = '{0:yyyy-MM-dd HH:mm}'" -f $buildDate))
$parts.Add('#endregion')
```

The backticks before each `$script:` are required. Without them PowerShell expands
`$script:ToolkitVersion` at build time, which is `$null`, and the artifact gets a line
reading `   = '9.1.0'` - a parse error.

- [ ] **Step 6: Show the commit in the build success message**

Replace the final `Write-Host` line of `build.ps1` with:

```powershell
Write-Host ('Built {0} ({1} KB, v{2} {3})' -f $artifact, $sizeKB, $Version, $commit) -ForegroundColor Green
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `Invoke-Pester .\tests\artifact.tests.ps1`

Expected: PASS, all tests in the file including the two new ones.

- [ ] **Step 8: Verify the dirty flag by hand**

The tests accept either a clean or dirty hash, so they cannot prove the suffix logic
works. Check it directly.

Run: `.\build.ps1`

The working tree has uncommitted changes at this point (`build.ps1` itself), so expect
the success line to end with a `-dirty` suffix, e.g. `Built ... (705 KB, v9.1.0 13fa809-dirty)`.

Then confirm the artifact agrees:

Run: `Select-String -Path .\dist\NMMTools.ps1 -Pattern 'ToolkitCommit'`

Expected: one line, the same hash with the `-dirty` suffix.

Be aware that `git status --porcelain` reports untracked files too, so an untracked
directory in the repo root marks every build dirty. At the time of writing, `tools\`
(the environment probe) is untracked and will do exactly that. This is correct
behaviour, not a bug: `build.ps1` globs `src\**`, so an untracked file genuinely can
change the artifact, and "this build does not correspond to any committed state" is the
honest answer. Do not add `--untracked-files=no` to silence it. Step 11 works around it
for the clean-tree check only.

- [ ] **Step 9: Run the full gate**

Run: `.\build.ps1` then `Invoke-Pester .\tests`

Expected: build succeeds with both gates, and the full suite passes. Baseline before
this plan was 151 passed / 0 failed; expect 153 / 0 now.

- [ ] **Step 10: Commit**

```bash
git add build.ps1 tests/artifact.tests.ps1
git commit -m "feat(build): bake version, commit hash, and build date into the artifact

Captures git rev-parse --short HEAD and a working-tree dirty flag at
build time and injects them as script variables after the param block,
so a deployed NMMTools.ps1 can be identified without diffing contents.
The header comment, the runtime block, and the build success message all
render from one captured timestamp and one captured hash, so they cannot
drift apart.

git is probed with \$ErrorActionPreference dropped to Continue: git
writes to stderr whenever it fails, and under Stop that can surface as a
terminating error and fail the build over a cosmetic string. A missing
git or a non-repo checkout yields 'unknown' rather than a build failure."
```

- [ ] **Step 11: Verify the clean-tree case**

The spec requires confirming that a clean tree produces a hash with no suffix. The
previous step only proved the dirty path. The tree is now clean of tracked changes, but
untracked files still count, so stash them first.

Run:

```powershell
git stash push --include-untracked -m "version-tracking clean-tree check"
git status --porcelain
```

Expected: `git status --porcelain` prints nothing.

Run: `.\build.ps1`

Expected: the success line ends with a bare hash and no `-dirty` suffix.

Restore the working tree:

```powershell
git stash pop
```

Expected: `tools\` is untracked again and `git status --porcelain` is non-empty.

If `git stash pop` reports a conflict, stop and report it rather than resolving it -
nothing in this task should have touched a stashed file.

---

### Task 2: Add the -Version switch

**Files:**
- Modify: `src\entry\00-param.ps1`
- Modify: `src\entry\99-main.ps1:1` (insert before `$script:IsAdmin = Test-IsAdmin`)
- Test: `tests\artifact.tests.ps1`

**Interfaces:**
- Consumes: `$script:ToolkitVersion`, `$script:ToolkitCommit`, `$script:ToolkitBuildDate`
  from Task 1 - all strings, injected by `build.ps1` into the artifact.
- Produces: a `-Version` switch on the built artifact that writes three lines to stdout
  and exits 0. The downstream PDQ packaging spec mirrors this branch in generated scripts.

- [ ] **Step 1: Confirm child-process output capture before asserting on it**

`Write-ToolOutput`'s Console sink emits through `Write-Host` (`src\core\02-output.ps1:51`),
and the test in Step 2 asserts on captured stdout. Verify capture works in this exact
invocation shape before writing a test that depends on it.

Run:

```powershell
& powershell.exe -NoProfile -Command "Write-Host 'capture-probe'"
```

Expected: `capture-probe` is returned into the PowerShell pipeline, not just painted on
the console. If it is NOT captured, stop and report it: that is a real finding, it means
`Write-Host` output is invisible to any parent process on this machine, and it would
retroactively justify the separate `Pdq` sink specified in the PDQ packaging design.
Do not work around it by weakening the assertion.

- [ ] **Step 2: Write the failing test**

Add this `It` block to `tests\artifact.tests.ps1`, inside `Describe 'Built artifact'`,
immediately after the `'lists tools when run with -ListTools'` test:

```powershell
    It 'prints provenance and exits 0 with -Version' {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact -Version
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'NMM System Toolkit v\d+\.\d+\.\d+'
        ($out -join "`n") | Should -Match 'Commit: '
        ($out -join "`n") | Should -Match 'Built: '
    }
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `Invoke-Pester .\tests\artifact.tests.ps1`

Expected: FAIL. The artifact has no `-Version` parameter, so `powershell.exe -File` exits
non-zero with a parameter-binding error and captures no matching output.

- [ ] **Step 4: Declare the parameter**

In `src\entry\00-param.ps1`, add `[switch]$Version` to the param block. The full file
becomes:

```powershell
[CmdletBinding()]
param(
    [string]$Tool,        # run one tool by slug or legacy number, then exit
    [switch]$Silent,      # no prompts; Read-ToolChoice returns declared defaults
    [switch]$Force,       # allow Disruptive tools under -Silent
    [switch]$ListTools,   # print the tool inventory and exit
    [switch]$Version,     # print build provenance and exit
    [string]$LogPath,     # directory for the session log file
    [ValidateSet('Auto','Console','GUI')][string]$Mode = 'GUI'
)
```

- [ ] **Step 5: Handle -Version first in the entry point**

In `src\entry\99-main.ps1`, insert this at the very top of the file, above the existing
`# ---- Entry point ----` comment and `$script:IsAdmin = Test-IsAdmin` line:

```powershell
# -Version is handled before anything else - it is the lowest-risk path and must
# not depend on elevation detection, sink setup, or tool resolution succeeding.
if ($Version) {
    Write-ToolOutput ('NMM System Toolkit v{0}' -f $script:ToolkitVersion) -Level Info
    Write-ToolOutput ('Commit: {0}' -f $script:ToolkitCommit) -Level Info
    Write-ToolOutput ('Built: {0}' -f $script:ToolkitBuildDate) -Level Info
    exit 0
}
```

Do not add precedence or warning logic for combining `-Version` with `-Tool` or
`-ListTools`. Per the spec's non-goals, `-Version` simply wins and exits first.

- [ ] **Step 6: Run the test to verify it passes**

Run: `Invoke-Pester .\tests\artifact.tests.ps1`

Expected: PASS, all tests in the file.

- [ ] **Step 7: Verify by hand**

Run: `.\dist\NMMTools.ps1 -Version`

Expected: three lines - toolkit version, commit hash, build date - and a prompt return
with no menu launched and no elevation prompt.

- [ ] **Step 8: Run the full gate**

Run: `.\build.ps1` then `Invoke-Pester .\tests`

Expected: build succeeds with both gates, full suite passes. Expect 154 / 0.

- [ ] **Step 9: Commit**

```bash
git add src/entry/00-param.ps1 src/entry/99-main.ps1 tests/artifact.tests.ps1
git commit -m "feat(entry): add -Version switch to print build provenance

Prints the version, commit hash, and build date baked in by build.ps1,
then exits 0. Handled before mode selection, -ListTools, and -Tool: it
is the lowest-risk path and should not depend on elevation detection or
tool resolution succeeding first.

Uses Write-ToolOutput rather than Write-Host so the banner is captured
to the session log when -LogPath is supplied, consistent with every
other output path in the toolkit."
```

---

## Out of scope

Carried verbatim from the spec's non-goals, restated here so an implementer does not
helpfully add them:

- No live comparison against GitHub or any "latest version" source.
- No fleet-wide query mechanism. A PDQ Inventory audit can shell out to
  `NMMTools.ps1 -Version` later; building that audit is not part of this work.
- No change to how the release version number is chosen. `build.ps1 -Version` stays a
  manually set label with a matching git tag; only the commit hash and dirty flag are new.
- No warning or precedence logic for `-Version` combined with other switches.
