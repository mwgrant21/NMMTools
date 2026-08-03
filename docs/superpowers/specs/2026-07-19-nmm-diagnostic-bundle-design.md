# NMM Diagnostic Bundle — Design Spec
**Date:** 2026-07-19
**Status:** Approved
**Scope:** One new orchestrator tool (`Invoke-DiagnosticBundle`), four new standalone diagnostic
tools that fill real gaps, and two small additive core changes. No existing tool's behavior
changes for callers who don't use the new optional parameters.

---

## Background

Individual diagnostic tools already cover most of what a technician collects for a ticket
(event errors, network config, Entra join state, installed software, uptime, pending reboot),
but there's no single "collect everything, zip it, give me a summary" workflow. Building that
turns several existing capabilities into one practical action instead of running ~11 tools by
hand and stitching the results together.

Four capabilities named in the original ask don't exist anywhere in the toolkit today and are
real gaps, not just missing wiring: Reliability Monitor history, `gpresult`/RSoP output, a
general Device Manager error-code scan, and WER application-crash-dump collection (today's
`Get-BSODCrashDumpParser` only covers kernel minidumps). These are built as independent,
registry-listed tools — reusable outside the bundle, consistent with how every other capability
in this toolkit works — not as bundle-only internal helpers.

Explicitly out of scope for this build: a new "Business Applications" category, Jira-attachment
wiring (the existing "Send to Jira" comment flow is untouched), and any remote/multi-machine
execution (NMMTools is local-only; a remote-capable tool is a separate future project with its
own security review).

---

## Architecture decision: capturing raw per-check output

Existing tools emit output only as a side effect — `Write-ToolOutput` fans out to
console/log-file/GUI, and `Complete-ToolRun` records a one-line `Status`/`Summary` into the
session's `$script:ToolRuns`. Nothing today captures a check's *raw* output text tied to that
one run, which the bundle needs for its per-check raw-data files.

**Decision: add a fourth output sink, `Capture`, to `src/core/02-output.ps1`.** Two new
functions, `Start-ToolOutputCapture` / `Stop-ToolOutputCapture`, save/restore the prior sink and
buffer `Write-ToolOutput` calls into a `StringBuilder` while capture is active:

```powershell
function Start-ToolOutputCapture {
    $script:CapturePrevSink = $script:OutputSink
    $script:CapturePrevLog  = $script:LogFilePath
    $script:CaptureBuffer   = New-Object System.Text.StringBuilder
    $script:OutputSink      = 'Capture'
    $script:LogFilePath     = $null
}

function Stop-ToolOutputCapture {
    $text = ''
    if ($script:CaptureBuffer) { $text = $script:CaptureBuffer.ToString() }
    $script:OutputSink    = $script:CapturePrevSink
    $script:LogFilePath   = $script:CapturePrevLog
    $script:CaptureBuffer = $null
    return $text
}
```

`Write-ToolOutput` gets one new branch: `elseif ($script:OutputSink -eq 'Capture') { [void]
$script:CaptureBuffer.AppendLine($Message) }`. `'Capture'` is intentionally NOT added to
`Set-OutputSink`'s public `ValidateSet` — it's an internal mode entered only via
`Start-ToolOutputCapture`, never a mode a tool or the entry point selects directly.

This means every existing (and future) tool works with the bundle **unchanged** — no
refactor of the ~15+ tools it calls, no new contract for tool authors.

**Second small core change:** `Export-TicketSummary` (`src/core/03-results.ps1`) currently always
summarizes the *entire* session's `$script:ToolRuns`. Add an optional `-Runs` parameter
(default: `$script:ToolRuns`, so every existing caller is unaffected) so the bundle can pass just
its own slice and get the same proven summary format instead of reimplementing it.

---

## New tool 1 — Reliability Monitor History

**File:** `src/tools/diagnostics/Get-ReliabilityHistory.ps1`
**Risk:** ReadOnly | **RequiresAdmin:** false | **Id:** `reliability-history` | **LegacyId:** 112

Queries `Win32_ReliabilityRecords` via CIM (`Get-CimInstance -ClassName Win32_ReliabilityRecords`)
for the selected window (see "Time window" below), grouped by `SourceName`/`EventIdentifier`.
Reports top recurring failure sources first (app crashes, driver failures, Windows failures),
each with count and most recent timestamp. Optional `-HoursBack` param (default 24) so it can be
called standalone with its existing default, or with a wider window from the bundle.

## New tool 2 — Group Policy Result

**File:** `src/tools/diagnostics/Get-GroupPolicyResult.ps1`
**Risk:** ReadOnly | **RequiresAdmin:** false | **Id:** `group-policy-result` | **LegacyId:** 113

Runs `gpresult /r` (RSoP summary: applied GPOs, security group membership, last policy refresh
time) and reports it. No mutation — this is the read counterpart to the existing
`Update-GroupPolicy` (`gpupdate /force`) repair tool.

## New tool 3 — Device Manager Errors

**File:** `src/tools/diagnostics/Get-DeviceManagerErrors.ps1`
**Risk:** ReadOnly | **RequiresAdmin:** false | **Id:** `device-manager-errors` | **LegacyId:** 114

`Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }`, reports
device name, class, and the decoded Device Manager error-code meaning (a small lookup table for
the common codes: 1, 10, 18, 22, 28, 31, 43, etc.).

## New tool 4 — WER Application Crash Inventory

