# NMMToolkit Claude Code Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add project-level Claude Code tooling to NMMToolkit: a CLAUDE.md context file, an nmm-tool-builder agent, and nmm-review / nmm-ship skills, per the approved spec `docs\superpowers\specs\2026-07-06-claude-tooling-design.md`.

**Architecture:** Four standalone markdown artifacts inside the NMMToolkit repo. CLAUDE.md carries shared conventions; the agent and skills reference it rather than repeating it. The nmm-review checklist lives once, in the nmm-review skill; the builder agent reads that file. No code changes to the toolkit itself.

**Tech Stack:** Claude Code project agents/skills (markdown + YAML frontmatter), PowerShell 5.1, Pester >= 5.0, git.

## Global Constraints

- All files ASCII-only (repo convention: non-ASCII breaks re-encoding; see `~\.claude\rules\codex.md`).
- All files UTF-8 without BOM.
- Registry entry fields, exactly these 10, in this order: `Id, LegacyId, Name, Category, Function, Description, RequiresAdmin, SilentCapable, Risk, Tags`.
- Risk values: `ReadOnly | Modifies | Disruptive`. Categories (capitalized, registry): `Browser, Cloud, Diagnostics, Laptop, QuickFix, Repair, Security, User`. Directories (lowercase): `browser, cloud, diagnostics, laptop, quickfix, repair, security, user`.
- Next free LegacyId is `110` (Q1-Q9 also exist for quickfix; new tools use numbers).
- Working directory for all commands: `C:\Users\IT\Desktop\NMMToolkit` unless stated.
- Commit after every task, in the NMMToolkit repo.
- IMPORTANT: project agents/skills only auto-register for Claude Code sessions started inside NMMToolkit. Verification from another directory must read/dispatch the doc contents explicitly (Task 5 does this).

---

### Task 1: Project CLAUDE.md

**Files:**
- Create: `C:\Users\IT\Desktop\NMMToolkit\CLAUDE.md`

**Interfaces:**
- Produces: shared conventions referenced by Tasks 2-4 (they say "see CLAUDE.md" instead of repeating the contract).

- [ ] **Step 1: Write the file**

Write `C:\Users\IT\Desktop\NMMToolkit\CLAUDE.md` with exactly this content:

````markdown
# NMMToolkit - Claude Code Project Guide

