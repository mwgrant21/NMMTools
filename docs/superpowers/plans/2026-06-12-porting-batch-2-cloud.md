# Porting Batch 2: Cloud & Collaboration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port 8 v8 Cloud & Collaboration tools (menu 21-25, 28-30) into v9 template shape. This is the first batch that (a) hits live network services, (b) contains genuinely state-changing/interactive tools, and (c) flips the landing menu into category mode.

**Architecture:** Each tool = one file in `src\tools\cloud\` + one registry entry (`Category = 'Cloud'`). Hardened template per `docs\porting-playbook.md`. v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY behavioral reference.

**Tech Stack:** Windows PowerShell 5.1, Pester 5.7.1, PSScriptAnalyzer 1.25.0.

**Repo:** `C:\Users\IT\Desktop\NMMToolkit`, work on branch `port/batch-2-cloud`.

**Standing rules (every task):** PS 5.1 only (no ternary/`??`/`&&`; never assign `$input`/`$matches`). **ASCII-only source** (use `-` not em-dash; `tests\encoding.tests.ps1` enforces it). UTF-8 BOM + trailing newline. `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`. Read `docs\porting-playbook.md` before porting. Tests `template.tests.ps1` + `registry.tests.ps1` enforce compliance automatically. Existing 15 diagnostics ports in `src\tools\diagnostics\` are style reference. Suite starts at 59/59.

## Decisions already made (with Matt) — do not re-litigate

- **Tool 26 (Credential Manager Cleanup): RETIRED from this batch.** Its capability (clear Office/M365 creds via `cmdkey`) folds into tool 60 when batch 6 ports it. Do NOT port 26 here. Record in parity checklist as "consolidated -> tool 60 (batch 6)".
- **Tool 27 (MFA Status): RETIRED.** It is a stub reading the same `HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork` key that tool 30 reads; tool 30 is a strict superset. Tool 30 absorbs the MFA framing (add `mfa` tag + mention in description). Record in parity checklist as "consolidated -> tool 30 (windows-hello)".
- **Tool 24 (Teams Cache Clear): EXTENDED to classic + New Teams**, with a confirm-before-kill gate (v8 killed Teams with no confirmation - that gap is closed).

## New-this-batch conventions (network + interactive)

1. **Network calls need a timeout.** `Test-NetConnection` has NO timeout parameter and blocks ~20s per unreachable host. For TCP reachability use a `System.Net.Sockets.TcpClient` + `BeginConnect`/`WaitOne(<ms>)` helper with an explicit timeout (e.g. 3000 ms), nested as a private function inside the tool that needs it. Unreachable endpoints degrade to a `Warning` summary - never a hang or unhandled `Failed`. (Mirrors `Get-SecurityAnalysis` / `Test-NetworkConnectivity` from batch 1.)
2. **Interactive multi-action v8 tools** (Office repair, OneDrive) become a guided sequence via `Read-ToolChoice` with silent-safe defaults. Under `-Silent` the tool takes its safest meaningful action; destructive sub-actions (OneDrive `/reset`, credential delete) default to skip/No.
3. **Disruptive tools** (`Risk='Disruptive'`: OneDrive reset, Teams kill) are refused under `-Silent` without `-Force` by the dispatcher automatically - rely on that, and always gate the destructive step behind `Read-ToolChoice -Default 'No'` for interactive runs too.
4. **Long-running external repair processes** (OfficeC2RClient): launch without `-Wait` (fire-and-forget) and report "launched", rather than blocking the toolkit. v8 used `-Wait`; the v9 port deliberately does not, to avoid hanging the session.

---

## Registry entries

Append to the Tools array in `src\registry\tools.psd1`, format identical to existing entries. ALL use `Category = 'Cloud'`. Adjust Description/Tags to actual v8 behavior - report any adjustment.

| Id | LegacyId | Name | Function | Admin | Silent | Risk | Description | Tags |
|---|---|---|---|---|---|---|---|---|
| azure-ad-health | 21 | Azure AD Health Check | Get-AzureADHealthCheck | $false | $true | ReadOnly | Entra/Azure AD + domain join state from dsregcmd (AzureAdJoined, DomainJoined, DeviceId) | azuread,entra,join,dsregcmd |
| office-repair | 22 | Office 365 Health and Repair | Repair-Office365 | $false | $true | Modifies | Triggers Office Click-to-Run update/repair and optionally clears cached Office credentials | office,m365,repair,clicktorun |
| onedrive-repair | 23 | OneDrive Health and Reset | Repair-OneDriveClient | $false | $true | Disruptive | Restarts OneDrive, or resets it (/reset wipes the local sync database - full re-sync) | onedrive,sync,reset,restart |
| teams-cache | 24 | Teams Cache Clear and Reset | Clear-TeamsCache | $false | $true | Disruptive | Clears classic + New Teams cache after closing Teams (drops active calls) | teams,cache,reset,newteams |
| m365-connectivity | 25 | M365 Connectivity Test | Test-M365Connectivity | $false | $true | ReadOnly | TCP reachability (timeout-bounded) to login.microsoftonline.com, outlook, onedrive, teams | m365,connectivity,network,endpoints |
| group-policy-update | 28 | Group Policy Update | Update-GroupPolicy | $false | $true | Modifies | Runs gpupdate /force (user policy always; machine policy needs admin + domain) | gpupdate,grouppolicy,gpo,domain |
| intune-health | 29 | Intune/MDM Health Check | Get-IntuneHealthCheck | $false | $true | ReadOnly | MDM enrollment status from HKLM Enrollments (UPN, provider); notes if access is restricted | intune,mdm,enrollment,management |
| windows-hello | 30 | Windows Hello / MFA Status | Get-WindowsHelloStatus | $false | $true | ReadOnly | Windows Hello / Passport-for-Work policy and biometric device status (covers MFA-readiness check) | hello,mfa,biometric,passport |

**Naming notes:** `Reset-OneDrive` -> `Repair-OneDriveClient` (approved verb `Repair`; `Reset-` is approved too but the tool both restarts and resets, so `Repair` is the honest umbrella; keep `reset`/`onedrive` in tags for search). All other function names already use approved verbs - keep them. `windows-hello` carries LegacyId 30 only; retired tool 27 is recorded in the parity checklist, not the registry.

---

## Per-tool porting notes (read the v8 source, then apply)

v8 line numbers (each ends at the next `function`): Get-AzureADHealthCheck 1151, Repair-Office365 1169, Reset-OneDrive 1222, Clear-TeamsCache 1269, Test-M365Connectivity 1315, Update-GroupPolicy 1413, Get-IntuneHealthCheck 1430, Get-WindowsHelloStatus 1453.

- **azure-ad-health (21):** `dsregcmd /status` piped through `Select-String` for AzureAdJoined/DomainJoined/WorkplaceJoined/DeviceId. Read-only, offline-valid (no network). Report the join state lines at Detail, a one-line verdict summary (e.g. "Azure AD joined; not domain joined").
- **office-repair (22):** v8 reads Office install from registry, then a menu: option 1 runs `OfficeC2RClient.exe /update user` (v8 mislabels this "Quick Repair" - it is the updater; describe honestly), option 2 clears `cmdkey` entries matching `MicrosoftOffice`. v9: `Read-ToolChoice` to pick "update/repair Office", "clear Office credentials", or "skip"; silent default = run the update/repair (the primary "health and repair" intent). Launch OfficeC2RClient WITHOUT `-Wait`. Credential clear defaults to No under silent. Risk Modifies. The C2R path may not exist -> guard with `Test-Path`, report "Office Click-to-Run not found" as Warning.
- **onedrive-repair (23):** v8 menu: reset (`OneDrive.exe /reset`, wipes sync DB) vs restart. v9: `Read-ToolChoice -Prompt 'Reset (full resync) or just Restart?' -Choices @('Restart','Reset') -Default 'Restart'`. Reset path emits a Warning that full re-sync follows. `Risk='Disruptive'` (so `-Silent` without `-Force` is refused by the dispatcher). Guard the OneDrive.exe path with `Test-Path`.
- **teams-cache (24):** EXTENDED. Close both `Teams` and `ms-teams` processes; clear classic paths (`$env:APPDATA\Microsoft\Teams\{Cache,blob_storage,databases,GPUcache}`) AND New Teams package cache (`$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache` and `...\LocalState` cache subfolders - verify exact subpaths against what exists; only remove cache-like folders, never the whole package dir). Gate the whole destructive sequence behind `Read-ToolChoice -Prompt 'Close Teams and clear its cache now?' -Default 'No' -Silent:$Silent`. `Risk='Disruptive'`. Report which Teams variants were found/cleared and MB freed if measurable. Restart classic Teams via Update.exe only if classic was present.
- **m365-connectivity (25):** Replace `Test-NetConnection` with a nested `Test-TcpEndpoint` private function using `System.Net.Sockets.TcpClient` + `BeginConnect` + `WaitOne(3000)` (3s timeout) + cleanup. Four endpoints (login.microsoftonline.com, outlook.office365.com, onedrive.live.com, teams.microsoft.com), all port 443. Per-endpoint reachable/unreachable at Detail; any unreachable -> overall `Warning`; all reachable -> `Success`. ReadOnly.
- **group-policy-update (28):** `gpupdate /force` captured via `& gpupdate /force 2>&1` (mind PS 5.1: native stderr - capture into a variable, do not `2>&1` into the error stream awkwardly; use call operator and `$LASTEXITCODE`). Precheck `(Get-CimInstance Win32_OperatingSystem)`/domain via `(Get-CimInstance Win32_ComputerSystem).PartOfDomain` and `$script:IsAdmin`: if not admin, note machine policy will be skipped (user policy still applies); if not domain-joined, note only local policy applies. Degrade gracefully - never `Failed` just because a DC is unreachable; report the gpupdate output and a Warning. Risk Modifies.
- **intune-health (29):** `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Enrollments\*'` where `ProviderID -like '*MS DM Server*'`, report UPN. Non-admin may not read the key -> if the enumeration throws or returns empty AND we cannot confirm, report "Unable to determine enrollment (may require admin)" as a Detail/Warning rather than a definitive "not enrolled". ReadOnly.
- **windows-hello (30):** `Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'` (policy presence) + `Get-PnpDevice -Class Biometric`. Report policy state and each biometric device (FriendlyName + Status). Summary covers Hello/MFA readiness. Absorbs retired tool 27. ReadOnly.

