# NMM Toolkit v8 → v9 Parity Checklist

Generated at batch 1 close-out; updated batch 6a close-out (batch 6 complete). **86 of ~111 items ported** (items 1-20, 21-25, 28-30, 31-36, 38-48, 50, 52, 53, 54, 55, 56, 57-60, 62-64, 65, 66, 67-73, 75, 76, 79-82, 83, 84, 85, 87-90, 94, 95, 96, 100, 102, 104). Items 26, 27, 37, 49, 61, 77, 78, 97, 98, 99, 106 consolidated.

> **Known consolidation candidates — decide at their batch, with Matt:**
> - **26 / 60** — Credential Manager Cleanup (appears in both Cloud & Common User Issues)
> - **22 / 99** — Office Repair (Office 365 Health & Repair vs Click-to-Run Online Repair) [resolved batch 3: 99 consolidated -> tool 22]
> - **76 / 106** — Outlook Search (Fix Outlook Search vs Repair Outlook Search Index) [resolved batch 6a: 106 consolidated -> 76 (outlook-search-repair)]

---

## System Diagnostics

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 1 | System Information | ported (batch 1) | system-info |
| 2 | Disk Space Analysis | ported (batch 1) | disk-space |
| 3 | Network Diagnostics | ported (batch 1) | network-diagnostics |
| 4 | Running Processes | ported (batch 1) | running-processes |
| 5 | Windows Services Status | ported (batch 1) | services-status |
| 6 | Recent Event Log Errors | ported (batch 1) | event-log-errors |
| 7 | Performance Metrics | ported (batch 1) | performance-metrics |
| 8 | Installed Software List | ported (batch 1) | installed-software |
| 9 | Windows Updates Status | ported (batch 1) | windows-updates |
| 10 | User Account Information | ported (batch 1) | user-accounts |
| 11 | Temp Files Cleanup | ported (pilot) | temp-cleanup |
| 12 | Network Connectivity Tests | ported (batch 1) | network-connectivity |
| 13 | System Health Check | ported (batch 1) | system-health |
| 14 | Security Analysis | ported (batch 1) | security-analysis |
| 15 | Driver Information | ported (batch 1) | driver-info |
| 16 | Startup Programs | ported (batch 1) | startup-programs |
| 17 | Scheduled Tasks Review | ported (batch 1) | scheduled-tasks |
| 18 | File System Check | ported (batch 1) | file-system-check |
| 19 | Windows Features Status | ported (batch 1) | windows-features |
| 20 | System Uptime and Boot Info | ported (pilot) | system-uptime |
| 69 | Offline Hardware Summary for Ticket Attachments | ported (batch 1) | hardware-summary |
| 94 | Pending Reboot Status | ported (batch 1) | pending-reboot |
| 104 | winget App Update Sweep | ported (batch 1) | winget-upgrade |

---

## Cloud & Collaboration

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 21 | Azure AD Health Check | ported (batch 2) | azure-ad-health |
| 22 | Office 365 Health and Repair | ported (batch 2) | office-repair |
| 23 | OneDrive Health and Reset | ported (batch 2) | onedrive-repair |
| 24 | Teams Cache Clear and Reset | ported (batch 2) | teams-cache |
| 25 | M365 Connectivity Test | ported (batch 2) | m365-connectivity |
| 26 | Credential Manager Cleanup | consolidated -> tool 60 (batch 6) | — |
| 27 | MFA Status Check | consolidated -> tool 30 (windows-hello) | — |
| 28 | Group Policy Update | ported (batch 2) | group-policy-update |
| 29 | Intune/MDM Health Check | ported (batch 2) | intune-health |
| 30 | Windows Hello Status | ported (batch 2) | windows-hello |

---

## Advanced System Repair

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 31 | DISM System Image Repair | ported (batch 3) | dism-repair |
| 32 | System File Checker (SFC) | ported (batch 3) | sfc-repair |
| 33 | Check Disk (ChkDsk) | ported (batch 3) | chkdsk-repair |
| 34 | Deep Disk Cleanup | ported (batch 3) | deep-disk-cleanup |
| 35 | OEM Driver/Firmware Update | ported (batch 3) | oem-driver-update |
| 36 | Complete Repair Suite (DISM+SFC+Cleanup) | ported (batch 3) | repair-suite |
| 37 | Check System Reboot Status | consolidated -> tools 20 + 94 | — |
| 65 | Local Windows Update Repair (Offline) | ported (batch 3) | windows-update-repair |
| 72 | Driver Integrity Scan | ported (batch 3) | driver-integrity-scan |
| 73 | Display Driver Cleaner (Safe Mode) | ported (batch 3) [renamed to 'Reset Display Adapter'] | display-adapter-reset |
| 75 | BSOD Crash Dump Parser (Mini) | ported (batch 3) | bsod-crash-parser |
| 87 | Install / Upgrade PowerShell 7 | ported (batch 3) | powershell7-install |
| 88 | Win11 Feature Update Unlock & Trigger | ported (batch 3) | win11-feature-unlock |
| 89 | Adobe Creative Cloud Force Removal | ported (batch 3) | adobe-cc-removal |
| 90 | Windows Activation Status & Repair | ported (batch 3) | windows-activation |
| 99 | Office Click-to-Run Online Repair | consolidated -> tool 22 (office-repair) | — |
| 100 | Proxy / Internet Settings Repair | ported (batch 3) | proxy-reset |
| 102 | Remove Windows.old (Post-Upgrade Cleanup) | ported (batch 3) | windows-old-removal |

---

## Laptop & Mobile Computing

