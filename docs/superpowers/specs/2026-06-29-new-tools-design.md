# NMMToolkit — New Tools Design
**Date:** 2026-06-29  
**Status:** Approved  
**Scope:** Four new standalone tools added to the existing toolkit (IDs 106–109). No existing tools modified.

---

## Background

Four recurring IT support patterns that the current toolkit doesn't permanently resolve:

1. Teams camera failures on Lenovo ThinkPad 21k900CUS + Dell D6000/WD19 docks — fixed repeatedly by `Repair-TeamsCamera` but root cause never addressed
2. Teams call quality complaints (lag, jitter, dropped video) concentrated on in-office docked users
3. Outlook search not covering shared/delegate mailboxes
4. Hyland/OnBase Outlook add-in repeatedly auto-disabled by Outlook's resilience feature

All four tools follow the existing toolkit pattern: diagnose silently, act, report findings. Tools 106 and 109 go further with hardening (Option C) to prevent recurrence.

---

## Tool 106 — Teams Camera Root Cause Diagnostic + Permanent Fix

**File:** `src/tools/user/Repair-TeamsCameraDeep.ps1`  
**Risk:** Modifies  
**PDQ-compatible:** Yes (`-Silent` supported)

### Environment Context
- Hardware: Lenovo ThinkPad 21k900CUS (uniform fleet)
- Docks: Dell D6000 (DisplayLink USB 3.0) and Dell WD19 (USB-C/Thunderbolt)
- Two distinct failure modes triggered by dock re-enumeration:
  - **Unavailable** — Windows consent store (`CapabilityAccessManager\webcam`) wiped on dock cycle
  - **Black screen** — DisplayLink virtual camera (D6000) prioritized over physical camera in Teams pipeline, or Lenovo IR camera (Windows Hello) taking precedence over main camera

### Detection Phase
1. Identify connected dock type:
   - D6000: detect DisplayLink driver (`dlcdusb3.sys` / DisplayLink service) and virtual camera device
   - WD19: detect Thunderbolt/USB-C dock by device tree
   - None: undocked baseline
2. Detect failure mode:
   - Check `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam` — missing or denied entry = Unavailable mode
   - Enumerate camera devices via WMI (`Win32_PnPEntity` where PNPClass = 'Camera') — if DisplayLink virtual camera exists and has higher enumeration order = Black screen mode
   - Check Lenovo IR camera device presence and driver state — IR camera taking priority = Black screen mode variant
3. Check USB selective suspend state on camera device node
4. Check DisplayLink driver version (D6000 only) — log for history

### Fix Phase
**Unavailable mode:**
- Restore consent store entry for webcam, set Value = Allow
- Grant Teams app explicit camera permission in consent store

**Black screen — DisplayLink virtual camera:**
- Disable DisplayLink virtual camera device (not the physical camera)
- Clear Teams camera device preference cache so it re-detects on next launch

**Black screen — IR camera conflict:**
- Disable IR camera device for Teams purposes (leave enabled for Windows Hello)
- Set Teams preferred camera registry key to physical camera device ID

### Hardening Phase (Option C)
- Disable USB selective suspend on the physical camera device node via registry (`HKLM\SYSTEM\CurrentControlSet\Enum\...\Device Parameters\WpdBusPnpEnumerator`)
- Set camera power management to never sleep (`IdleInWorkingState = 0`)
- Write consent store entry with a `ForceDeny = 0` sentinel that survives re-enumeration
- Log root cause, dock type, and fix applied to `%PROGRAMDATA%\NMMTools\camera-fix-history.json` — repeat visits append entries so pattern is visible over time

### Output
```
Dock detected       : Dell D6000 (DisplayLink)
Failure mode        : Black screen — DisplayLink virtual camera taking priority
Physical camera     : Lenovo Integrated Camera (USB\VID_04F2...)
Fix applied         : DisplayLink virtual camera disabled, Teams cache cleared
Hardening applied   : USB suspend disabled, power management pinned
History             : 1 prior fix on this machine (2026-06-14)
Why it kept happening: D6000 dock re-enumeration was re-activating DisplayLink
                       virtual camera on every dock cycle
```

### Slug / Legacy ID
`teams-camera-deep` / 106

---

## Tool 107 — Teams Meeting Quality Diagnostic

**File:** `src/tools/cloud/Get-TeamsMeetingQuality.ps1`  
**Risk:** ReadOnly  
**PDQ-compatible:** Yes (report written to log)

### What It Measures