**Porting procedure per tool** (same as batch 1): read v8 -> write `src\tools\cloud\<Function>.ps1` in template shape (`New-ToolRun -Id` matches registry Id) -> append registry entry -> build green + full suite green -> smoke per safety rules -> commit.

**SMOKE SAFETY:**
- SAFE to run `-Silent`: azure-ad-health, m365-connectivity (really probes - fine), intune-health, windows-hello. These are ReadOnly.
- group-policy-update: `gpupdate /force` DOES refresh policy. Acceptable to smoke ONCE on this dev machine (it is benign here) - or smoke and report. Use judgment; if unsure, verify via build+template tests only and note it.
- office-repair, onedrive-repair, teams-cache: DO NOT run the destructive paths. office-repair/onedrive-repair are Modifies/Disruptive; teams-cache would close Teams. Verify these via build + template/parse tests only. You MAY smoke them `-Silent` WITHOUT `-Force` to confirm the dispatcher REFUSES the Disruptive ones (exit 1) and that office-repair's silent default path is wired (but do NOT let it actually launch OfficeC2RClient or delete creds - if smoking would trigger a real action, skip and verify by reading).

---

### Task 1 (sub-batch 2.1): read-only inspection tools
**Tools:** azure-ad-health (21), intune-health (29), windows-hello (30).
All ReadOnly, no network, no prompts. Smoke all three `-Silent` (exit 0). Commit `feat: port cloud batch 2.1 (azure-ad-health, intune-health, windows-hello)`.

