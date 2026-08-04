# USB Device Troubleshooter — Design Spec
**Date:** 2026-08-04
**Status:** Approved
**Scope:** One new tool, `Repair-UsbDevices` (category `Repair`) — scans all USB-attached PnP
devices for problem status, attempts a reconnect (disable/re-enable) on non-storage devices,
and flags devices whose error code indicates a missing/bad driver for manual update. No
existing tool's behavior changes.

---

## Background

Support calls involving a flaky USB device (mouse, webcam, headset, dock peripheral) currently
have no dedicated toolkit entry. The closest existing tools are narrower: `Reset-DisplayAdapter`
resets one specific adapter class, `Get-DriverIntegrityScan` audits the whole driver store
read-only, and `Repair-TeamsCameraDeep` targets USB dock camera failures specifically. This
tool generalizes the "diagnose, then disable/re-enable to force a reconnect" pattern already
established by `Reset-DisplayAdapter` to any USB-attached device, and separately flags devices
that look like they need a driver update rather than a reconnect.

This is a general health-audit tool, not a single-device lookup — it scans everything and acts
on what it finds in one pass, rather than requiring the tech to name a specific device.

---

## Scan scope

`Get-PnpDevice | Where-Object { $_.InstanceId -like 'USB*' }` — deliberately broader than
`Get-PnpDevice -Class USB`, which only returns hub/controller/composite nodes. Filtering by
`InstanceId` prefix instead catches the actual function devices (mouse, webcam, headset, etc.),
which live under their own classes (`Mouse`, `Image`, `AudioEndpoint`, ...) but are still
USB-attached — that's what "my USB device stopped working" actually means in practice.

Each device is cross-referenced with `Get-CimInstance Win32_PnPEntity` (matched by `PNPDeviceID`)
to read `ConfigManagerErrorCode`, since `Get-PnpDevice`'s `Status` alone doesn't expose the
specific Device Manager error code.

---

## Classification

For every device whose `Status -ne 'OK'`:

1. **Error code lookup.** `ConfigManagerErrorCode` is mapped through a small lookup table to a
   human description. Codes covered at minimum: 10 (cannot start), 28 (drivers not installed),
   31 (not working properly), 32 (driver disabled), 37 (driver failed to load), 39 (driver may
   be corrupt/missing), 43 (device reported problems), 45 (currently not connected), 48
   (previous driver blocked as incompatible).
2. **Driver-flagged bucket.** Codes 10, 28, 31, 32, 37, 39, 48 are treated as driver-related.
   These devices are reported with their code/description and "manual driver update
   recommended" — no automated driver action is taken (see Non-goals).
3. **Storage exclusion.** Any problem device whose `Class` is `USBSTOR`, `DiskDrive`, or
   `CDROM` is reported but never disabled/re-enabled — flagged "excluded: storage device,
   needs manual attention" instead, since disabling a storage device mid-use risks data
   corruption in a way a mouse/webcam/headset reconnect does not.
4. **Fixable bucket.** Every other non-OK, non-excluded device is a reconnect candidate.
   (A device can appear in both the driver-flagged bucket and the fixable bucket — e.g. a
   webcam with code 43 gets both the driver recommendation and the disable/re-enable attempt.)

---

## Reconnect action

One overall confirmation, not per-device — mirrors `Reset-DisplayAdapter`'s existing pattern
and the toolkit-wide `-Silent` + `Risk = 'Disruptive'` contract (refused under `-Silent` unless
`-Force`):

```powershell
Read-ToolChoice -Prompt 'N fixable USB device(s) found with problems. Attempt reconnect (brief disconnect)?' `
    -Choices @('Yes', 'No') -Default 'No' -Silent:$Silent
```

On `Yes`, every fixable device (not per-device prompts) is processed:

```powershell
Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
```

After re-enabling, each device's status is re-queried and reported before/after — the fix is
verified, not assumed to have worked (matching the repo's existing verify-before-log
discipline used elsewhere for state-changing operations).

---

## Registry entry

```powershell
@{
    Id            = 'usb-device-repair'
    LegacyId      = '120'
    Name          = 'USB Device Troubleshooter'
    Category      = 'Repair'
    Function      = 'Repair-UsbDevices'
    Description   = 'Scans USB-attached devices for problem status, attempts reconnect (disable/re-enable) on non-storage devices, and flags devices needing a manual driver update'
    RequiresAdmin = $true
    SilentCapable = $true
    Risk          = 'Disruptive'
    Tags          = @('usb','device','driver','reconnect','pnp')
}
```

`RequiresAdmin = $true` because `Enable-PnpDevice`/`Disable-PnpDevice` require elevation.
`Risk = 'Disruptive'` because it forces a brief disconnect on live devices, same classification
as `Reset-DisplayAdapter`.

---

## Verdict / status

- `Success` — no problem devices found.
- `Warning` — any of: a device remains non-OK after the fix attempt, any device is
  driver-flagged, or any storage device was excluded from the fix. Summary line reports counts
  for each bucket (found / fixed / still-failing / driver-flagged / excluded-storage).
- `Failed` — only on an unhandled exception (e.g. `Get-PnpDevice`/`Get-CimInstance` both
  unavailable), matching the standard template's catch block.

---

## Non-goals (explicit)

- No automated driver update/reinstall. Driver-flagged devices are reported with their error
  code and description only — matches `Get-DriverIntegrityScan`'s read-only precedent, and
  avoids the real risk of an automated wrong-driver install. This was explicitly deferred, not
  overlooked.
- No per-device confirmation prompts — one overall Yes/No gate covers the whole fixable set,
  consistent with `Reset-DisplayAdapter` and the toolkit's existing `-Silent`/`-Force` contract.
- No remote/multi-machine execution — toolkit-wide standing non-goal.
- No handling of USB devices that aren't currently enumerable at all (e.g. a hub that dropped
  off the bus entirely) — this tool only acts on devices Windows still lists with a problem
  status, not devices missing from `Get-PnpDevice` altogether.

---

## Testing

- `tests\template.tests.ps1` / `tests\registry.tests.ps1` — structural checks, run automatically
  (registry/file/function agreement), same as every prior tool addition.
- `.\build.ps1` then `Invoke-Pester .\tests` — full suite.
- Manual smoke test through the built artifact on a machine with at least one USB device in a
  non-OK state (Device Manager warning icon), to confirm the classification buckets, the
  storage exclusion, and that the disable/re-enable cycle actually clears a recoverable error.
  This repo has no per-tool business-logic test files for any of its ~120 existing diagnostic
  tools, only structural checks — consistent with the established convention.
