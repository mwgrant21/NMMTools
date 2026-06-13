# Porting Batch 3: Advanced System Repair — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port 16 v8 Advanced System Repair tools into v9, enhance the already-shipped Office tool (tool 22) to absorb tool 99, and retire tool 37. This is the HIGHEST-RISK batch: DISM/SFC/ChkDsk system repair, irreversible deletions (Windows.old, Adobe), a break-glass Win11 unlock, and long-running operations.

**Architecture:** Each tool = one file in `src\tools\repair\` + one registry entry (`Category = 'Repair'`). Hardened template per `docs\porting-playbook.md`. v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY behavioral reference.

**Repo:** `C:\Users\IT\Desktop\NMMToolkit`, branch `port/batch-3-repair`.

**USAGE MODEL (decisive for this batch):** Run INTERACTIVELY by a technician at the keyboard (currently Matt, usually sole operator). The toolkit elevates at launch, so admin is available in normal interactive use. Design priority = the interactive experience: clear prompts, confirm gates, honest live status. `-Silent` only needs to be SAFE (Disruptive tools refuse without `-Force`; destructive prompts default to safe). Do NOT contort repair defaults to "act under silent" - full silent automation is a future PDQ concern, not now.

**Standing rules (every task):** PS 5.1 only (no ternary/`??`/`&&`; never assign `$input`/`$matches`). **ASCII-only source** (`-` not em-dash; `tests\encoding.tests.ps1` fails the build on any non-ASCII byte). UTF-8 BOM + trailing newline. `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`. Read `docs\porting-playbook.md` first. Template/registry/encoding tests enforce compliance. The 31 prior ports are style reference. Suite starts 59/59.

## Decisions already made (with Matt) - do not re-litigate
- **Tool 37: RETIRED.** Covered by tool 20 (uptime, shipped) + tool 94 (pending-reboot, 5 sources, shipped). Do NOT port. Parity checklist: `consolidated -> tools 20 + 94`.
- **Tool 99: MERGED into tool 22 (enhance the existing `src\tools\cloud\Repair-Office365.ps1`).** Add two choices: 'SilentForcedUpdate' (`/update user displaylevel=false forceappshutdown=true`) and 'FullRepair' (`/scenario RepairAll /displaylevel True /shutdownapps True /forceappshutdown True` - the genuine repair neither tool did before). Parity checklist: 99 `consolidated -> tool 22`.
- **Tool 73: HONEST RENAME.** v8 did NO DDU, NO Safe Mode, NO driver removal - it only disables/re-enables the display adapter. Port that truthfully as `Reset-DisplayAdapter` / "Reset Display Adapter". Keep tags ddu/display/gpu so searches still land. Risk Disruptive (momentary black screen).
- **Tool 88: FULL TOOL, break-glass.** Port the unlock+upgrade, but Disruptive/interactive-only with a TYPED confirm and an explicit warning that it removes version-lock GPO keys and stages a major upgrade that can reboot.
- **Tool 89 (Adobe): KEEP full aggressive removal** (it exists for a real reason). Strong typed confirm + warning it clears Adobe user data (%APPDATA%/%LOCALAPPDATA%\Adobe - Lightroom catalogs, PS presets), but do NOT water down the removal.

## New-this-batch conventions
1. **Long-running ops run SYNCHRONOUSLY and capture the REAL exit code.** v8 ran DISM/SFC/ChkDsk as bare calls and reported success regardless of outcome. v9 MUST capture `$LASTEXITCODE` (or `Start-Process -Wait -PassThru` `.ExitCode`) and map: 0 -> Success; DISM/SFC nonzero or "found corruption" -> Warning/Failed per the tool; report the true result. The tech is watching - tell them what actually happened.
2. **Destructive deletions: scoped paths + typed confirm.** Every `Remove-Item`/`rmdir`/DISM-reset that destroys data (Windows.old, Adobe, deep-cleanup Full tier) gets: (a) paths built from well-known env vars with `Test-Path` guards (never a bare variable that could be empty -> root); (b) a `Read-ToolChoice` typed-confirm gate (e.g. Default 'No', or a "type REMOVE to proceed" pattern via `Read-ToolChoice -Choices @('REMOVE','Cancel') -Default 'Cancel'`); (c) `Risk='Disruptive'` so `-Silent` without `-Force` refuses.
3. **Network/download ops** (PS7 install, Win11 assistant, Adobe cleaner, OEM updaters) need an `-ErrorAction`/try-catch guard so a failed/slow download degrades to a Warning, not an unhandled crash. Long downloads use `Start-Process -Wait -PassThru` with exit-code capture.
4. **Admin:** set `RequiresAdmin = $true` for every tool that needs elevation (most of them). The dispatcher refuses non-admin `-Silent`; interactively the launch elevation covers it.
5. **Reboot-affecting tools** (ChkDsk /F/R schedules boot-time; winsock reset needs reboot; Win11 upgrade reboots) must clearly report that a reboot is required/scheduled in the summary.

---

## Registry entries

Append to `src\registry\tools.psd1`, format identical to existing. ALL `Category = 'Repair'`. Adjust Description/Tags to v8 reality (report adjustments).

| Id | LegacyId | Name | Function | Admin | Silent | Risk | Description | Tags |
|---|---|---|---|---|---|---|---|---|
| dism-repair | 31 | DISM System Image Repair | Invoke-DISMRepair | $true | $true | Modifies | DISM CheckHealth/ScanHealth, then optional RestoreHealth (repairs the component store; may contact WU) | dism,image,restorehealth,corruption |
| sfc-repair | 32 | System File Checker | Invoke-SFCRepair | $true | $true | Modifies | sfc /scannow - scans and repairs protected system files from the local cache | sfc,scannow,systemfiles,corruption |
| chkdsk-repair | 33 | Check Disk | Invoke-ChkDskRepair | $true | $true | Disruptive | chkdsk scan, or /F /R (schedules a boot-time check on the system drive) | chkdsk,disk,filesystem,badsectors |
| deep-disk-cleanup | 34 | Deep Disk Cleanup | Invoke-DeepDiskCleanup | $true | $true | Disruptive | Tiered cleanup: temp/WU cache/CBS/WER (Conservative), plus Windows.old (Full tier, typed confirm) | cleanup,disk,space,windowsold |
| oem-driver-update | 35 | OEM Driver/Firmware Update | Invoke-OEMDriverUpdate | $true | $true | Modifies | Launches the vendor updater (Dell DCU / Lenovo Vantage / HP) to scan for driver/firmware updates | driver,firmware,oem,dell,lenovo,hp |
| repair-suite | 36 | Complete Repair Suite | Invoke-SystemRepairSuite | $true | $true | Disruptive | One-click DISM RestoreHealth + SFC + conservative cleanup, in sequence | suite,dism,sfc,cleanup,repair |
| windows-update-repair | 65 | Local Windows Update Repair | Repair-WindowsUpdateLocal | $true | $true | Disruptive | Resets WU components: stops services, renames SoftwareDistribution/Catroot2, re-registers DLLs | windowsupdate,wuauserv,softwaredistribution,reset |
| driver-integrity-scan | 72 | Driver Integrity Scan | Get-DriverIntegrityScan | $true | $true | ReadOnly | Inventories installed drivers; flags duplicates, unknown publishers, and stale (3yr+) drivers | driver,integrity,scan,inventory |
| display-adapter-reset | 73 | Reset Display Adapter | Reset-DisplayAdapter | $true | $true | Disruptive | Disables and re-enables the display adapter (brief black screen) to clear display glitches | display,gpu,adapter,ddu |
| bsod-crash-parser | 75 | BSOD Crash Dump Parser | Get-BSODCrashDumpParser | $false | $true | ReadOnly | Parses minidumps for bug-check codes and likely causes; optional report export | bsod,crashdump,minidump,bugcheck |
| powershell7-install | 87 | Install / Upgrade PowerShell 7 | Install-PowerShell7 | $true | $true | Modifies | Installs/updates PowerShell 7 via winget or GitHub MSI (also enables PSRemoting) | powershell7,pwsh,install,winget |
| win11-feature-unlock | 88 | Win11 Feature Update Unlock | Invoke-Win11FeatureUpdateUnlock | $true | $true | Disruptive | BREAK-GLASS: removes version-lock GPO keys and stages a Win11 feature upgrade (can reboot) | win11,featureupdate,unlock,upgrade |
| adobe-cc-removal | 89 | Adobe Creative Cloud Force Removal | Remove-AdobeCC | $true | $true | Disruptive | Force-removes all Adobe apps, services, tasks, files, and registry (clears Adobe user data) | adobe,creativecloud,removal,uninstall |
| windows-activation | 90 | Windows Activation Status & Repair | Repair-WindowsActivation | $true | $true | Modifies | Reports license/activation status; attempts online activation (slmgr /ato) if unlicensed | activation,license,slmgr,kms |
| proxy-reset | 100 | Proxy / Internet Settings Repair | Repair-ProxySettings | $true | $true | Modifies | Resets WinHTTP/WinINET proxy, clears PAC, flushes DNS, resets Winsock (reboot to finish) | proxy,winhttp,winsock,internet |
| windows-old-removal | 102 | Remove Windows.old | Remove-WindowsOld | $true | $true | Disruptive | Removes Windows.old via DISM /StartComponentCleanup /ResetBase (ends OS rollback - irreversible) | windowsold,rollback,dism,cleanup |

**Verbs:** all approved (Invoke/Repair/Get/Reset/Install/Remove). `display-adapter-reset` Function is `Reset-DisplayAdapter`.

---

## Per-tool porting notes (read the v8 source, then apply)

v8 lines: DISM 1484, SFC 1521, ChkDsk 1552, DiskCleanup 10197, OEM 2109, RepairSuite 2185, WU-Local 8846, DriverIntegrity 3319, DisplayDriver 3489, BSOD 3727, PS7 10377, Win11Unlock 10495, Adobe 10620, Activation 10767, Proxy 11614, WindowsOld 11671. (Office99 11582 - for the tool-22 merge.)

- **dism-repair (31):** CheckHealth + ScanHealth (read-only probes) always; then `Read-ToolChoice -Prompt 'Run full RestoreHealth repair? (10-20 min)' -Default 'No' -Silent:$Silent` before RestoreHealth. Run each DISM phase capturing exit code; report the REAL result (DISM exit 0 = healthy/repaired; nonzero = report Warning/Failed with the code). Long-running, synchronous.
- **sfc-repair (32):** `sfc /scannow` synchronous; capture exit code AND parse the tail of output ("found corrupt files and repaired"/"could not fix"/"no integrity violations"). Map to Success/Warning. Long-running.
- **chkdsk-repair (33):** prompt drive letter (default C) and mode via `Read-ToolChoice` (Scan vs Fix). Scan = `chkdsk C:` (read-only). Fix = `chkdsk C: /F /R` -> on the system drive this SCHEDULES a boot-time check; report "scheduled at next reboot" clearly. Risk Disruptive. Default mode = Scan (safe). Confirm before Fix.
- **deep-disk-cleanup (34):** tiered. Conservative tier (temp, Windows\Temp, Prefetch, SoftwareDistribution\Download [stop/restart wuauserv+bits], CBS logs, WER ReportQueue/ReportArchive) = the silent-safe default. Full tier ADDS DeliveryOptimization + Windows.old removal (`rmdir /s /q C:\Windows.old`, DISM /SPSuperseded fallback) and REQUIRES a typed confirm (`Read-ToolChoice -Choices @('CONFIRM','Cancel') -Default 'Cancel'`). Every path Test-Path-guarded. Measure + report MB freed. Risk Disruptive.
- **oem-driver-update (35):** detect `Win32_ComputerSystem.Manufacturer`; branch Dell (dcu-cli /scan) / Lenovo (tvsu /CM) / HP; hard-coded vendor exe paths guarded with Test-Path; if absent, report the vendor download URL as a Detail note (don't fail). `Read-ToolChoice` before launching. `Start-Process -Wait -PassThru`, capture exit. Network (vendor servers). Risk Modifies.
- **repair-suite (36):** PORT LAST (depends on 31/32/34). One confirm: `Read-ToolChoice -Prompt 'Run full repair suite (DISM RestoreHealth + SFC + conservative cleanup, 20-30 min)?' -Default 'No' -Silent:$Silent`. Then run the three operations IN SEQUENCE. To avoid divergence and double-prompting: factor the three core operations (DISM RestoreHealth runner, SFC runner, conservative-cleanup runner) into SHARED helper functions in a new `src\core\07-repair-helpers.ps1`, and have BOTH the individual tools (31/32/34) AND the suite call those helpers. The suite calls them directly (no sub-prompts) after its single confirm; the individual tools wrap them with their own prompts/reporting. (Core helpers are NOT tool files, so they're exempt from the registry-mapping test - verify the suite passes.) Report a combined per-step status. Risk Disruptive, long-running.
- **windows-update-repair (65):** stop wuauserv/cryptSvc/bits/msiserver; rename SoftwareDistribution -> .old and Catroot2 -> .old (Test-Path/guard; if a prior .old exists, handle); re-register the 36 DLLs via regsvr32 /s; restart services. Confirm before acting (v8 didn't). Note: renames (doesn't delete); the .old folders persist. Risk Disruptive. Report what was reset.
- **driver-integrity-scan (72):** `Get-WindowsDriver -Online -All`; group for duplicates; flag empty/non-allowlisted publishers (Microsoft|Intel|AMD|NVIDIA|Realtek|Qualcomm) and 3yr+ stale; optional report export to Desktop via `[Environment]::GetFolderPath('Desktop')`. ReadOnly. Long-ish (1-3 min). RequiresAdmin (Get-WindowsDriver).
- **display-adapter-reset (73):** RENAMED. `Get-PnpDevice -Class Display`; confirm via `Read-ToolChoice -Prompt 'Reset display adapter? (screen will flicker/black briefly)' -Default 'No' -Silent:$Silent`; Disable-PnpDevice -Confirm:$false each, sleep, Enable-PnpDevice -Confirm:$false each. Report adapters reset. Honest summary: "display adapter reset (driver store unchanged)". Risk Disruptive. NO Safe Mode, NO reboot, NO driver removal.
- **bsod-crash-parser (75):** enumerate `$env:SystemRoot\Minidump\*.dmp`; read first 4096 bytes, regex bug-check codes, map known codes; optional report export to Desktop. ReadOnly. If no dumps, Success "no crash dumps found". RequiresAdmin $false (note dump reads may need admin - degrade to a note if access denied).
- **powershell7-install (87):** if `$PSVersionTable.PSVersion.Major -ge 7` report already-installed Success and return. Else winget primary (`winget install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements`), GitHub MSI fallback (Invoke-RestMethod latest release -> download -> msiexec /qn). Capture exit. Warn that it enables PSRemoting. Confirm before install. Network (guard downloads). Risk Modifies.
- **win11-feature-unlock (88):** BREAK-GLASS. First report current version + version-lock state (the safe diagnostic part). Then a STRONG gate: `Read-ToolChoice -Prompt 'This removes Windows Update version-lock GPO keys and stages a Win11 upgrade that can reboot. Type UNLOCK to proceed' -Choices @('UNLOCK','Cancel') -Default 'Cancel' -Silent:$Silent`. Only on UNLOCK: remove the policy keys (TargetReleaseVersion etc.), gpupdate /force, flush WU cache, download+run the Win11 Installation Assistant (`/QuietInstall /SkipEULA /NoRestartUI`). Report that a major upgrade is staged and the machine will reboot. Risk Disruptive, network, long-running.
- **adobe-cc-removal (89):** KEEP FULL removal. Strong gate: `Read-ToolChoice -Prompt 'Force-remove ALL Adobe software, settings, and user data (Lightroom catalogs, PS presets under %APPDATA%\\Adobe)? Type REMOVE to proceed' -Choices @('REMOVE','Cancel') -Default 'Cancel' -Silent:$Silent`. Then the v8 7-step removal: stop ~16 processes, stop+delete 6 services (sc.exe delete), CC Uninstaller, download+run Adobe Cleaner Tool (--removeAll=1, guard download), Remove-Item the Adobe paths (ProgramFiles/ProgramFiles(x86)/ProgramData/LOCALAPPDATA/APPDATA/CommonProgramFiles[(x86)]\Adobe - all Test-Path guarded), registry removal (HKLM/WOW6432Node/HKCU Adobe + Uninstall entries matching ^Adobe), Unregister-ScheduledTask *Adobe*. Note in the summary it removes the RUNNING user's Adobe profile data (not all profiles). Risk Disruptive, network (cleaner download).
- **windows-activation (90):** `Get-CimInstance SoftwareLicensingProduct` (PartialProductKey present = a real license row) -> report LicenseStatus, grace, KMS info. If unlicensed: `cscript //nologo slmgr.vbs /ato` to attempt activation; re-query to confirm. Network (KMS/MS). Risk Modifies. RequiresAdmin.
- **proxy-reset (100):** confirm first (warns connectivity drops until reboot): `netsh winhttp reset proxy`; clear HKCU WinINET proxy (ProxyEnable=0, remove ProxyServer/ProxyOverride/AutoConfigURL); `ipconfig /flushdns`; `netsh winsock reset` (needs reboot). Report "Winsock reset - REBOOT required". WARNING: in a PAC/WPAD-managed env this breaks proxy until GPO re-applies - note that. Risk Modifies. RequiresAdmin.
- **windows-old-removal (102):** check `C:\Windows.old` exists (else Success "no Windows.old present"); report size; STRONG gate: `Read-ToolChoice -Prompt 'Permanently remove Windows.old? This ENDS the ability to roll back the previous Windows. Type CONFIRM' -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent`; then `dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase` via Start-Process -Wait -PassThru, capture exit, report. Risk Disruptive, long-running.

