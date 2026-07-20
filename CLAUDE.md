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

   Statuses: Success | Warning | Failed | Skipped. Every code path
   must end in exactly one Complete-ToolRun. Refused is dispatcher-issued
   only (silent/admin gates) - never pass it to Complete-ToolRun; it
   appears only in the artifact exit-code contract.

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