Modular source for the NMM System Toolkit (105+ tools). Develop in `src\`,
ship the concatenated artifact `dist\NMMTools.ps1`. PowerShell 5.1 target.

## Commands

    .\build.ps1                  # concatenate + parse gate + analyzer gate
    .\build.ps1 -SkipAnalyzer    # faster inner loop
    Invoke-Pester .\tests        # full suite (Pester >= 5.0)

Exit code contract for the artifact: 0 = Success/Warning/Skipped,
1 = Failed/Refused/unknown tool.

## Layout

- `src\entry\` - `00-param.ps1` (artifact param block, first) and
  `99-main.ps1` (entry point, last)
- `src\core\` - numeric prefix = build concatenation order (01-bootstrap ..
  10-jira). New core files continue the sequence.
- `src\registry\tools.psd1` - THE tool registry. Pure data, one entry per tool.
- `src\tools\<category>\<Verb-Noun>.ps1` - one file per tool, filename equals
  function name. Category dirs (lowercase): browser, cloud, diagnostics,
  laptop, quickfix, repair, security, user.
- `tests\` - Pester: registry consistency, template compliance, artifact
  parse/smoke, encoding checks.
- `docs\superpowers\specs\` - approved design specs. The v9 tool template is
  spec section 3 of `2026-06-12-nmm-toolkit-v9-design.md`.

## Adding a tool (the contract)

1. Create `src\tools\<category>\<Verb-Noun>.ps1`. Approved PowerShell verbs
   only. Template shape (all five elements mandatory):

```powershell
function Verb-Noun {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'tool-id'
        # work: Write-ToolOutput for ALL output (never Write-Host);
        # Read-ToolChoice -Prompt ... -Default ... -Silent:$Silent for ALL
        # prompting (never Read-Host)
        Complete-ToolRun $run -Status Success -Summary 'one line'
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
```

   Statuses: Success | Warning | Failed | Skipped | Refused. Every code path
   must end in exactly one Complete-ToolRun.

2. Add the registry entry in `src\registry\tools.psd1` - fields, exactly
   these, in this order:

```powershell
@{
    Id            = 'tool-id'            # kebab-case slug, unique
    LegacyId      = '110'                # next free number (110+); string
    Name          = 'Human Name'
    Category      = 'Security'           # capitalized; must match the dir
    Function      = 'Verb-Noun'          # must equal filename minus .ps1
    Description   = 'One line, no trailing period'
    RequiresAdmin = $false
    SilentCapable = $true                # $false only if tool cannot run headless
    Risk          = 'ReadOnly'           # ReadOnly | Modifies | Disruptive
    Tags          = @('a','b','c')       # lowercase search keywords
}
```

3. `.\build.ps1` then `Invoke-Pester .\tests` - registry tests fail if file,
   function, and registry disagree. The GUI and console menu are registry-
   driven; no wiring needed.

## Semantics

- `-Silent` refuses tools registered `SilentCapable = $false`.
- `Risk = 'Disruptive'` tools refuse `-Silent` unless `-Force` is added.
- `RequiresAdmin = $true` tools are gated by the dispatcher; do not add your
  own elevation checks.

## PS 5.1 gotchas (violations fail review)

- `$(if ($x) { 'a' } else { 'b' })` - NEVER `(if ...)`; that throws
  CommandNotFoundException at runtime and AST tests will not catch it.
- ASCII only. No em dashes, smart quotes, box-drawing chars.
- UTF-8 without BOM. `Set-Content -Encoding UTF8` writes a BOM in PS 5.1;
  for files read by non-PowerShell apps use
  `[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))`.
- `Write-ToolOutput`, never `Write-Host` (breaks sink routing and PDQ logs).
- No PS7-only syntax (ternary, `??`, `?.`).
- Scheduled tasks that touch HKCU need an explicit
  `New-ScheduledTaskPrincipal` for the logged-on user (SYSTEM's HKCU is the
  wrong hive).
- Literal `{`/`}` in double-quoted strings need backtick escapes; `{{`/`}}`
  in `-f` format strings.

## Claude tooling in this repo

- Agent `nmm-tool-builder` (`.claude\agents\`): builds a tool end-to-end
  from a plain-language request; commits locally when green. Batch protocol
  is documented in the agent file.
- Skill `/nmm-review` (`.claude\skills\nmm-review\`): NMM checklist, then
  dispatches global ps-code-reviewer + security-code-reviewer.
- Skill `/nmm-ship` (`.claude\skills\nmm-ship\`): build -> test -> copy
  dist to Desktop -> sync to private repo. The ONLY sanctioned release path.

## Reference docs

- v9 design spec: `docs\superpowers\specs\2026-06-12-nmm-toolkit-v9-design.md`
- Claude tooling spec: `docs\superpowers\specs\2026-07-06-claude-tooling-design.md`
- Porting playbook: `docs\porting-playbook.md`
- v8 monolith (feature-frozen reference): `C:\Users\IT\Desktop\NMMTools-v8-fallback.ps1` if present
````

- [ ] **Step 2: Verify encoding and content**

Run:
```powershell
Set-Location C:\Users\IT\Desktop\NMMToolkit
$bytes = [System.IO.File]::ReadAllBytes('CLAUDE.md')
"BOM: $($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)"
$nonAscii = (Get-Content CLAUDE.md -Raw).ToCharArray() | Where-Object { [int]$_ -gt 127 }
"NonAscii chars: $(@($nonAscii).Count)"
```
Expected: `BOM: False`, `NonAscii chars: 0`

- [ ] **Step 3: Cross-check the registry contract against reality**

Run:
```powershell
$reg = Import-PowerShellDataFile src\registry\tools.psd1
($reg.Tools[0].Keys | Sort-Object) -join ','
```
Expected: `Category,Description,Function,Id,LegacyId,Name,RequiresAdmin,Risk,SilentCapable,Tags` - matches the field list documented in CLAUDE.md. If it differs, fix CLAUDE.md, not the registry.

- [ ] **Step 4: Commit**

```powershell
git add CLAUDE.md
git commit -m "docs: add project CLAUDE.md with tool contract and PS5.1 gotchas"
```

---

### Task 2: nmm-review skill

**Files:**
- Create: `C:\Users\IT\Desktop\NMMToolkit\.claude\skills\nmm-review\SKILL.md`

**Interfaces:**
- Produces: the review checklist at `.claude\skills\nmm-review\SKILL.md` - the single source of truth. Task 3's agent reads this exact path.

- [ ] **Step 1: Write the file**

Create directory `.claude\skills\nmm-review\` and write `SKILL.md` with exactly this content:

````markdown
---
name: nmm-review
description: NMM-specific review of new or modified NMMToolkit tools. Runs the registry/template/semantics checklist, then dispatches the global ps-code-reviewer and security-code-reviewer agents with the checklist injected. Use after any manual tool edit, or when asked to review NMMToolkit changes.
---

# NMM Tool Review

Review target: the changed tool files and registry entries in the working
tree (use `git status` / `git diff` to find them) unless the user names
specific tools.

## Part 1 - Mechanical checklist (run yourself, in order)

1. **Registry <-> file consistency.** For each changed tool:
   - Registry entry exists in `src\registry\tools.psd1` with all 10 fields:
     Id, LegacyId, Name, Category, Function, Description, RequiresAdmin,
     SilentCapable, Risk, Tags.
   - `Function` equals the filename minus `.ps1` and the function actually
     defined in the file.
   - `Category` (capitalized) matches the directory (lowercase):
     Browser/browser, Cloud/cloud, Diagnostics/diagnostics, Laptop/laptop,
     QuickFix/quickfix, Repair/repair, Security/security, User/user.
   - `Id` is kebab-case and unique; `LegacyId` is unique.
2. **Template compliance** (spec section 3, v9 design spec):
   - `[CmdletBinding()] param([switch]$Silent)` present.
   - First act inside try: `$run = New-ToolRun -Id '<registry Id>'` - the Id
     string must equal the registry Id exactly.
   - Every code path ends in exactly one `Complete-ToolRun` with Status one
     of Success/Warning/Failed/Skipped/Refused; catch block does
     `Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message`.
   - All output via `Write-ToolOutput`; all prompting via `Read-ToolChoice`
     with `-Silent:$Silent`. Zero `Write-Host`, `Read-Host`.
3. **Semantics sanity:**
   - Tool prompts the user? Then `Read-ToolChoice` defaults must make the
     silent path sensible, or `SilentCapable = $false`.
   - Tool changes system state? `Risk` must be Modifies or Disruptive, and
     `RequiresAdmin` set honestly.
   - Reboots, service-stops of critical services, or data deletion =>
     `Risk = 'Disruptive'`.
4. **PS 5.1 trap scan** (each is an automatic finding):
   - `(if ` used as an expression (must be `$(if ...)`)
   - Any non-ASCII character (em dash, smart quote)
   - `Write-Host` / `Read-Host`
   - PS7-only syntax: ternary `? :`, `??`, `?.`, chained `&&`/`||`
   - `Set-Content -Encoding UTF8` writing files consumed by non-PowerShell apps
5. **Gates:** `.\build.ps1` passes and `Invoke-Pester .\tests` is green. If
   either is red, report and stop - do not dispatch reviewers over a broken
   build.

## Part 2 - Reviewer dispatch

Dispatch BOTH global agents in parallel, each with: the diff (or file list),
the full Part 1 checklist text, and the project CLAUDE.md path
(`C:\Users\IT\Desktop\NMMToolkit\CLAUDE.md`) as required reading:

- `ps-code-reviewer` - correctness, standards, PDQ compatibility.
- `security-code-reviewer` - security implications of the change.

## Part 3 - Report

Merge Part 1 + Part 2 findings into one list ordered by severity. For each:
file:line, what, why it matters, suggested fix. State explicitly which
checklist items passed clean. Apply fixes only if the user asked for
review-and-fix.
````

- [ ] **Step 2: Verify encoding, frontmatter, and path**

Run:
```powershell
Set-Location C:\Users\IT\Desktop\NMMToolkit
$p = '.claude\skills\nmm-review\SKILL.md'
$raw = Get-Content $p -Raw
"Exists: $(Test-Path $p)"
"Frontmatter: $($raw -match '(?s)^---\r?\nname: nmm-review\r?\ndescription: .+?\r?\n---')"
$nonAscii = $raw.ToCharArray() | Where-Object { [int]$_ -gt 127 }
"NonAscii chars: $(@($nonAscii).Count)"
```
Expected: `Exists: True`, `Frontmatter: True`, `NonAscii chars: 0`

- [ ] **Step 3: Commit**

```powershell
git add .claude\skills\nmm-review\SKILL.md
git commit -m "feat: add nmm-review skill (checklist + reviewer dispatch)"
```

---

### Task 3: nmm-tool-builder agent

**Files:**
- Create: `C:\Users\IT\Desktop\NMMToolkit\.claude\agents\nmm-tool-builder.md`

**Interfaces:**
- Consumes: checklist file `.claude\skills\nmm-review\SKILL.md` (Task 2), conventions in `CLAUDE.md` (Task 1).
- Produces: dispatchable agent `nmm-tool-builder` for sessions started in NMMToolkit.

- [ ] **Step 1: Write the file**

Create directory `.claude\agents\` and write `nmm-tool-builder.md` with exactly this content:

````markdown
---
name: nmm-tool-builder
description: Use this agent to add one new tool to NMMToolkit from a plain-language request, end to end - scaffold the tool file and registry entry, build, test, self-review, and commit locally. Trigger on "add a tool that...", "build an NMM tool for...", or batch requests ("add these N tools" - see Batch dispatch protocol; one agent per tool). Does NOT sync, push, or deploy; that is /nmm-ship.

Examples:

<example>
user: "Add a tool that reports machine certificates expiring within 60 days, security category, read-only."
assistant: "I'll dispatch nmm-tool-builder to scaffold, build, test, review, and commit the tool."
</example>

<example>
user: "Add these three quickfix tools: clear Edge cache, reset Windows Search, rebuild icon cache."
assistant: "Batch request - I'll dispatch three nmm-tool-builder agents in parallel, one per tool, in isolated worktrees, then merge them sequentially."
</example>
---

You are the NMM tool builder. You build EXACTLY ONE tool per dispatch, end
to end, inside the NMMToolkit repo (`C:\Users\IT\Desktop\NMMToolkit` or the
worktree path given in your prompt).

Required reading before any work, in this order:
1. `CLAUDE.md` (repo root) - the tool contract, registry fields, gotchas.
2. `.claude\skills\nmm-review\SKILL.md` - the review checklist you will
   apply to your own work in step 5.
3. One existing tool in the target category as a live example.

## Pipeline (do all steps; never skip, never reorder)

1. **Interpret the request.** Determine: tool purpose, Category, Risk,
   RequiresAdmin, SilentCapable, Id (kebab-case), Function (approved
   Verb-Noun), Name, Description, Tags. If the request does not state a
   value, infer it and RECORD the inference - every inferred value goes in
   your final report as an assumption. Do not stop to ask questions.
   LegacyId: read `src\registry\tools.psd1`, use max numeric LegacyId + 1.
2. **Scaffold.** Create `src\tools\<category>\<Verb-Noun>.ps1` per the
   CLAUDE.md template and append the registry entry to
   `src\registry\tools.psd1` (keep the existing formatting style: aligned
   `=` signs, entry placed at the end of the Tools array). ASCII only,
   UTF-8 no BOM.
3. **Build.** `.\build.ps1`. Fix and rerun until green.
4. **Test.** `Invoke-Pester .\tests`. Fix and rerun until green.
5. **Self-review.** Apply Part 1 of the nmm-review checklist to your own
   diff. Then dispatch `ps-code-reviewer` and `security-code-reviewer`
   (Part 2 of the checklist) with your diff and the checklist text. Apply
   confirmed findings; rerun build + tests after any change.
6. **Commit locally.**
   `git add <tool file> src\registry\tools.psd1`
   `git commit -m "feat(<category>): add <tool-id> tool"`
   Never push, never sync, never touch dist\ deployment or the Desktop copy.
7. **Report** (your final message): tool id + function + files touched, the
   registry entry verbatim, build/test output summary (counts, not walls of
   text), review findings applied, and ALL assumptions made in step 1.

## Hard rules

- Red build or red tests at the end = report FAILURE with the actual output.
  Never claim success past a red gate. Never commit on red.
- One tool per dispatch. If your prompt contains multiple tools, build only
  the first and say so in your report.
- Never edit files outside `src\tools\<category>\` and
  `src\registry\tools.psd1` except when a reviewer finding requires it -
  then say so explicitly in your report.

## Batch dispatch protocol (for the ORCHESTRATOR, not this agent)

For "add these N tools" requests, the main session must:
1. Dispatch N nmm-tool-builder agents concurrently, one tool each, each
   with `isolation: worktree` so parallel edits to `tools.psd1` cannot
   collide. Tell each agent its worktree path.
2. After all report green: merge each branch back into master SEQUENTIALLY.
   A `tools.psd1` conflict means both branches appended an entry - resolve
   by keeping BOTH entries (reassign LegacyIds sequentially if two agents
   picked the same number).
3. Re-run `.\build.ps1` + `Invoke-Pester .\tests` after EACH merge; master
   only advances green.
4. A branch that cannot merge green is left on its branch and reported for
   manual resolution; continue with the remaining branches.
````

- [ ] **Step 2: Verify encoding, frontmatter, and checklist path**

Run:
```powershell
Set-Location C:\Users\IT\Desktop\NMMToolkit
$p = '.claude\agents\nmm-tool-builder.md'
$raw = Get-Content $p -Raw
"Exists: $(Test-Path $p)"
"Frontmatter: $($raw -match '(?s)^---\r?\nname: nmm-tool-builder\r?\ndescription: .+')"
"ChecklistRef: $($raw -match [regex]::Escape('.claude\skills\nmm-review\SKILL.md'))"
$nonAscii = $raw.ToCharArray() | Where-Object { [int]$_ -gt 127 }
"NonAscii chars: $(@($nonAscii).Count)"
```
Expected: all `True`, `NonAscii chars: 0`

- [ ] **Step 3: Commit**

```powershell
git add .claude\agents\nmm-tool-builder.md
git commit -m "feat: add nmm-tool-builder agent"
```

---

### Task 4: nmm-ship skill

**Files:**
- Create: `C:\Users\IT\Desktop\NMMToolkit\.claude\skills\nmm-ship\SKILL.md`

**Interfaces:**
- Consumes: `build.ps1`, `tests\`, `C:\Users\IT\Claude-Files\nmm-toolkit\sync.ps1` (existing; copies `Desktop\nmmtools.ps1` into the Claude-Files repo, stages, and with `-Message` commits + rebases + pushes).

- [ ] **Step 1: Write the file**

Create directory `.claude\skills\nmm-ship\` and write `SKILL.md` with exactly this content:

````markdown
---
name: nmm-ship
description: Release the NMMToolkit build - full build, full test suite, copy dist to the Desktop deployment copy, sync to the private repo (mwgrant21/Claude-Files) with a descriptive commit message, push. Use when asked to "ship", "release", or "sync nmm". Hard-stops on any red gate.
---

# NMM Ship

Working directory: `C:\Users\IT\Desktop\NMMToolkit`. Run the gates IN ORDER;
any failure = STOP, report the failing output, ship nothing.

## Gate 0 - clean tree

`git status --porcelain` in NMMToolkit. Uncommitted changes to `src\` or
`tests\`? STOP and tell the user what is uncommitted - ship only committed
work.

## Gate 1 - build

    .\build.ps1

Any throw (parse gate, analyzer gate) = STOP.

## Gate 2 - tests

    Invoke-Pester .\tests

Any failed test = STOP. Report the failure names and output.

## Step 3 - deploy copy

    Copy-Item dist\NMMTools.ps1 "$env:USERPROFILE\Desktop\nmmtools.ps1" -Force

The Desktop copy is what sync.ps1 reads - this step is what makes the new
build shippable.

## Step 4 - stage and diff

    & "$env:USERPROFILE\Claude-Files\nmm-toolkit\sync.ps1" -StageOnly

If it prints "No changes to sync" - report that and stop (nothing to ship).
Otherwise read the staged change:

    git -C "$env:USERPROFILE\Claude-Files" --no-pager diff --cached --stat

and read `git -C C:\Users\IT\Desktop\NMMToolkit log --oneline` since the
last ship to know WHAT is in this release.

## Step 5 - commit message and push

Compose a message: first line "NMMTools vX.Y.Z - <one-line summary>", then
a bullet per tool added/changed (from the NMMToolkit commits). Then:

    & "$env:USERPROFILE\Claude-Files\nmm-toolkit\sync.ps1" -Message "<the message>"

sync.ps1 handles commit + pull --rebase + push. If it reports a rebase
conflict or push failure, report verbatim and stop - never force-push.

## Step 6 - report

Version shipped, gates passed (build, N tests), diff stat, commit message
used, push result.
````

- [ ] **Step 2: Verify encoding, frontmatter, and sync path**

Run:
```powershell
Set-Location C:\Users\IT\Desktop\NMMToolkit
$p = '.claude\skills\nmm-ship\SKILL.md'
$raw = Get-Content $p -Raw
"Exists: $(Test-Path $p)"
"Frontmatter: $($raw -match '(?s)^---\r?\nname: nmm-ship\r?\ndescription: .+')"
"SyncPath: $(Test-Path "$env:USERPROFILE\Claude-Files\nmm-toolkit\sync.ps1")"
$nonAscii = $raw.ToCharArray() | Where-Object { [int]$_ -gt 127 }
"NonAscii chars: $(@($nonAscii).Count)"
```
Expected: all `True`, `NonAscii chars: 0`

- [ ] **Step 3: Commit**

```powershell
git add .claude\skills\nmm-ship\SKILL.md
git commit -m "feat: add nmm-ship skill (gated release flow)"
```

---

### Task 5: Acceptance - build a real tool through the pipeline

Validates the builder agent doc by having a fresh general-purpose agent follow it verbatim (this session did not start in NMMToolkit, so the agent name is not registered here; the DOC is what we are testing).

**Files:**
- Create (by the dispatched agent): `src\tools\security\Get-CertificateExpiryReport.ps1`
- Modify (by the dispatched agent): `src\registry\tools.psd1`

**Interfaces:**
- Consumes: all of Tasks 1-4.
- Produces: tool `certificate-expiry` (Function `Get-CertificateExpiryReport`, Category `Security`, Risk `ReadOnly`, RequiresAdmin `$false`, SilentCapable `$true`, LegacyId next free number) - verified absent from the registry on 2026-07-06.

- [ ] **Step 1: Dispatch the builder simulation**

Dispatch ONE general-purpose agent with exactly this prompt:

> Read `C:\Users\IT\Desktop\NMMToolkit\.claude\agents\nmm-tool-builder.md` and follow it as your instructions, exactly. Your tool request: "Add a tool that reports machine certificates (LocalMachine\My) expiring within the next 60 days, including already-expired ones - subject, thumbprint, NotAfter, days remaining. Security category, read-only, silent-capable, no admin required. Warning status if any certificate expires within 60 days, Success if none do." Work directly in `C:\Users\IT\Desktop\NMMToolkit` (single-tool dispatch - no worktree needed).

- [ ] **Step 2: Verify the agent's work independently**

Run (do not trust the report alone):
```powershell
Set-Location C:\Users\IT\Desktop\NMMToolkit
Test-Path src\tools\security\Get-CertificateExpiryReport.ps1
$reg = Import-PowerShellDataFile src\registry\tools.psd1
$t = $reg.Tools | Where-Object Id -eq 'certificate-expiry'
"Entry: $($null -ne $t); Fn: $($t.Function); Cat: $($t.Category); Risk: $($t.Risk)"
.\build.ps1
Invoke-Pester .\tests
git log --oneline -3
```
Expected: file exists; `Entry: True; Fn: Get-CertificateExpiryReport; Cat: Security; Risk: ReadOnly`; build green; all tests pass; a `feat(security): add certificate-expiry tool` commit exists.

- [ ] **Step 3: CLI smoke test of the artifact**

Run:
```powershell
powershell -NoProfile -File dist\NMMTools.ps1 -ListTools | Select-String certificate-expiry
powershell -NoProfile -File dist\NMMTools.ps1 -Tool certificate-expiry -Silent
"ExitCode: $LASTEXITCODE"
```
Expected: `-ListTools` line contains `certificate-expiry`; the tool runs and prints certificate output (or a clean none-found message); `ExitCode: 0` (Success and Warning both exit 0).

- [ ] **Step 4: Fix-forward if red**

If any of Steps 2-3 fail: apply superpowers:systematic-debugging, fix, re-run the failed step. Do not delete the tool to make gates pass.

---

### Task 6: Acceptance - ship it

- [ ] **Step 1: Execute the nmm-ship flow**

Follow `.claude\skills\nmm-ship\SKILL.md` exactly as written (Gates 0-2, Steps 3-6). This validates the skill doc AND releases the certificate-expiry tool for real. Ship commit message first line: `NMMTools v9.1.0 - add certificate-expiry tool`.

- [ ] **Step 2: Verify the push**

Run:
```powershell
git -C "$env:USERPROFILE\Claude-Files" log --oneline -1
git -C "$env:USERPROFILE\Claude-Files" status
```
Expected: newest commit is the ship commit; status reports branch up to date with origin.

- [ ] **Step 3: Final manual note for the user**

Report to the user: registration of the agent + skills happens automatically the next time a Claude Code session starts in `C:\Users\IT\Desktop\NMMToolkit` - suggest opening one there and running `/nmm-review` or dispatching `nmm-tool-builder` to confirm. (Optional visual check: launch the GUI - `powershell -File dist\NMMTools.ps1` - and confirm certificate-expiry appears under Security.)
