# Porting Batch 4: Laptop & Mobile Computing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port 17 v8 Laptop & Mobile tools (menu 38-47, 62-64, 67-68, 70-71) into v9. Network-heavy; BitLocker is the highest-care tool; several v8 tools silently changed settings or killed apps with no confirm - v9 adds the gates.

**Architecture:** Each tool = one file in `src\tools\laptop\` + one registry entry (`Category = 'Laptop'`). Hardened template per `docs\porting-playbook.md`. v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference.

**Repo:** `C:\Users\IT\Desktop\NMMToolkit`, branch `port/batch-4-laptop`.

**USAGE MODEL (unchanged):** interactive tech at the keyboard (toolkit elevates at launch). Optimize the interactive experience; `-Silent` only needs to be SAFE. "Report + action-menu" tools: the read-only report always runs, then `Read-ToolChoice` offers actions with a SAFE default (Skip/None) so `-Silent` takes no action.

**Standing rules:** PS 5.1 (no ternary/`??`/`&&`; never assign `$input`/`$matches`). **ASCII-only source** (encoding test fails build on non-ASCII). UTF-8 BOM + trailing newline. `Import-Module Pester -MinimumVersion 5.0` before `Invoke-Pester`. Read `docs\porting-playbook.md` first. 47 prior ports are reference. Suite starts 59/59.

## Decisions already made (with Matt) - do not re-litigate
- **No consolidations this batch.** 67 (network-stack-reset) and 100 (proxy-reset, shipped) stay SEPARATE (different problem profiles, only winsock+flushdns overlap). 39 (wifi-diagnostics) and 70 (wifi-environment) stay SEPARATE (connection mgmt vs RF scan). 71 (travel-readiness) is a self-contained read-only pre-flight (does NOT orchestrate other tools - port inline, read-only).
- **BitLocker (42) recovery-key FILE backup: KEEP but HARDENED.** Loud warning before writing; save to a path the tech confirms via Read-ToolChoice/Read-Host (NOT auto-Desktop); restrict the file ACL to the current user (`icacls <file> /inheritance:r /grant:r "$env:USERNAME:F"`); prompt to delete after display. KEEP the Azure AD/Intune backup option (BackupToAAD-BitLockerKeyProtector) too. Never show the 48-digit key in the default status display (only the protector-ID GUID, like v8).
- **WiFi saved-password display (tool 47 option): KEEP with a warning** that it prints the password on screen (matters on shared/recorded sessions).

## New-this-batch conventions
1. **Report-then-action pattern:** every "report + menu" tool runs its ReadOnly report first (always), then `Read-ToolChoice -Choices @('None', <actions>) -Default 'None' -Silent:$Silent` (or the v8 action set with a safe default). `-Silent` -> 'None' -> report only, no action. Destructive actions (delete-all-profiles, kill-apps, BitLocker suspend, power-scheme overwrite) get an explicit secondary confirm even interactively.
2. **Add the confirm gates v8 LACKED:** tool 64 (sleep-hibernate) SILENTLY overwrote the power scheme in v8 - v9 must confirm first. Tool 41 (webcam-audio) killed Teams/Zoom/Skype/browsers with no warning - v9 confirms + lists what will be closed. Tool 39 delete-all-profiles needs a typed/explicit confirm.
3. **Network reachability uses the timeout-bounded TcpClient helper.** Tool 40 (vpn-health) does DNS + ping with no timeout (hangs if VPN up but internet down). REUSE the nested `Test-TcpEndpoint` pattern from `Test-M365Connectivity.ps1` (BeginConnect + WaitOne(3000) + finally dispose) for reachability checks instead of bare Test-Connection.
4. **Disruptive tools** (47 profile cleanup deletes all wifi creds; 67 stack reset cycles adapters + needs reboot) keep their typed gates ('RESET' for 67) and refuse `-Silent` without `-Force`.

---

## Registry entries

Append to `src\registry\tools.psd1`. ALL `Category = 'Laptop'`, `SilentCapable = $true`. Adjust Description/Tags to v8 reality (report adjustments).

| Id | LegacyId | Name | Function | Admin | Risk | Description | Tags |
|---|---|---|---|---|---|---|---|
| battery-health | 38 | Battery Health Check | Get-BatteryHealth | $false | ReadOnly | Battery design vs full-charge capacity, wear %, and a powercfg battery report | battery,health,wear,powercfg |
| wifi-diagnostics | 39 | Wi-Fi Diagnostics | Get-WiFiDiagnostics | $true | Modifies | Wi-Fi adapter/SSID/signal report; optional adapter restart or forget-network actions | wifi,wireless,adapter,signal |
| vpn-health | 40 | VPN Health and Connection | Test-VPNHealth | $false | Modifies | Windows VPN profile status + reachability (timeout-bounded); optional reconnect/disconnect | vpn,rasdial,connection,reachability |
| webcam-audio-test | 41 | Webcam and Audio Device Test | Test-WebcamAudio | $false | Modifies | Lists camera + sound devices; opens test apps; optional close-conflicting-apps (confirmed) | webcam,camera,audio,microphone |
| bitlocker-status | 42 | BitLocker Status and Recovery | Get-BitLockerStatus | $true | Modifies | BitLocker encryption/protection status; AAD/Intune or hardened file key backup; suspend/resume | bitlocker,encryption,recovery,key |
| power-management | 43 | Power Management and Plans | Get-PowerManagement | $true | Modifies | Active power plan + battery; optional plan switch or USB-selective-suspend change | power,powercfg,plan,battery |
| docking-displays | 44 | Docking Station and Displays | Get-DockingDisplays | $false | Modifies | Connected monitors; optional display topology switch (extend/clone/external/internal) | docking,display,monitor,displayswitch |
| bluetooth-devices | 45 | Bluetooth Device Management | Get-BluetoothDevices | $true | Modifies | Bluetooth adapter + paired device list; optional bthserv restart (drops BT briefly) | bluetooth,bthserv,pairing,wireless |
| storage-health | 46 | Storage Health (SSD/NVMe) | Get-StorageHealth | $true | Modifies | Physical disk health, wear, temperature; optional Optimize-Volume (TRIM) or online scan | storage,ssd,nvme,disk |
| network-profile-cleanup | 47 | Network Profile Cleanup | Clear-NetworkProfiles | $true | Disruptive | Lists saved Wi-Fi profiles; delete (typed confirm), show saved password (warned), or stack reset | wifi,profile,cleanup,credential |
| touchpad-keyboard | 62 | Touchpad and Keyboard Troubleshooter | Repair-TouchpadKeyboard | $true | Modifies | Re-enables errored HID touchpad/keyboard devices; optionally clears Filter/Sticky Keys | touchpad,keyboard,hid,input |
| thermal-health | 63 | Thermal and Fan Health Check | Get-ThermalHealth | $false | ReadOnly | CPU temperature, load, and throttling-risk snapshot from ACPI thermal zone | thermal,temperature,fan,cpu |
| sleep-hibernate | 64 | Sleep / Hibernate / Lid-Close Repair | Repair-SleepHibernate | $true | Modifies | Reports sleep states + wake blockers; optionally applies standard lid/sleep/hibernate timers (confirmed) | sleep,hibernate,lid,powercfg |
| network-stack-reset | 67 | Advanced Network Stack Deep Reset | Reset-NetworkStack | $true | Disruptive | Flush DNS + winsock + TCP/IP reset + cycle all active adapters (typed RESET; reboot to finish) | network,winsock,tcpip,reset |
| hotkey-fn | 68 | Input and Hotkey / Fn Key Check | Repair-HotkeyFnKeys | $true | Modifies | Checks OEM hotkey services (Lenovo/Dell/HP/Synaptics/ELAN); optionally starts/enables stopped ones | hotkey,fnkey,oem,service |
| wifi-environment | 70 | Wi-Fi Environment Snapshot | Get-WiFiEnvironment | $false | ReadOnly | Passive scan of nearby Wi-Fi networks (signal, channel, congestion) | wifi,scan,channel,environment |
| travel-readiness | 71 | Laptop Readiness for Travel | Test-LaptopTravelReadiness | $false | ReadOnly | Quick read-only pre-flight: disk space, battery wear, BitLocker, Wi-Fi adapter, VPN service presence | travel,readiness,preflight,laptop |

**Verbs** all approved (Get/Test/Clear/Repair/Reset). Note `webcam-audio-test`/`vpn-health` use `Test-`, `network-profile-cleanup` uses `Clear-`, `network-stack-reset` uses `Reset-`.

---

## Per-tool porting notes (read the v8 source, then apply)

v8 lines: BatteryHealth 2367, WiFiDiagnostics 2443, VPNHealth 2525, WebcamAudio 2628, BitLockerStatus 2711, PowerManagement 2907, DockingDisplays 2984, BluetoothDevices 3065, StorageHealth 3140, NetworkProfiles 3224, TouchpadKeyboard 8593, ThermalHealth 8680, SleepHibernate 8765, NetworkStack 11790, HotkeyFnKeys 11866, WiFiEnvironment 12065, TravelReadiness 12137.

- **battery-health (38):** Win32_Battery + `powercfg /batteryreport` (write to TEMP, report path); wear% calc. ReadOnly. Report-only (no action menu in v9 needed beyond the existing report). Note the HTML report location.
- **wifi-diagnostics (39):** netsh wlan show interfaces/profiles + Get-NetAdapter report. Actions via Read-ToolChoice (Default None): restart adapter (Restart-NetAdapter), forget current SSID, forget ALL (typed/explicit confirm - deletes all wifi creds), generate wlanreport. Modifies.
- **vpn-health (40):** Get-VpnConnection; if connected, reachability via the nested Test-TcpEndpoint helper (e.g. 8.8.8.8:53 or a name resolve guarded) instead of bare Test-Connection. Actions (Default None): reconnect (rasdial), disconnect, clear VPN phonebook (`$env:APPDATA\Microsoft\Network\Connections\Pbk\*` - scoped + confirm). Modifies.
- **webcam-audio-test (41):** list Win32_SoundDevice + camera PnP entities. Actions (Default None): open Camera app, open Sound Recorder, open Sound settings, CLOSE conflicting apps (Teams/Zoom/Skype/Chrome/Firefox/msedge) - this one CONFIRMS and LISTS what it will close (v8 killed silently). Modifies.
- **bitlocker-status (42):** Get-BitLockerVolume status (show protector TYPE + ID GUID only, NEVER the 48-digit key in status). Actions (Default None): (a) AAD/Intune backup (BackupToAAD-BitLockerKeyProtector, guard Get-Command), (b) HARDENED file backup - warn about plaintext, Read-ToolChoice/Read-Host for a save path (default a confirmed location, not auto-Desktop), write the key, then `icacls "<file>" /inheritance:r /grant:r "$env:USERNAME:F"`, then offer to delete it; (c) Suspend (Suspend-BitLocker -RebootCount 2, explicit confirm + drive), (d) Resume. Modifies. RequiresAdmin. NO Disable/Decrypt.
- **power-management (43):** powercfg /getactivescheme + /list + Win32_Battery. Actions (Default None): set High Performance / Balanced / Power Saver, show sleep timers, disable USB selective suspend. Modifies.
- **docking-displays (44):** WmiMonitorID report. Actions (Default None): DisplaySwitch /detect /extend /clone /external /internal, open display settings. external/internal can hide the active display - note in the choice text. Modifies.
- **bluetooth-devices (45):** Bluetooth PnP + device list. Actions (Default None): Restart-Service bthserv (confirm - drops BT input briefly), open BT settings. Modifies.
- **storage-health (46):** Get-PhysicalDisk + Get-StorageReliabilityCounter (temp/wear/power-on-hours) + Get-Volume report. Actions (Default None): Optimize-Volume C (TRIM/defrag, long), Repair-Volume -Scan all volumes (online chkdsk scan, long). Modifies.
- **network-profile-cleanup (47):** netsh wlan show profiles list. Actions: delete ALL (typed confirm - 'CONFIRM'), delete specific (name + secondary confirm), SHOW saved password (`netsh wlan show profile name=.. key=clear` - WARN it prints the password on screen, per Matt), stack reset (winsock+ip+flushdns). Risk Disruptive (refuses silent-no-force). Keep the password-display with warning.
- **touchpad-keyboard (62):** Get-PnpDevice HIDClass filtered to touchpad/keyboard in Error/Unknown; confirm then Enable-PnpDevice each; then offer to clear Filter/Sticky Keys (HKCU accessibility). Modifies. RequiresAdmin.
- **thermal-health (63):** MSAcpi_ThermalZoneTemperature (tenths-Kelvin -> Celsius, try/catch graceful if unavailable) + Get-Counter CPU load + Win32_Processor maxclock; throttling-risk verdict. ReadOnly.
- **sleep-hibernate (64):** powercfg /availablesleepstates + /requests report. THEN - WITH A CONFIRM (v8 did it silently!) - apply the standard lid/sleep/hibernate timers (the 7 powercfg setacvalueindex/setdcvalueindex lines + setactive). Optionally clear wake blockers (Audiosrv restart, confirmed). Modifies. RequiresAdmin.
- **network-stack-reset (67):** keep the typed 'RESET' gate. ipconfig flushdns; netsh winsock reset; netsh int ip reset; Disable-NetAdapter/Enable-NetAdapter on all Up adapters (the adapter cycle). Report 'reboot required'. Risk Disruptive. RequiresAdmin.
- **hotkey-fn (68):** Get-Service for the 6 OEM services; if any stopped + confirm: Start-Service + Set-Service Automatic. Read NumLock state; Fn-key BIOS advisory. Modifies. RequiresAdmin.
- **wifi-environment (70):** netsh wlan show networks mode=bssid passive scan; parse SSID/signal/channel; congestion flag (>10). ReadOnly.
- **travel-readiness (71):** inline read-only checks (disk space, battery wear, BitLocker ProtectionStatus, Wi-Fi adapter presence, VPN service presence) -> OK/Warning/Issue verdict. ReadOnly. Self-contained (do NOT call other tools).

**Porting procedure per tool** (as prior batches): read v8 -> write `src\tools\laptop\<Function>.ps1` template-shaped (`New-ToolRun -Id` matches registry Id; report-then-Read-ToolChoice for action tools) -> append registry entry -> build green + suite green -> smoke per safety -> commit.

**SMOKE SAFETY (non-elevated dev session):**
- SAFE to run `-Silent`: battery-health, thermal-health, wifi-environment, travel-readiness (ReadOnly, no admin). vpn-health (no admin; report + None default - does network reachability, fine). webcam-audio (no admin; report + None default - does NOT open/kill anything under -Silent). docking-displays (no admin; report + None).
- Admin-required tools (39,42,43,45,46,47,62,64,67,68): refuse under non-elevated -Silent (exit 1) - quote the refusal as proof. Verify their action LOGIC by reading.
- Disruptive (47,67): refuse silent-no-force (exit 1). NEVER run their destructive paths.
- For the report+action tools: under -Silent the Read-ToolChoice returns 'None' default -> report only, no action. Confirm by reading the default is safe.

---

### Task 1 (sub-batch 4.1): read-only diagnostics
**Tools:** battery-health (38), thermal-health (63), wifi-environment (70), travel-readiness (71). All ReadOnly, no admin. Smoke all four `-Silent` (exit 0), quote summaries. Commit `feat: port laptop batch 4.1 (battery-health, thermal-health, wifi-environment, travel-readiness)`.

### Task 2 (sub-batch 4.2): network/connectivity
**Tools:** wifi-diagnostics (39), vpn-health (40, REUSE Test-TcpEndpoint helper), network-profile-cleanup (47, Disruptive), network-stack-reset (67, Disruptive, typed RESET). vpn-health + report parts smoke; Disruptive ones refuse. Commit `feat: port laptop batch 4.2 (wifi-diagnostics, vpn-health, network-profile-cleanup, network-stack-reset)`.

### Task 3 (sub-batch 4.3): devices
**Tools:** webcam-audio-test (41, confirm before closing apps), bluetooth-devices (45), docking-displays (44), storage-health (46). Report + None-default actions. Commit `feat: port laptop batch 4.3 (webcam-audio-test, bluetooth-devices, docking-displays, storage-health)`.

### Task 4 (sub-batch 4.4): power/input
**Tools:** power-management (43), sleep-hibernate (64, ADD the confirm v8 lacked), touchpad-keyboard (62), hotkey-fn (68). Commit `feat: port laptop batch 4.4 (power-management, sleep-hibernate, touchpad-keyboard, hotkey-fn)`.

### Task 5 (sub-batch 4.5): BitLocker - the careful one
**Tool:** bitlocker-status (42). Hardened key file backup (warn + confirmed path + icacls ACL + prompt-to-delete), AAD/Intune backup, suspend (confirm)/resume; status display never shows the 48-digit key. Verify by reading + refusal smoke (admin-gated). Commit `feat: port laptop batch 4.5 (bitlocker-status with hardened key handling)`.

### Task 6: Batch close-out
- [ ] Build green + full suite green. `-ListTools` shows **64 tools** (23 diag + 8 cloud + 16 repair + 17 laptop). Quote the 17 Laptop rows with Risk/Admin.
- [ ] Category-menu check: 4 categories now (A=Cloud, B=Diagnostics, C=Laptop, D=Repair). Scripted-stdin smoke: 4 category letters; a legacy number (e.g. 38) runs from landing; category C drills into the 17 laptop tools. Quote.
- [ ] Update `docs\parity-checklist.md`: mark 38-47,62,63,64,67,68,70,71 `ported (batch 4)` with v9 ids. Commit `docs: batch 4 complete - parity checklist (64/106 ported)`.
- [ ] Final whole-batch review (focus: BitLocker key never leaked in status, file backup hardened + ACL'd; confirm gates on the v8-silent tools; vpn-health uses the timeout helper; Disruptive tools refuse silent-no-force). Then merge to master.

## After this batch
Remaining: 5 (Browser 48-50), 6 (Common User Issues 52-61/66/76-85/95-98/106 incl. tool 60 credential merge), 7 (Security/Domain 51/91-93/101 + Quick Fixes Q1-Q9). See `docs\parity-checklist.md`.
