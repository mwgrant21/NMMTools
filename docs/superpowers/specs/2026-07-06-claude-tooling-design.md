# NMMToolkit Claude Code Integration - Design Spec

Date: 2026-07-06
Status: Approved

## Purpose

Eliminate the four recurring friction points when developing NMMToolkit with
Claude Code: the add-a-tool ceremony, generic (non-NMM-aware) review, the
manual build/test/sync loop, and per-session context loss. All tooling is
development-side only; nothing ships inside `dist\NMMTools.ps1`.

## Scope and Location

All artifacts live in the NMMToolkit repo, versioned with the code and synced
to the private repo (`mwgrant21/Claude-Files`) via the existing sync flow:

```
NMMToolkit\
  CLAUDE.md                          # project conventions, auto-loaded
  .claude\
    agents\
      nmm-tool-builder.md            # tool-building agent (primary workhorse)
    skills\
      nmm-review\SKILL.md            # NMM review checklist + reviewer dispatch
      nmm-ship\SKILL.md              # build -> test -> sync -> commit -> push
```

No new global (`~/.claude`) assets. Existing global agents
(`ps-code-reviewer`, `security-code-reviewer`) are reused, not duplicated.

## Component 1: CLAUDE.md

One page. Contents:

- Registry contract: one entry per tool in `src\registry\tools.psd1`; entry
  shape (Id, Name, Category, Function, SilentCapable, Risk, legacy menu
  number) mirrored from the current file.
- Tool file contract: one file per tool at
  `src\tools\<category>\<Verb-Noun>.ps1`, template rules per spec section 3
  of `docs\superpowers\specs\2026-06-12-nmm-toolkit-v9-design.md`.
- Category list (browser, cloud, diagnostics, laptop, quickfix, repair,
  security, user) and `src\core` numeric build-order prefix convention.
- Semantics: `-Silent` refusal rules, `Risk = 'Disruptive'` + `-Force`,
  exit codes (0 = Success/Warning/Skipped, 1 = Failed/Refused/unknown).
- Commands: `.\build.ps1` (parse gate + analyzer gate), `Invoke-Pester
  .\tests` (Pester >= 5.0).
- PS5.1 gotchas: `$(if ...)` not `(if ...)`; UTF-8 without BOM
  (`Set-Content -Encoding UTF8` writes BOM in PS5.1); explicit scheduled-task
  principal for HKCU work; Write-Output not Write-Host; ASCII only.
- Pointers to the v9 spec and `docs\porting-playbook.md` for depth.

Fixes context loss for interactive sessions and for every dispatched agent
(project agents inherit project CLAUDE.md).

## Component 2: nmm-tool-builder agent

The most-used piece. Input: a plain-language tool request, e.g. "add a tool
that clears the print spooler, quickfix category, silent-capable".

### Single-tool pipeline (one dispatch, self-contained)

1. Scaffold `src\tools\<category>\<Verb-Noun>.ps1` following the artifact
   contract, plus the matching registry entry in `tools.psd1`.
2. Infer category / Risk / SilentCapable when not stated; every inference is
   flagged as an assumption in the final report. The builder does not stop to
   ask questions.
3. Run `.\build.ps1` and the Pester suite; iterate until green.
4. Auto-review: read the checklist from
   `.claude\skills\nmm-review\SKILL.md` (the single source of truth for
   review rules), dispatch `ps-code-reviewer` and
   `security-code-reviewer` with the checklist injected, apply confirmed
   findings, re-run build + tests.
5. Commit locally with a conventional message describing the tool. No sync,
   no push - that remains `/nmm-ship`'s job.
6. Report: files touched, registry entry, test results, review findings
   applied, assumptions made.

### Batch mode ("add these N tools")

- One builder per tool, dispatched concurrently, each in an isolated git
  worktree on its own branch, running the full single-tool pipeline
  including the local commit.
- Rationale: tool files are conflict-free (unique paths) but every builder
  edits the shared `tools.psd1`; worktrees defer that to merge time where
  the conflict is mechanical (both sides appended an entry; keep both).
- Integration step: merge branches back sequentially; resolve `tools.psd1`
  conflicts by keeping both entries; re-run `build.ps1` + Pester after each
  merge so master only advances green. Result: one commit per tool.

### Guardrails

- Never claims success past a red build or failing tests; reports failures
  with output instead.
- Never syncs, pushes, or deploys.
- Existing Pester registry-consistency tests are the safety net; no new test
  infrastructure.

## Component 3: nmm-review skill

`/nmm-review` for reviewing manual edits (the builder invokes the same
checklist automatically - one source of truth for review rules).

Checklist:
- Registry <-> tool file consistency (entry exists, function name matches,
  category matches directory).
- Artifact/template contract compliance (spec section 3).
- `-Silent` / Risk / exit-code semantics correct for the tool's behavior.
- PS5.1 trap scan (the CLAUDE.md gotcha list).

After the checklist, dispatches the existing global `ps-code-reviewer` and
`security-code-reviewer` agents with the checklist injected as context.

## Component 4: nmm-ship skill

`/nmm-ship` formalizes the "sync nmm" ritual:

1. `.\build.ps1` - abort on red.
2. Full Pester run - abort on failures.
3. `C:\Users\IT\Claude-Files\nmm-toolkit\sync.ps1 -StageOnly`
4. Read the staged diff, write the commit message.
5. Push to `mwgrant21/Claude-Files`.

Refuses to proceed past a red build or failing tests.

## Error Handling

- Builder: red build/tests -> iterate; if stuck, report failure with output.
- Batch integration: a merge that cannot go green is reported and left on
  its branch for manual resolution; other tools' merges proceed.
- nmm-ship: hard-stops at the first red gate; never force-pushes.

## Acceptance Test

Build one real, small tool through the full pipeline - builder (scaffold,
build, test, auto-review, commit) then `/nmm-ship` - and confirm the tool
appears in the GUI (registry-driven, no wiring needed) and passes
`-ListTools` / `-Tool <id> -Silent` CLI smoke checks.

## Out of Scope

- New features inside NMMTools.ps1 itself.
- Duplicate reviewer agents; global reviewers are reused.
- Deployment (PDQ or otherwise).