**Tool-22 enhancement (99 merge) - edits the EXISTING `src\tools\cloud\Repair-Office365.ps1`:** add two choices to its Read-ToolChoice: 'SilentForcedUpdate' (`OfficeC2RClient.exe /update user displaylevel=false forceappshutdown=true`) and 'FullRepair' (`OfficeC2RClient.exe /scenario RepairAll /displaylevel True /shutdownapps True /forceappshutdown True`). Keep existing UpdateRepair/ClearCreds/Skip. Update the registry Description for office-repair to mention "update, full online repair, or clear credentials". Since FullRepair/SilentForcedUpdate force-close Office, office-repair stays Risk='Disruptive' (already reclassified in batch 2). Update the switch default arm. This does NOT create a new tool; 99 is retired.

**Porting procedure per tool** (as prior batches): read v8 -> write `src\tools\repair\<Function>.ps1` template-shaped (`New-ToolRun -Id` matches registry Id) -> append registry entry -> build green + suite green -> verify per safety -> commit.

**SMOKE SAFETY - this batch is dangerous. Verify destructive tools by READING + build/parse, NOT by running their destructive paths.**
- SAFE to run `-Silent`: driver-integrity-scan, bsod-crash-parser (ReadOnly). windows-activation `-Silent` reports status then attempts /ato (benign if already activated - judge). 
- DISM/SFC are long but non-destructive to data; you MAY run dism-repair/sfc-repair `-Silent` (silent default skips RestoreHealth for DISM; SFC scannow will run ~10min - optional, can verify by reading + build instead to save time). State which.
- Disruptive tools (chkdsk Fix, deep-cleanup Full, repair-suite, windows-update-repair, display-adapter-reset, win11-feature-unlock, adobe-cc-removal, windows-old-removal): `-Silent` WITHOUT -Force must REFUSE (exit 1) - that's the proof. NEVER run with -Force. NEVER trigger chkdsk /F, the Win11 upgrade, Adobe removal, Windows.old removal, WU folder rename, or the display toggle during testing.
- oem-driver-update: do NOT launch a vendor updater; verify by reading + build (and confirm it refuses or no-ops cleanly if the vendor exe is absent).
- powershell7-install: PS7 may already be installed (Major>=7 -> Success return). If not installed, do NOT actually install during testing - verify by reading + the already-installed/return path.