### Task 2 (sub-batch 2.2): network + policy tools
**Tools:** m365-connectivity (25), group-policy-update (28).
m365-connectivity MUST use the timeout-bounded TcpClient helper (no `Test-NetConnection`). group-policy-update needs admin/domain prechecks + graceful degradation. Smoke m365-connectivity `-Silent` (exit 0; quote per-endpoint results). group-policy-update: smoke once or verify per safety note. Commit `feat: port cloud batch 2.2 (m365-connectivity, group-policy-update)`.

### Task 3 (sub-batch 2.3): interactive state-changing tools
**Tools:** office-repair (22), onedrive-repair (23), teams-cache (24).
Read-ToolChoice with silent-safe defaults; Disruptive ones (23, 24) marked `Risk='Disruptive'`. Verify via build + template tests + reading; smoke ONLY the non-destructive confirmations (e.g. dispatcher refusal of Disruptive under `-Silent` no-`-Force`). Commit `feat: port cloud batch 2.3 (office-repair, onedrive-repair, teams-cache)`.

---

### Task 4: Batch close-out
- [ ] **Step 1:** Build green + full suite green. `dist\NMMTools.ps1 -ListTools` shows **31 tools** (23 diagnostics + 8 cloud); confirm the 8 cloud entries with correct Risk/Admin/Silent flags.
- [ ] **Step 2: Category-mode transition check (FIRST time this activates).** With 2 categories and 31 tools, the landing menu must now be CATEGORY mode (letters). Scripted-stdin smoke (pipe "X" into a dot-sourced Start-ConsoleMenu with the real registry): confirm it shows two category letters (e.g. `A. Cloud (8 tools)`, `B. Diagnostics (23 tools)`), NOT the flat list. Then confirm a legacy tool number still runs directly from the landing prompt (pipe "21\n\nX" - azure-ad-health runs) and a category letter drills in (pipe "a\n\nX" - shows the Cloud tool list). Quote both.
- [ ] **Step 3:** Update `docs\parity-checklist.md`: mark 21-25, 28-30 as `ported (batch 2)` with v9 ids; mark 26 as `consolidated -> tool 60 (batch 6)`; mark 27 as `consolidated -> tool 30 (windows-hello)`. Commit `docs: batch 2 complete - parity checklist (31/106 ported, 26+27 consolidated)`.
- [ ] **Step 4:** Final whole-batch review, then merge to master.

---

## After this batch
Remaining: batch 3 (Advanced System Repair - DISM/SFC/driver removal; high-risk, several Disruptive), 4 (Laptop/Mobile - lots of network: WiFi/VPN/Bluetooth), 5 (Browser), 6 (Common User Issues incl. the tool 60 credential merge), 7 (Security/Domain + Quick Fixes). See `docs\parity-checklist.md`.
