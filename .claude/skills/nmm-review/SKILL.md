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