**File:** `src/tools/diagnostics/Get-CrashDumpInventory.ps1`
**Risk:** ReadOnly | **RequiresAdmin:** false | **Id:** `wer-crash-inventory` | **LegacyId:** 115

Complements `Get-BSODCrashDumpParser` (kernel minidumps only). Enumerates
`%LOCALAPPDATA%\CrashDumps\*.dmp` and WER report folders
(`%ProgramData%\Microsoft\Windows\WER\ReportArchive` /
`%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive`) within the selected window, reporting
crashing application name, dump timestamp, and dump file size — file inventory only, no dump
parsing (that would need debugging tools not present on a bare endpoint). Optional `-HoursBack`
param, same pattern as tool 1.

## Bundle orchestrator — NMM Diagnostic Bundle

**File:** `src/tools/diagnostics/Invoke-DiagnosticBundle.ps1`
**Risk:** ReadOnly | **RequiresAdmin:** false | **Id:** `diagnostic-bundle` | **LegacyId:** 116

### Flow

1. `Read-ToolChoice -Prompt 'Time window' -Choices @('24h','7d') -Default '24h' -Silent:$Silent`
   — sets `$hoursBack` (24 or 168) passed to the four window-aware checks below.
2. Runs, in order, under `Start-ToolOutputCapture` / `Stop-ToolOutputCapture` pairs:
   Event Log errors, Reliability Monitor history (`-HoursBack`), Windows Update status,
   Device Manager errors, network configuration, dsregcmd/Entra state, Group Policy result,
   crash dumps — both `Get-BSODCrashDumpParser` (kernel) and `Get-CrashDumpInventory`
   (`-HoursBack`, WER), installed software, system uptime, pending reboot.
3. Records `$script:ToolRuns.Count` before step 2 and slices the new entries after, so the
   bundle's health summary reflects only its own checks even in a long console session.
4. Writes each check's captured raw text to `<checkid>.txt` in a working folder
   (`$env:TEMP\NMMTools-Bundle-<COMPUTERNAME>-<timestamp>\`).
5. Writes `summary.txt` — health rollup (PASS/WARN/FAIL per check, from each run's `Status`) at
   the top, then `Export-TicketSummary -Runs $bundleRuns` output below it (the exact copyable
   technician summary format already used elsewhere in the toolkit).
6. `Compress-Archive` the working folder to
   `Desktop\NMM-Diagnostic-Bundle_<COMPUTERNAME>_<timestamp>.zip` (same pattern as
   `Invoke-BrowserBackupRestore.ps1`), then removes the working folder.
7. `Complete-ToolRun` with a summary line: pass/warn/fail counts + ZIP path.

### Output (console)

```
Time window          : 24h
Checks run           : 11 (2 new gap-fill checks: Reliability Monitor, Device Manager)
Health summary        PASS  8   WARN 2   FAIL 1
  [WARN] Pending Reboot        - Windows Update requires reboot
  [WARN] Reliability History   - 3 repeated app-crash sources in window
  [FAIL] Group Policy Result   - gpresult returned no data (RSOP service issue)
Bundle                : C:\Users\<user>\Desktop\NMM-Diagnostic-Bundle_WKSTN-042_20260719-2210.zip
```

---

## Non-goals (explicit, so they don't creep back in)

- No "Business Applications" category / GlobalProtect / Nitro / RingCentral — separate project.
- No remote/multi-machine execution (`target_host`, WinRM, CIM sessions to other machines) — the
  toolkit has none today; adding it is its own design with its own security review.
- No direct Jira-attachment upload — the existing Jira comment flow already lets a tech paste
  the ticket summary; wiring ZIP attachment upload is a separate, explicit ask if wanted later.
- `Get-EventLogErrors`, `Get-WindowsUpdates`, `Get-NetworkDiagnostics`, `Get-AzureADHealthCheck`,
  `Get-InstalledSoftware`, `Get-SystemUptime`, `Get-PendingRebootStatus`,
  `Get-BSODCrashDumpParser` are called as-is; only `Get-EventLogErrors` gains an optional
  `-HoursBack` (default 24, so unspecified calls are unchanged) to make its lookback
  window-aware for the bundle.

## Registry entries

Five new entries appended to `src/registry/tools.psd1` (LegacyId 112-116), all
`Category = 'Diagnostics'`, `Risk = 'ReadOnly'`, `RequiresAdmin = $false`, `SilentCapable = $true`.

## Testing

- Tools 1-4: unit-testable with CIM/process mocks per existing Pester conventions
  (`tests/template.tests.ps1`, `tests/registry.tests.ps1` cover template/registry compliance
  automatically for any new tool).
- New `Start-ToolOutputCapture`/`Stop-ToolOutputCapture` pair: unit test in
  `tests/output.tests.ps1` — capture returns exactly the buffered lines, prior sink/log path
  restored after `Stop-ToolOutputCapture`, nested Console-session output unaffected.
- `Export-TicketSummary -Runs`: unit test in `tests/results.tests.ps1` — passing a subset returns
  only those runs; omitting `-Runs` matches today's full-session behavior (regression guard).
- Bundle tool: unit-testable for the health-summary/slicing/ZIP-path logic with mocked
  `$script:ToolRuns` and a stubbed `Compress-Archive`; full end-to-end ZIP creation validated by
  manual run before merge (per this repo's existing convention for tools touching the filesystem).
