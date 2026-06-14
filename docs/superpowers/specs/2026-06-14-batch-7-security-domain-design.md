# Batch 7 (Part 1): Security / Domain Tools - Design Spec

**Date:** 2026-06-14
**Scope:** Port v8 tools 51, 91, 92, 93, 101 into v9 under a new `Security` category. No consolidations.
This is **batch 7 Part 1**; Part 2 (Quick Fixes Q1-Q9) is a separate later cycle.
**Status:** Approved (brainstormed with Matt 2026-06-14). Next: writing-plans -> batch 7 implementation plan.

## Context

Final batch. Batches 1-6 are complete (86 tools, 71/71 tests). v8 monolith at
`C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference. v8 function locations:

| v8 # | v8 function | Line |
|-----:|---|---|
| 51 | `Repair-DomainTrust` | 4607 |
| 91 | `Repair-TimeSync` | 10846 |
| 92 | `Get-LocalAdminAudit` | 10930 |
| 93 | `Get-DefenderStatus` | 11031 |
| 101 | `Enable-RemoteDesktop` | 11639 |

## Usage model (unchanged)

Interactive technician at the keyboard; the toolkit self-elevates at launch. Optimize the interactive
experience; `-Silent` only needs to be SAFE. Every tool follows **report-then-action**: the read-only
report runs always, then `Read-ToolChoice -Choices @('None', <actions>) -Default 'None' -Silent:$Silent`
gates the action arm, so under `-Silent` the tool reports and does nothing (no credential prompts, no
typed-confirm gates reached).

## Decisions made with Matt (do not re-litigate)

1. **New `Category = 'Security'`** for all 5 tools (mirrors the v8 "Security & Domain" section). The
   landing menu letters categories alphabetically, so adding Security auto-inserts as **F** and shifts
   User to **G** (A=Browser B=Cloud C=Diagnostics D=Laptop E=Repair F=Security G=User). No menu code
   changes - `build.ps1` already recurses `src\tools`, so a new `src\tools\security\` folder builds
   automatically.
2. **Keep the domain Rejoin action, hardened.** Port all 7 of tool 51's actions including Rejoin
   (Remove-Computer -> WORKGROUP, Add-Computer, optional restart), gated behind a typed `REJOIN`
   confirmation; the tool is `Risk='Disruptive'` so the dispatcher also refuses silent-without-force.
3. **RDP gets Enable + Disable.** v8 only enabled; v9 reports state then offers Enable (typed confirm -
   increases exposure) or Disable (re-deny + close firewall). Disable is the purely-safer direction.
4. **No consolidations.** All 5 are distinct tools.

## Approved-verb / naming notes

| v8 function | v9 function | Note |
|---|---|---|
| `Repair-DomainTrust` (51) | `Repair-DomainTrust` | Repair approved - unchanged. Id `domain-trust-repair` |
| `Repair-TimeSync` (91) | `Repair-TimeSync` | Repair approved - unchanged. Id `time-sync-repair` |
| `Get-LocalAdminAudit` (92) | `Get-LocalAdminAudit` | Get kept deliberately: the tool's identity is a read-only audit; the Disable action is opt-in and defaults to None, so it is read-only unless chosen. Id `local-admin-audit` |
| `Get-DefenderStatus` (93) | `Get-DefenderStatus` | Get kept (same rationale; UpdateSignatures is the opt-in action). Id `defender-status` |
| `Enable-RemoteDesktop` (101) | `Set-RemoteDesktop` | Renamed: the tool now toggles both ways (Enable/Disable), so `Set` fits better than `Enable`. Set is approved. Id `rdp-config` |

## The five tools

`New-ToolRun -Id '<id>'` literal MUST equal the registry `Id`. All `SilentCapable = $true` (report arm
runs under `-Silent`). `Complete-ToolRun -Status` accepts only `Success | Failed | Warning | Skipped`
(`Error` is a `Write-ToolOutput -Level`, not a status). Interactive-only free-text prompts (`Read-Host`
typed confirmations, `Get-Credential`) are reached ONLY after an interactive action selection and never
under `-Silent` (action defaults to None) - the sanctioned exception per the porting playbook.

### 1. domain-trust-repair (v8 51)

- **Function** `Repair-DomainTrust`, **Category** Security, **RequiresAdmin** `$true`, **Risk**
  `Disruptive`.
- **Report (always):** `Win32_ComputerSystem` name/domain/PartOfDomain/workgroup; secure-channel test
  (`Test-ComputerSecureChannel`); DC list (`nltest /dclist:<domain>`); DNS resolution of `$env:USERDNSDOMAIN`;
  time-sync status (`w32tm /query /status`). **If not domain-joined: report that and finish (no action
  menu).**
- **Actions:** `Read-ToolChoice -Choices @('None','TestSecureChannel','RepairSecureChannel','ResetMachinePassword','ResyncTime','PurgeKerberos','RejoinDomain','ShowDetails') -Default 'None' -Silent:$Silent`.
  - `TestSecureChannel`: `Test-ComputerSecureChannel` (read-only), report OK/broken.
  - `RepairSecureChannel`: `Test-ComputerSecureChannel -Repair -Credential (Get-Credential ...)`; report result.
  - `ResetMachinePassword`: `Reset-ComputerMachinePassword -Credential (Get-Credential ...)`; advise restart.
  - `ResyncTime`: `w32tm /resync /force`; report exit. Cross-references `time-sync-repair` for deep repair.
  - `PurgeKerberos`: `klist purge`; advise re-auth.
  - `RejoinDomain`: typed `REJOIN` confirm via `Read-Host`; then `Get-Credential`; `Remove-Computer
    -UnjoinDomainCredential <cred> -WorkgroupName WORKGROUP -Force`; `Add-Computer -DomainName <domain>
    -Credential <cred> -Force`; offer restart (`shutdown /r /t 10`). Honest per-step status.
  - `ShowDetails`: read-only `dsregcmd /status` (AzureAd/DomainJoined/WorkplaceJoined), `nltest
    /dsgetdc:<domain>`, `nltest /sc_query:<domain>`.
- **Honesty:** each action reports its real outcome (try/catch -> Warning/Failed, never false Success);
  Get-Credential cancelled -> Skipped.
- **Tags:** `domain`,`kerberos`,`securechannel`,`nltest`,`ad`.

### 2. time-sync-repair (v8 91)

- **Function** `Repair-TimeSync`, **Category** Security, **RequiresAdmin** `$true`, **Risk** `Modifies`.
- **Report (always):** current system time; `w32tm /query /status` (source/stratum/last-sync);
  `w32tm /query /peers` (configured NTP peer or "none").
- **Actions:** `Read-ToolChoice -Choices @('None','Resync','FullRepair') -Default 'None' -Silent:$Silent`.
  - `Resync`: ensure W32Time running; `w32tm /resync /force`; report.
  - `FullRepair`: `w32tm /unregister` + `/register`; start W32Time; configure source (domain-joined ->
    `/syncfromflags:domhier`; else `/manualpeerlist:time.windows.com /syncfromflags:manual /reliable:YES`);
    `w32tm /resync /force`.
- **Honesty:** re-query `w32tm /query /status` "Last Successful Sync Time" after the action; if the source
  is still unset/unsynced, report **Warning** (not Success). Note the Kerberos 5-minute-skew caveat in
  output.
- **Tags:** `time`,`w32tm`,`ntp`,`kerberos`,`sync`.

### 3. local-admin-audit (v8 92)

- **Function** `Get-LocalAdminAudit`, **Category** Security, **RequiresAdmin** `$true`, **Risk**
  `Modifies`.
- **Report (always):** members of the local `Administrators` group (`Get-LocalGroupMember`); for each,
  PrincipalSource, last logon, DISABLED / PWD-NEVER-EXPIRES flags (local accounts), and an "UNEXPECTED"
  flag for active members not on the expected allow-list; built-in `Administrator` enabled/disabled state.
  Expected allow-list is a top-of-function constant: `Administrator`, `Domain Admins`, `Enterprise Admins`.
- **Actions:** `Read-ToolChoice -Choices @('None','DisableUnexpected') -Default 'None' -Silent:$Silent`
  (offered ONLY when unexpected active accounts exist; otherwise no action, report-only Success).
  - `DisableUnexpected`: for each flagged account, if it is a LOCAL account -> `Disable-LocalUser`; domain
    accounts are reported "cannot disable locally" and skipped.
- **Honesty:** count only confirmed disables (account was local + enabled + `Disable-LocalUser` did not
  throw); domain accounts never attempted; built-in Administrator is **report-only** (never auto-disabled).
- **Tags:** `admin`,`audit`,`localgroup`,`security`,`accounts`.

### 4. defender-status (v8 93)

- **Function** `Get-DefenderStatus`, **Category** Security, **RequiresAdmin** `$false` (read-only
  `Get-MpComputerStatus`; the lone non-admin tool this batch), **Risk** `Modifies`.
- **Report (always):** `Get-MpComputerStatus` -> Real-Time Protection, definition age + signature version,
  last quick scan + age, Antivirus/Antispyware/BehaviorMonitor/NIS enabled, Tamper Protection; active
  threats via `Get-MpThreatDetection`.
- **Actions:** `Read-ToolChoice -Choices @('None','UpdateSignatures') -Default 'None' -Silent:$Silent`.
  - `UpdateSignatures`: `Update-MpSignature`; report.
- **Honesty:** v8 auto-updated signatures on every run - v9 gates it behind the action. If
  `Get-MpComputerStatus` throws (third-party AV / Defender not active), report **Warning** "could not query
  Defender - third-party AV may be active" and finish (no action). Stale-definition / RTP-off / active-threat
  conditions drive a Warning-level summary.
- **Tags:** `defender`,`antivirus`,`security`,`threats`,`signatures`.

### 5. rdp-config (v8 101)

- **Function** `Set-RemoteDesktop`, **Category** Security, **RequiresAdmin** `$true`, **Risk**
  `Disruptive`.
- **Report (always):** `fDenyTSConnections` (RDP enabled when 0), NLA (`UserAuthentication`), Remote Desktop
  firewall group enabled state (`Get-NetFirewallRule -DisplayGroup 'Remote Desktop'`), TermService status +
  StartType.
- **Actions:** `Read-ToolChoice -Choices @('None','Enable','Disable') -Default 'None' -Silent:$Silent`.
  - `Enable`: typed `ENABLE` confirm via `Read-Host` (increases attack surface); set
    `fDenyTSConnections=0`, `UserAuthentication=1` (NLA), `Enable-NetFirewallRule -DisplayGroup 'Remote
    Desktop'`, `Set-Service TermService -StartupType Automatic` + start; re-query `fDenyTSConnections` and
    report Warning if not 0.
  - `Disable`: set `fDenyTSConnections=1`, `Disable-NetFirewallRule -DisplayGroup 'Remote Desktop'`;
    re-query and report.
