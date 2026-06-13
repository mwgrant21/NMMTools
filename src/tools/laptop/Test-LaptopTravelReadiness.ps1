function Test-LaptopTravelReadiness {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'travel-readiness'

        $issues   = @()
        $warnings = @()
        $ok       = @()

        # --- Check 1: Free disk space (C: drive) ---
        $sysDisk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($sysDisk -and $sysDisk.Size -gt 0) {
            $freeGB  = [math]::Round($sysDisk.FreeSpace / 1GB, 2)
            $freePct = [math]::Round(($sysDisk.FreeSpace / $sysDisk.Size) * 100, 1)
            $diskMsg = 'Disk: {0} GB free ({1}%)' -f $freeGB, $freePct
            if ($freeGB -lt 10) {
                $issues += $diskMsg
            } elseif ($freePct -lt 15) {
                $warnings += $diskMsg
            } else {
                $ok += $diskMsg
            }
        } else {
            $warnings += 'Disk: unable to read C: drive info'
        }

        # --- Check 2: Battery wear (inline - self-contained, do NOT call Get-BatteryHealth) ---
        $battInst = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if ($battInst) {
            $dCap = $battInst.DesignCapacity
            $fCap = $battInst.FullChargeCapacity
            if ($dCap -and $dCap -gt 0 -and $fCap) {
                $wearPct = [math]::Round((1 - ($fCap / $dCap)) * 100, 1)
                $battMsg = 'Battery: {0}% wear' -f $wearPct
                if ($wearPct -gt 50) {
                    $issues += ($battMsg + ' (consider replacement)')
                } elseif ($wearPct -gt 30) {
                    $warnings += $battMsg
                } else {
                    $ok += $battMsg
                }
            } else {
                $warnings += 'Battery: capacity data not available'
            }
        } else {
            $warnings += 'Battery: not detected (may be desktop)'
        }

        # --- Check 3: BitLocker OS volume ---
        # -ErrorAction SilentlyContinue: cmdlet may fail or return empty when non-admin
        $blVol = $null
        try {
            $blVol = Get-BitLockerVolume -ErrorAction SilentlyContinue |
                Where-Object { $_.VolumeType -eq 'OperatingSystem' }
        }
        catch { }

        if ($blVol) {
            if ($blVol.ProtectionStatus -eq 'On') {
                $ok += 'BitLocker: Protected'
            } else {
                $issues += ('BitLocker: Protection is {0}' -f $blVol.ProtectionStatus)
            }
        } else {
            # Empty result when non-admin is normal; report "unknown" not "off"
            $warnings += 'BitLocker: unknown (non-admin or not configured)'
        }

        # --- Check 4: Wi-Fi adapter presence ---
        $wifiAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless' })
        if ($wifiAdapters.Count -gt 0) {
            $ok += 'Wi-Fi adapter: present'
        } else {
            $issues += 'Wi-Fi adapter: not detected'
        }

        # --- Check 5: VPN service presence (presence only - not connectivity) ---
        $vpnServiceNames = @('RasMan', 'OpenVPNService', 'NordVPN', 'ExpressVPN')
        $vpnFound = $false
        foreach ($svcName in $vpnServiceNames) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $vpnFound = $true
                $ok += ('VPN service present: {0}' -f $svcName)
                break
            }
        }
        if (-not $vpnFound) {
            $warnings += 'VPN client: no known VPN service detected'
        }

        # --- Display results ---
        # Readiness check headline; per-check rows follow
        Write-ToolOutput ('Travel readiness: {0} OK, {1} warning(s), {2} issue(s)' -f $ok.Count, $warnings.Count, $issues.Count)

        # OK checks at Detail level
        foreach ($item in $ok) {
            Write-ToolOutput ('[OK] {0}' -f $item) -Level Detail
        }
        # Warnings at Warning level
        foreach ($item in $warnings) {
            Write-ToolOutput ('[WARN] {0}' -f $item) -Level Warning
        }
        # Issues at Warning level (no Error level for ReadOnly tools)
        foreach ($item in $issues) {
            Write-ToolOutput ('[ISSUE] {0}' -f $item) -Level Warning
        }

        # Overall verdict
        if ($issues.Count -gt 0) {
            $verdict = 'Not Ready'
        } elseif ($warnings.Count -gt 0) {
            $verdict = 'Ready with Warnings'
        } else {
            $verdict = 'Ready'
        }

        $allFlags = @($issues + $warnings)
        if ($allFlags.Count -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary (
                '{0}: {1}' -f $verdict, ($allFlags -join '; '))
        } else {
            Complete-ToolRun $run -Status Success -Summary (
                '{0}: all 5 checks passed' -f $verdict)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
