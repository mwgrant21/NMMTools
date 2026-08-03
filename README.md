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

## CLI / PDQ usage

    NMMTools.ps1 -ListTools
    NMMTools.ps1 -Tool system-uptime -Silent
    NMMTools.ps1 -Tool 20 -Silent                      # legacy v8 menu number
    NMMTools.ps1 -Tool temp-cleanup -Silent -LogPath C:\Logs

Exit code 0 = Success/Warning/Skipped, 1 = Failed/Refused/unknown tool.
`-Silent` refuses tools registered `SilentCapable = $false`, and refuses
`Risk = 'Disruptive'` tools unless `-Force` is added.

## How this was built

Full transparency: the v9 modularization was implemented by directing Claude Code against
the approved spec in `docs\superpowers\specs\`. The tool inventory, registry design, risk
gating, and build-gate requirements come from real support work on our fleet; I reviewed
and tested every tool against the v8 reference before shipping. AI wrote most of the
keystrokes — the operational judgment is mine.
