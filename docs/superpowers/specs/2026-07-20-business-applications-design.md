# Business Applications Category — Design Spec
**Date:** 2026-07-20
**Status:** Approved
**Scope:** One new tool category (`Business`) and three new read-only diagnostic tools —
`Get-GlobalProtectStatus`, `Get-NitroProStatus`, `Get-RingCentralStatus`. No existing tool's
behavior changes.

---

## Background

The NMM Diagnostic Bundle spec (`2026-07-19-nmm-diagnostic-bundle-design.md`) explicitly scoped
out a new "Business Applications" category — naming GlobalProtect, Nitro, and RingCentral as
candidates — as a separate future project. That framework was never written up beyond that
one-line deferral note; this spec is the first real design for it.

This build covers diagnostics only. Repair/fix tools for these apps, remote/multi-machine
execution, and Jira-attachment wiring remain out of scope, consistent with the toolkit-wide
non-goals already established in the diagnostic-bundle spec.

---

## Category

- New dir `src\tools\business\`, matching the existing lowercase-dir convention (browser, cloud,
  diagnostics, laptop, quickfix, repair, security, user).
- Registry `Category = 'Business'` — single word, capitalized, matching every existing category
  field (not the two-word "Business Applications" from the deferral note).
- All three tools: `Risk = 'ReadOnly'`, `RequiresAdmin = $false`, `SilentCapable = $true` — same
  profile as the recent diagnostic-bundle tools. Registry entries appended at LegacyId 117-119
  (next free after 116).
- Each follows the standard five-element tool template (`New-ToolRun` / `Write-ToolOutput` /
  `Complete-ToolRun`, `[switch]$Silent` param). No GUI/console-menu wiring needed — both are
  registry-driven.

---

## Tool 1: `Get-GlobalProtectStatus`

Diagnoses the Palo Alto GlobalProtect VPN client.

Checks:
- `PanGPS` service status (`Get-Service`) — the system-level GP service.
- `PanGPS.exe` process running (user-mode connection is driven by the service; process check is
  a secondary signal).
- Portal/gateway configuration presence: `HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\Settings`
  and `...\PanGPS` (verify exact value names against a real install before shipping — sourced
  from Palo Alto's public KB, not yet confirmed against this org's client version).
- Active VPN adapter presence (`Get-NetAdapter` filtered for GlobalProtect/Palo, same pattern
  already used in `Get-TeamsMeetingQuality`).
- Tail of `PanGPS.log` (`C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.log`, falling
  back to the numbered rotation `PanGPS.1.log` etc. if the base file is empty) for recent
  auth-failure / gateway-unreachable lines.
- Tail of the per-user `PanGPA.log`
  (`C:\Users\<user>\AppData\Local\Palo Alto Networks\GlobalProtect\PanGPA.log`) for the same.

Verdict: connected / disconnected / service-down / not-installed, plus a rollup of any log
errors found, same shape as the existing verdict pattern.

---

## Tool 2: `Get-NitroProStatus`

Diagnoses Nitro PDF Pro installation and licensing.

Checks:
- Install detection + version via the uninstall registry key (`HKLM:\SOFTWARE\Nitro\PDF Pro\<ver>`
  and the standard `Uninstall\{GUID}` key — the GUID is version-specific and needs confirming
  against the org's deployed Nitro version at implementation time).
- License/activation state under `HKLM:\SOFTWARE\Nitro\PDF Pro\<ver>\settings\NLS`
  (trial vs activated — exact value name to confirm on a real install).
- Process running check (`NitroPDF.exe` / current process name — verify against installed
  version).
- Whether Nitro is the current default PDF handler (`HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice`
  ProgId check) — a common support complaint (Adobe silently reclaiming the file association).

Verdict: installed/not, licensed/trial/expired, default-handler yes/no.

---

## Tool 3: `Get-RingCentralStatus`

Diagnoses the RingCentral desktop app.

Checks:
- Install detection (`C:\Users\<user>\AppData\Local\Programs\RingCentral`, with a fallback check
  for the legacy `AppData\Local\Glip\app-<version>` path from when the app was branded Glip).
- Process running check.
- Version, from the install manifest if present.
- Default microphone/audio-device sanity check (`Get-CimInstance Win32_SoundDevice` /
  default-communications-device query) — headset/mic issues are the most common RingCentral
  ticket category.
- Tail of `C:\Users\<user>\AppData\Local\RingCentral\RingCentralLogs` for recent
  connect/call-quality error lines.
- Lightweight reachability check (DNS + ping) to a RingCentral service endpoint — kept
  deliberately shallower than `Get-TeamsMeetingQuality`'s full latency/jitter/QoS pass, to avoid
  duplicating that tool's depth for a lower-priority app.

Verdict: installed/not, running/not, audio device found/not, rollup of recent log errors.

---

## Registry entries

Three entries appended to `src\registry\tools.psd1`, `Category = 'Business'`,
`Risk = 'ReadOnly'`, `RequiresAdmin = $false`, `SilentCapable = $true`:

```powershell
@{
    Id            = 'globalprotect-status'
    LegacyId      = '117'
    Name          = 'GlobalProtect VPN Status'
    Category      = 'Business'
    Function      = 'Get-GlobalProtectStatus'
    Description   = 'Checks GlobalProtect VPN connection state, service health, and recent log errors'
    RequiresAdmin = $false
    SilentCapable = $true
    Risk          = 'ReadOnly'
    Tags          = @('globalprotect', 'vpn', 'paloalto', 'business')
}
@{
    Id            = 'nitro-pro-status'
    LegacyId      = '118'
    Name          = 'Nitro PDF Pro Status'
    Category      = 'Business'
    Function      = 'Get-NitroProStatus'
    Description   = 'Checks Nitro PDF Pro install, license/activation state, and default PDF handler'
    RequiresAdmin = $false
    SilentCapable = $true
    Risk          = 'ReadOnly'
    Tags          = @('nitro', 'pdf', 'license', 'business')
}
@{
    Id            = 'ringcentral-status'
    LegacyId      = '119'
    Name          = 'RingCentral App Status'
    Category      = 'Business'
    Function      = 'Get-RingCentralStatus'
    Description   = 'Checks RingCentral desktop app install/run state, audio device, and recent log errors'
    RequiresAdmin = $false
    SilentCapable = $true
    Risk          = 'ReadOnly'
    Tags          = @('ringcentral', 'softphone', 'audio', 'business')
}
```

---

## Non-goals (explicit)

- No repair/fix tools for these apps in this pass — diagnostics only. Repair tools are a
  candidate follow-up once these prove out what's actually broken in the field.
- No "Business Applications" two-word category name — single-word `Business`, matching every
  existing category.
- No remote/multi-machine execution — toolkit is local-only (standing toolkit-wide non-goal).
- No Jira-attachment wiring — unrelated to this build.
- No apps beyond GlobalProtect, Nitro, and RingCentral — additional business apps are a separate
  future ask.

---

## Verification risk (called out explicitly, not left implicit)

The exact registry key names, log paths, and process names above are sourced from public
vendor KB articles and community reports, not confirmed against this org's actual deployed
versions of these three apps. Each is marked above where it needs confirming. Implementation
should verify against a real install of each app and adjust before shipping — matching the
repo's existing "build -> Pester -> manual smoke test" convention (`docs\porting-playbook.md`);
this repo has no per-tool business-logic test files for any of its ~115 existing diagnostic
tools, only structural checks (`tests\template.tests.ps1` / `tests\registry.tests.ps1`).

---

## Testing

- `tests\template.tests.ps1` / `tests\registry.tests.ps1` — structural checks, run automatically
  against every tool file (registry/file/function agreement).
- `.\build.ps1` then `Invoke-Pester .\tests` — full suite, same as every prior tool addition.
- Manual smoke test through the built artifact on a machine with each app installed, to confirm
  the verification-risk items above and adjust any wrong paths.