---

### Task 1 (sub-batch 3.1): read-only / light tools
**Tools:** driver-integrity-scan (72), bsod-crash-parser (75), windows-activation (90). Smoke 72 + 75 `-Silent` (exit 0). 90 reports status (benign). Commit `feat: port repair batch 3.1 (driver-integrity-scan, bsod-crash-parser, windows-activation)`.

### Task 2 (sub-batch 3.2): heavy repair (DISM/SFC/ChkDsk)
**Tools:** dism-repair (31), sfc-repair (32), chkdsk-repair (33). Establish the long-running-synchronous-with-real-exit-status pattern. Verify chkdsk Fix refuses silent-no-force; DISM/SFC verify by reading+build (or optional long smoke). Commit `feat: port repair batch 3.2 (dism-repair, sfc-repair, chkdsk-repair)`.

### Task 3 (sub-batch 3.3): destructive cleanup & removal - HIGHEST DELETION RISK
**Tools:** deep-disk-cleanup (34), windows-old-removal (102), adobe-cc-removal (89). Every Remove-Item scoped + Test-Path-guarded; typed-confirm gates; Risk Disruptive. Verify ALL by reading + build + refusal smoke (silent-no-force -> exit 1). DO NOT execute any deletion. Commit `feat: port repair batch 3.3 (deep-disk-cleanup, windows-old-removal, adobe-cc-removal)`.