**Network path:**
- Detect active NIC: built-in (Intel/Realtek), dock NIC (D6000 DisplayLink USB NIC, WD19 NIC), or WiFi
- Identify which adapter Teams is bound to
- Flag D6000 DisplayLink NIC explicitly — USB 3.0 shared bus with peripherals is a known bottleneck for video calls

**Live network quality (to real M365 endpoints):**
- Ping latency (10 samples) to `*.lync.com` STUN endpoints and `teams.microsoft.com`
- Calculate avg/min/max latency and jitter (std deviation between samples)
- Packet loss percentage
- DNS resolution time to Teams endpoints

**VPN check:**
- Detect active VPN tunnel
- Check if Teams traffic is routed through VPN (full tunnel) vs excluded (split tunnel)
- Full tunnel = flag as likely contributor to latency

**Configuration checks (no changes):**
- Teams QoS / DSCP marking: check `HKLM\SOFTWARE\Policies\Microsoft\Windows\QoS` for Teams audio/video DSCP values
- Hardware video encoder: check for Intel Quick Sync, NVIDIA NVENC, AMD VCE via WMI GPU query — CPU fallback flagged
- Teams version (current vs outdated)
- CPU utilization and available RAM snapshot at time of test
- DisplayLink NIC driver version if D6000 dock detected

**Teams log sampling:**
- Read last 500 lines of `%APPDATA%\Microsoft\Teams\logs.txt`
- Extract recent call quality events (packet loss, codec switches, bandwidth drops) if present

### Scoring
Each measured dimension gets a simple flag: OK / WARNING / ISSUE  
Final verdict line summarizes top 1–2 contributors.

### Output
```
Network adapter     : Dell D6000 DisplayLink NIC [WARNING - shared USB bus]
Latency to M365     : 42ms avg | Jitter: 18ms [WARNING] | Packet loss: 0.2% [OK]
DNS resolution      : 12ms [OK]
VPN                 : Active, full tunnel [ISSUE - Teams traffic tunneled]
QoS / DSCP          : Not configured [WARNING]
Hardware encoder    : Intel Quick Sync available [OK]
Teams version       : Current [OK]
CPU / RAM           : 34% / 6.2GB free [OK]

Verdict: VPN full tunnel and high jitter on D6000 NIC are the
         likely causes of dropped video. Recommend split tunnel
         for Teams traffic and switching to built-in NIC for calls.
```

### Slug / Legacy ID
`teams-meeting-quality` / 107

---

## Tool 108 — Outlook Search: All Mailboxes Fix

**File:** `src/tools/user/Repair-OutlookSearchScope.ps1`  
**Risk:** Modifies  
**PDQ-compatible:** Yes (`-Silent` supported)

### Detection Phase
1. Locate active Outlook profile from registry (`HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Profiles`)
2. Enumerate all connected data files from profile:
   - Primary mailbox .ost
   - Shared mailbox .ost files
   - Delegate mailbox .ost files
   - Online archive .ost
   - Any connected .pst files
3. For each data file:
   - Check if path is registered in Windows Search indexing scope (`HKLM\SOFTWARE\Microsoft\Windows Search\CrawlScopeManager`)
   - Check file size — files >5GB may be hitting Windows Search default exclusion
   - Check if file appears in Windows Search crawl backlog
4. Check Outlook search scope registry key (`HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Search\SearchDefaultScope`) — value 0 = current mailbox, value 1 = all mailboxes
5. Check Windows Search service (WSearch) state and last crawl timestamp
6. Check for Outlook search corruption flag (`OutlookSecondaryIndex` corruption key)

### Fix Phase
- Register each unindexed .ost/.pst path with Windows Search crawl scope
- For files >5GB: raise per-file size limit in Windows Search registry
- Set `SearchDefaultScope = 1` (All Mailboxes)
- Clear corruption flag if present
- Restart WSearch service if degraded
- Issue targeted re-index notification for Outlook data scope only — does NOT trigger full system re-index

### Output
```
Outlook profile     : Outlook (default)
Primary mailbox     : C:\Users\...\Outlook.ost (3.2GB) — Indexed [OK]
Shared: Finance     : C:\Users\...\Finance.ost (1.1GB) — NOT indexed [FIXED]
Shared: HR Inbox    : C:\Users\...\HR.ost (890MB) — NOT indexed [FIXED]
Online Archive      : C:\Users\...\Archive.ost (7.4GB) — Excluded (>5GB) [FIXED - limit raised]
Search scope        : Was "Current Mailbox" — set to "All Mailboxes" [FIXED]
Windows Search      : Healthy, last crawl 2h ago
Re-index            : Triggered for 3 data files — full results in ~15 min
```

