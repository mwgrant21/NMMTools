function Get-DefenderStatus {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'defender-status'

        # --- Report ---
        $d = $null
        try { $d = Get-MpComputerStatus -ErrorAction Stop } catch { $d = $null }
        if (-not $d) {
            Write-ToolOutput 'Could not query Windows Defender - a third-party AV may be active.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'Defender not queryable (third-party AV may be active)'
            return
        }

        if ($d.RealTimeProtectionEnabled) { Write-ToolOutput 'Real-Time Protection: Enabled' -Level Info }
        else { Write-ToolOutput 'Real-Time Protection: DISABLED' -Level Warning }

        $defAgeH = $null
        if ($d.AntivirusSignatureLastUpdated) { $defAgeH = [math]::Round(((Get-Date) - $d.AntivirusSignatureLastUpdated).TotalHours, 1) }
        Write-ToolOutput ('Definitions: {0} (age {1} h)' -f $d.AntivirusSignatureVersion, $defAgeH) -Level Detail
        if ($d.LastQuickScanEndTime) {
            $scanDays = [math]::Round(((Get-Date) - $d.LastQuickScanEndTime).TotalDays, 1)
            Write-ToolOutput ('Last quick scan: {0} ({1} days ago)' -f $d.LastQuickScanEndTime.ToString('yyyy-MM-dd HH:mm'), $scanDays) -Level Detail
        }
        Write-ToolOutput ('AV={0}  AntiSpyware={1}  BehaviorMonitor={2}  NIS={3}  Tamper={4}' -f $d.AntivirusEnabled, $d.AntispywareEnabled, $d.BehaviorMonitorEnabled, $d.NisEnabled, $d.IsTamperProtected) -Level Detail

        $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue)
        if ($threats.Count -gt 0) {
            Write-ToolOutput ('ACTIVE THREATS: {0}' -f $threats.Count) -Level Warning
            foreach ($t in $threats) { Write-ToolOutput ('  - {0} (severity {1})' -f $t.ThreatName, $t.SeverityID) -Level Warning }
        } else {
            Write-ToolOutput 'No active threats detected.' -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Defender action' -Choices @('None','UpdateSignatures') -Default 'None' -Silent:$Silent

        if ($action -eq 'UpdateSignatures') {
            try {
                Update-MpSignature -ErrorAction Stop
                Complete-ToolRun $run -Status Success -Summary 'Defender signature update initiated'
            } catch {
                Complete-ToolRun $run -Status Warning -Summary ('Signature update failed: {0}' -f $_.Exception.Message)
            }
            return
        }

        $rtpOff = -not $d.RealTimeProtectionEnabled
        $stale = ($null -ne $defAgeH) -and ($defAgeH -gt 72)
        if ($rtpOff -or $stale -or ($threats.Count -gt 0)) {
            Complete-ToolRun $run -Status Warning -Summary ('Attention: RTP-on={0} stale-defs={1} threats={2}' -f $d.RealTimeProtectionEnabled, $stale, $threats.Count)
        } else {
            Complete-ToolRun $run -Status Success -Summary 'Defender healthy: RTP on, defs current, no threats'
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