- **Honesty:** Enable claims success only after re-querying `fDenyTSConnections -eq 0`; otherwise Warning.
- **Tags:** `rdp`,`remotedesktop`,`firewall`,`nla`,`termservice`.

## Registry entries

Five new entries appended to `src/registry/tools.psd1`, each
`@{ Id; LegacyId; Name; Category='Security'; Function; Description; RequiresAdmin; SilentCapable=$true;
Risk; Tags }`. LegacyId = the v8 number (51, 91, 92, 93, 101).

## Testing

- Existing template/registry/encoding AST suite auto-covers the 5 new tools (Id<->New-ToolRun match,
  approved verbs, `[switch]$Silent`, ASCII-only, UTF-8 BOM + trailing newline, registry completeness).
  Suite count 71 -> 76.
- New `Category='Security'` flows through the dynamic landing menu with no code change (precedent: 'Browser'
  added batch 5, 'User' added batch 6c).
- Per-tool: PSScriptAnalyzer clean; `build.ps1` compiles; spot-run report arm under `-Silent` returns
  report-only with no state change and no credential/typed-confirm prompt.
- Interactive credential/typed-confirm paths cannot be exercised headless (self-elevation + Get-Credential);
  rely on green dispatch/template tests + `-ListTools` (same constraint noted since batch 4).

## Parity impact

- Items 51, 91, 92, 93, 101 -> **ported**. Tool count 86 -> **91**. Checklist header -> "91 of ~111 items
  ported".
- After this sub-batch, the ONLY remaining v8 items are Quick Fixes **Q1-Q9** (batch 7 Part 2 - composite
  macros chaining existing tools; their named-tool-vs-menu-construct design is deferred to that cycle).

## Out of scope

- Quick Fixes Q1-Q9 (batch 7 Part 2).
- A configurable expected-admins allow-list (kept as a constant for now; tunable later).
- Disabling/decrypting anything beyond the stated scoped actions.