### Task 4 (sub-batch 3.4): install / update / network
**Tools:** powershell7-install (87), win11-feature-unlock (88, break-glass typed-confirm), oem-driver-update (35). Network downloads guarded. Verify by reading + build + refusal smoke for 88; 87 via already-installed path; 35 via reading. Commit `feat: port repair batch 3.4 (powershell7-install, win11-feature-unlock, oem-driver-update)`.

### Task 5 (sub-batch 3.5): system config repair + the suite
**Tools:** windows-update-repair (65), proxy-reset (100), display-adapter-reset (73), repair-suite (36, PORT LAST - create `src\core\07-repair-helpers.ps1` shared helpers used by 31/32/34 and the suite). Refusal smokes for the Disruptive ones. The suite must build and its core helpers must not break the registry-mapping test. Commit `feat: port repair batch 3.5 (windows-update-repair, proxy-reset, display-adapter-reset, repair-suite)`.

### Task 6: Tool-22 enhancement (99 merge)
Enhance `src\tools\cloud\Repair-Office365.ps1`: add SilentForcedUpdate + FullRepair choices, update registry Description, switch default arm. Verify office-repair still refuses silent-no-force (Disruptive). Smoke `-Silent` -> Skip default path. Commit `feat: merge tool 99 into office-repair (add silent-forced + full online repair options)`.

### Task 7: Batch close-out
- [ ] Build green + full suite green. `-ListTools` shows **47 tools** (23 diag + 8 cloud + 16 repair). Quote the 16 Repair rows with Risk/Admin flags.
- [ ] Category-menu check: 3 categories now (A=Cloud, B=Diagnostics, C=Repair or alphabetical). Scripted-stdin smoke: landing shows 3 category letters with counts; a legacy number (e.g. 72) runs from landing; category C drills into the 16 repair tools. Quote.
- [ ] Update `docs\parity-checklist.md`: mark 31-36,65,72,73,75,87-90,100,102 `ported (batch 3)`; 37 `consolidated -> tools 20 + 94`; 99 `consolidated -> tool 22`. Commit `docs: batch 3 complete - parity checklist (47/106 ported)`.
- [ ] Final whole-batch review (focus: every destructive Remove-Item/DISM-reset is gated + scoped; long-running tools report real exit status; the suite/helpers refactor is clean). Then merge to master.

## After this batch
Remaining: 4 (Laptop/Mobile - network-heavy, reuse Test-TcpEndpoint), 5 (Browser), 6 (Common User Issues incl. tool 60 credential merge), 7 (Security/Domain + Quick Fixes). See `docs\parity-checklist.md`.
