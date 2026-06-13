# NMM Toolkit v9 — Porting Playbook

Rules for porting a v8 tool. The v8 monolith (`C:\Users\IT\Desktop\NMMTools.ps1`)
is READ-ONLY behavioral reference.

## The Id-in-three-places rule
The kebab-case slug must be identical in: (1) the registry `Id`, (2) the tool's
`New-ToolRun -Id '<slug>'`, (3) nowhere else. `tests\template.tests.ps1` enforces this.

## Template (mandatory shape)
    function Verb-Noun {
        [CmdletBinding()]
        param([switch]$Silent)   # required by dispatcher even when unused

        $run = $null
        try {
            $run = New-ToolRun -Id '<slug>'
            # ... port v8 behavior here ...
            Complete-ToolRun $run -Status Success -Summary '<one line for the ticket>'
        }
        catch {
            Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
        }
    }

## Hard rules
- NEVER call Write-Host or Read-Host in a tool. Use `Write-ToolOutput -Level Info|Success|Warning|Error|Detail`
  and `Read-ToolChoice -Prompt ... -Default ... -Silent:$Silent`.
- Every prompt needs a safe `-Default` — that default is what `-Silent` (PDQ) auto-selects.
- Approved verbs only (`Get-Verb`); rename v8 `Fix-*` → `Repair-*` etc., keep the old name in registry Tags.
- Status meanings: Success = did the thing; Warning = ran, found something worth flagging;
  Skipped = user declined; Failed = could not do the thing. Summary goes on the ticket — write it for a tech.
- Registry fields: `Risk` = ReadOnly | Modifies | Disruptive (Disruptive needs -Force under -Silent).
  `SilentCapable = $false` only when the tool is meaningless without interaction.
- Preserve v8 BEHAVIOR (what it checks/fixes/reports), not v8 code. Drop v8's Add-ToolResult,
  colors, Write-Host formatting; keep thresholds, registry paths, command invocations.
- File: `src\tools\<category>\<Verb-Noun>.ps1`, UTF-8 with BOM, one function per file
  (private helpers may be nested INSIDE the function body).

## Per-batch loop
    .\build.ps1
    Import-Module Pester -MinimumVersion 5.0; Invoke-Pester .\tests
Both must be green before commit. Smoke at least one ported read-only tool via:
    .\dist\NMMTools.ps1 -Tool <slug> -Silent

## Conventions hardened after batch 1

- **Encoding:** Source .ps1 must be ASCII-only (use `-` not the em-dash). `tests\encoding.tests.ps1`
  enforces this. The build writes a BOM'd artifact; source stays ASCII so no read path can mojibake.

- **Tag vocabulary:** singular nouns, no redundant tags (e.g. don't list both 'features' and
  'windows-features'); search is tag-driven so spelling consistency matters.

- **Risk taxonomy:** ReadOnly = inspects state and MAY emit a report artifact to disk (e.g.
  hardware-summary, ticket export) but changes NO system configuration; Modifies = changes system
  state reversibly/routinely; Disruptive = can close/replace running software or force a reboot
  (requires -Force under -Silent).

- **Network calls (batch 2+):** every call to a remote/cloud service (Azure AD, M365, Teams, DNS)
  must have an explicit timeout and/or `-ErrorAction` guard and degrade to a Warning summary on
  unreachable/denied - never let a hang or throw become an unhandled Failed. Mirror
  `Get-SecurityAnalysis` ('Unable to check' -> Warning) and `Test-NetworkConnectivity`
  (per-target failure) patterns.
