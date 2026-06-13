# NMM Toolkit v8 → v9 Parity Checklist

Generated at batch 1 close-out; updated batch 3 close-out. **47 of ~111 items ported** (items 1-20, 21-25, 28-30, 31-36, 65, 69, 72, 73, 75, 87-90, 94, 100, 102, 104). Items 26, 27, 37, 99 consolidated.

> **Known consolidation candidates — decide at their batch, with Matt:**
> - **26 / 60** — Credential Manager Cleanup (appears in both Cloud & Common User Issues)
> - **22 / 99** — Office Repair (Office 365 Health & Repair vs Click-to-Run Online Repair) [resolved batch 3: 99 consolidated -> tool 22]
> - **76 / 106** — Outlook Search (Fix Outlook Search vs Repair Outlook Search Index)

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
| 38 | Battery Health Check | pending (batch 4) | — |
| 39 | Wi-Fi Diagnostics | pending (batch 4) | — |
| 40 | VPN Health and Connection | pending (batch 4) | — |
| 41 | Webcam and Audio Device Test | pending (batch 4) | — |
| 42 | BitLocker Status and Recovery | pending (batch 4) | — |
| 43 | Power Management and Plans | pending (batch 4) | — |
| 44 | Docking Station and Displays | pending (batch 4) | — |
| 45 | Bluetooth Device Management | pending (batch 4) | — |
| 46 | Storage Health (SSD/NVMe) | pending (batch 4) | — |
| 47 | Network Profile Cleanup | pending (batch 4) | — |
| 62 | Touchpad & Keyboard Troubleshooter | pending (batch 4) | — |
| 63 | Thermal & Fan Health Check | pending (batch 4) | — |
| 64 | Sleep / Hibernate / Lid-Close Repair | pending (batch 4) | — |
| 67 | Advanced Network Stack Deep Reset (Offline) | pending (batch 4) | — |
| 68 | Input & Hotkey / Fn Key Check | pending (batch 4) | — |
| 70 | Wi-Fi Environment Snapshot | pending (batch 4) | — |
| 71 | Laptop Readiness for Travel | pending (batch 4) | — |

---

## Browser & Data Tools

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 48 | Browser Backup (Chrome/Edge/Firefox/Brave) | pending (batch 5) | — |
| 49 | Browser Restore from Backup | pending (batch 5) | — |
| 50 | Comprehensive Browser Clear (All Data Except Passwords) | pending (batch 5) | — |

---

## Common User Issues

| v8 # | v8 Menu Name | Status | v9 Id |
|-----:|---|---|---|
| 52 | Printer Troubleshooter | pending (batch 6) | — |
| 53 | Performance Optimizer | pending (batch 6) | — |
| 54 | Windows Search Rebuild | pending (batch 6) | — |
| 55 | Start Menu & Taskbar Repair | pending (batch 6) | — |
| 56 | Audio Troubleshooter | pending (batch 6) | — |
| 57 | Windows Explorer Reset | pending (batch 6) | — |
| 58 | Mapped Network Drives | pending (batch 6) | — |
| 59 | Default Apps & File Types | pending (batch 6) | — |
| 60 | Credential Manager Cleanup | pending (batch 6) | — |
| 61 | Display & Monitor Config | pending (batch 6) | — |
| 66 | Local Profile Size & Roaming Cache Cleanup | pending (batch 6) | — |
| 76 | Fix Outlook Search (Restart WSearch + Reset Search Components) | pending (batch 6) | — |
| 77 | Webcam Driver Fix (Soft Reset + Optional Driver Reinstall) | pending (batch 6) | — |
| 78 | Shared Mailbox Access Fix | pending (batch 6) | — |
| 79 | Clear M365 Auth Tokens | pending (batch 6) | — |
| 80 | AutoDiscover Fix | pending (batch 6) | — |
| 81 | Outlook OST Rebuild | pending (batch 6) | — |
| 82 | Outlook Profile Repair | pending (batch 6) | — |
| 83 | Teams Meeting Add-in Repair (Outlook button missing) | pending (batch 6) | — |
| 84 | Teams Camera/Mic Permissions Reset | pending (batch 6) | — |
| 85 | Teams Deep Diagnostic & Repair | pending (batch 6) | — |
| 95 | Temporary Profile Repair | pending (batch 6) | — |
| 96 | Outlook Add-in Repair (OnBase & Others) | pending (batch 6) | — |
| 97 | Teams Camera & Media Stack Reset | pending (batch 6) | — |
| 98 | Reset Print Spooler (Deep) | pending (batch 6) | — |
| 106 | Repair Outlook Search Index | pending (batch 6) | — |

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