_Item 67 appears under Quick Fixes in the v8 menu but is assigned here per the batch plan._

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 38 | Battery Health Check | ported (batch 4) | battery-health |
| 39 | Wi-Fi Diagnostics | ported (batch 4) | wifi-diagnostics |
| 40 | VPN Health and Connection | ported (batch 4) | vpn-health |
| 41 | Webcam and Audio Device Test | ported (batch 4) | webcam-audio-test |
| 42 | BitLocker Status and Recovery | ported (batch 4) | bitlocker-status |
| 43 | Power Management and Plans | ported (batch 4) | power-management |
| 44 | Docking Station and Displays | ported (batch 4) | docking-displays |
| 45 | Bluetooth Device Management | ported (batch 4) | bluetooth-devices |
| 46 | Storage Health (SSD/NVMe) | ported (batch 4) | storage-health |
| 47 | Network Profile Cleanup | ported (batch 4) | network-profile-cleanup |
| 62 | Touchpad & Keyboard Troubleshooter | ported (batch 4) | touchpad-keyboard |
| 63 | Thermal & Fan Health Check | ported (batch 4) | thermal-health |
| 64 | Sleep / Hibernate / Lid-Close Repair | ported (batch 4) | sleep-hibernate |
| 67 | Advanced Network Stack Deep Reset (Offline) | ported (batch 4) | network-stack-reset |
| 68 | Input & Hotkey / Fn Key Check | ported (batch 4) | hotkey-fn |
| 70 | Wi-Fi Environment Snapshot | ported (batch 4) | wifi-environment |
| 71 | Laptop Readiness for Travel | ported (batch 4) | travel-readiness |

---

## Browser & Data Tools

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 48 | Browser Backup (Chrome/Edge/Firefox/Brave) | ported (batch 5) | browser-backup-restore |
| 49 | Browser Restore from Backup | consolidated -> tool 48 (browser-backup-restore) | — |
| 50 | Comprehensive Browser Clear (All Data Except Passwords) | ported (batch 5) | browser-clear |

---

## Common User Issues

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 52 | Printer Troubleshooter | ported (batch 6d) | printer-repair |
| 53 | Performance Optimizer | ported (batch 6d) | perf-optimizer |
| 54 | Windows Search Rebuild | ported (batch 6c) | windows-search-rebuild |
| 55 | Start Menu & Taskbar Repair | ported (batch 6c) | start-menu-taskbar |
| 56 | Audio Troubleshooter | ported (batch 6d) | audio-repair |
| 57 | Windows Explorer Reset | ported (batch 6c) | windows-explorer-reset |
| 58 | Mapped Network Drives | ported (batch 6e) | network-drives |
| 59 | Default Apps & File Types | ported (batch 6c) | default-apps |
| 60 | Credential Manager Cleanup | ported (batch 6e) | credential-manager |
| 61 | Display & Monitor Config | consolidated -> tools 44 + 73 | — |
| 66 | Local Profile Size & Roaming Cache Cleanup | ported (batch 6e) | profile-cache |
| 76 | Fix Outlook Search (Restart WSearch + Reset Search Components) | ported (batch 6a) | outlook-search-repair |
| 77 | Webcam Driver Fix (Soft Reset + Optional Driver Reinstall) | consolidated -> tool 84 (teams-camera-repair) | — |
| 78 | Shared Mailbox Access Fix | consolidated -> tool 79 (m365-auth-reset) | — |
| 79 | Clear M365 Auth Tokens | ported (batch 6a) | m365-auth-reset |
| 80 | AutoDiscover Fix | ported (batch 6a) | autodiscover-fix |
| 81 | Outlook OST Rebuild | ported (batch 6a) | outlook-ost-rebuild |
| 82 | Outlook Profile Repair | ported (batch 6a) | outlook-profile-repair |
| 83 | Teams Meeting Add-in Repair (Outlook button missing) | ported (batch 6b) | teams-addin-repair |
| 84 | Teams Camera/Mic Permissions Reset | ported (batch 6b) | teams-camera-repair |
| 85 | Teams Deep Diagnostic & Repair | ported (batch 6b) | teams-deep-diagnostic |
| 95 | Temporary Profile Repair | ported (batch 6e) | temp-profile-repair |
| 96 | Outlook Add-in Repair (OnBase & Others) | ported (batch 6a) | outlook-addin-repair |
| 97 | Teams Camera & Media Stack Reset | consolidated -> tool 84 (teams-camera-repair) | — |
| 98 | Reset Print Spooler (Deep) | consolidated -> tool 52 (printer-repair) | — |
| 106 | Repair Outlook Search Index | consolidated -> tool 76 (outlook-search-repair) | — |

---

## Security & Domain

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 51 | Domain Trust and Connection Repair | pending (batch 7) | — |
| 91 | Time Sync Repair | pending (batch 7) | — |
| 92 | Local Admin Account Audit | pending (batch 7) | — |
| 93 | Windows Defender / Security Status | pending (batch 7) | — |
| 101 | Enable Remote Desktop | pending (batch 7) | — |

---

## Quick Fixes

_Q1–Q9 are composite workflows that bundle existing tools. Exact composition and whether each becomes a named v9 tool or a macro TBD with Matt at batch 7 / consolidation review._

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| Q1 | Office Issues | pending (batch 7) | — |
| Q2 | OneDrive Issues | pending (batch 7) | — |
| Q3 | Teams Issues | pending (batch 7) | — |
| Q4 | Login Issues | pending (batch 7) | — |
| Q5 | Wi-Fi Issues | pending (batch 7) | — |
| Q6 | VPN Issues | pending (batch 7) | — |
| Q7 | Audio/Video Prep | pending (batch 7) | — |
| Q8 | Docking Station | pending (batch 7) | — |
| Q9 | Browser Backup | pending (batch 7) | — |