### Slug / Legacy ID
`outlook-search-all` / 108

---

## Tool 109 — OnBase/Hyland Add-in Permanent Enable

**File:** `src/tools/user/Repair-OnBaseAddinPermanent.ps1`  
**Risk:** Modifies  
**PDQ-compatible:** Yes (`-Silent` supported)

### Detection Phase
Identify OnBase/Hyland add-in registration:
- Search both `HKCU\SOFTWARE\Microsoft\Office\Outlook\Addins` and `HKLM\SOFTWARE\Microsoft\Office\Outlook\Addins` for Hyland/OnBase ProgIDs (`OnBase.OutlookAddin`, `Hyland.OutlookAddIn`, and variants)
- Read current `LoadBehavior` value (3 = load at startup, 2 = load on demand, 0 = disabled)
- Check `HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems` — binary blob listing add-ins Outlook auto-killed
- Check `HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\CrashedAddinList` — add-ins flagged for causing crashes
- Check `HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\AddinLoadTimes` — actual recorded load time vs threshold (default 1000ms)
- Determine registration scope: HKCU (user, vulnerable) vs HKLM (machine, persistent)

### Fix Phase (B)
- Set `LoadBehavior = 3`
- Remove add-in GUID/ProgID from `DisabledItems` blob
- Clear entry from `CrashedAddinList`
- Remove from any other Resiliency blacklist subkeys

### Hardening Phase (C)
- Add add-in ProgID to `HKCU\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList` with value 1 — Outlook checks this before auto-disabling
- Raise per-add-in startup timeout: write `AddinLoadTimeOut` for the ProgID to 5000 (5 seconds) — prevents slow OnBase loads from triggering auto-disable
- If registered under HKCU: write duplicate registration under HKLM so it survives user profile resets (requires elevation)
- Create a weekly scheduled task (`NMMTools-OnBaseAddinCheck`) that:
  - Checks LoadBehavior for the add-in
  - If not 3: sets it back to 3 silently
  - Logs action to `%PROGRAMDATA%\NMMTools\onbase-addin-heal.log`

### Output
```
Add-in found        : Hyland.OutlookAddIn (HKCU)
LoadBehavior        : Was 0 (disabled) — restored to 3
Disabled by         : CrashedAddinList (Outlook auto-killed after slow load)
Load time recorded  : 2,340ms (exceeded 1,000ms threshold)
Fix applied         : Removed from CrashedAddinList, LoadBehavior = 3
DoNotDisableList    : Added [HARDENED]
Startup timeout     : Raised to 5,000ms [HARDENED]
HKLM registration   : Added [HARDENED]
Self-heal task      : Created — weekly check [HARDENED]
Verdict             : Add-in hardened. Outlook cannot auto-disable it.
```

### Slug / Legacy ID
`onbase-addin-fix` / 109

---

## Implementation Notes

### File locations
```
src/tools/user/Repair-TeamsCameraDeep.ps1
src/tools/cloud/Get-TeamsMeetingQuality.ps1
src/tools/user/Repair-OutlookSearchScope.ps1
src/tools/user/Repair-OnBaseAddinPermanent.ps1
```

### Registry entries (tools.psd1)
All four tools follow existing registry schema:
- `Id`, `Slug`, `LegacyId`, `Name`, `Description`, `Category`, `Risk`, `PDQCompatible`, `Tags`, `Fn`

### Risk levels
| Tool | Risk | Reason |
|------|------|--------|
| 106 Teams Camera Deep | Modifies | Driver device state, registry, power settings |
| 107 Teams Meeting Quality | ReadOnly | Measurement only, no changes |
| 108 Outlook Search Scope | Modifies | Windows Search registration, Outlook registry |
| 109 OnBase Permanent Enable | Modifies | Registry, scheduled task, HKLM write |

### Testing
- 106 and 109: testable via unit tests with registry mocks; WMI device detection requires live hardware
- 107: ReadOnly, fully unit-testable with mocked ping results and log file fixtures
- 108: testable with mock Outlook profile registry keys and temp .ost file paths
- All four: manual validation on Lenovo 21k900CUS + Dell D6000/WD19 before merge

### PDQ Deploy notes
- 106, 108, 109: support `-Silent` for unattended deployment
- 107: ReadOnly, output written to log at `%PROGRAMDATA%\NMMTools\Logs\` under `-Silent`
- 109 HKLM write requires elevation — PDQ steps run as SYSTEM so this is satisfied automatically
