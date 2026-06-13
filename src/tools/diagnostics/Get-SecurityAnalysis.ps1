function Get-SecurityAnalysis {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'security-analysis'

        $findings       = @()
        $firewallStatus = 'Unable to check'
        $defenderStatus = 'Unable to check'

        # --- Firewall check ---------------------------------------------------
        try {
            $profiles     = Get-NetFirewallProfile -ErrorAction Stop
            $enabledCount = @($profiles | Where-Object { $_.Enabled -eq $true }).Count
            if ($enabledCount -eq 3) {
                $firewallStatus = 'Enabled (All Profiles)'
                Write-ToolOutput ('Firewall: {0}' -f $firewallStatus)
            } else {
                $firewallStatus = 'Partially Enabled ({0}/3 profiles)' -f $enabledCount
                Write-ToolOutput ('Firewall: {0}' -f $firewallStatus) -Level Warning
                $findings += $firewallStatus
            }
        } catch {
            # Access restricted or NetSecurity module unavailable — report at Detail, not a finding
            Write-ToolOutput 'Firewall: Unable to check' -Level Detail
        }

        # --- Defender check ---------------------------------------------------
        try {
            $defender = Get-MpComputerStatus -ErrorAction Stop
            if ($defender.AntivirusEnabled) {
                $defenderStatus = 'Enabled'
                Write-ToolOutput ('Windows Defender: {0}' -f $defenderStatus)
            } else {
                $defenderStatus = 'Disabled'
                Write-ToolOutput ('Windows Defender: {0}' -f $defenderStatus) -Level Warning
                $findings += 'Windows Defender disabled'
            }
        } catch {
            # Defender cmdlet unavailable or access restricted — report at Detail, not a finding
            Write-ToolOutput 'Windows Defender: Unable to check' -Level Detail
        }

        # --- Verdict ----------------------------------------------------------
        # Deliberate improvement over v8: when neither check could run, report Warning
        # instead of Success — Success with no real data is misleading.
        $unavailableSuffix = ''
        if ($firewallStatus -eq 'Unable to check') { $unavailableSuffix += '; firewall check unavailable' }
        if ($defenderStatus -eq 'Unable to check') { $unavailableSuffix += '; Defender check unavailable' }

        if ($firewallStatus -eq 'Unable to check' -and $defenderStatus -eq 'Unable to check') {
            Complete-ToolRun $run -Status Warning -Summary (
                'Could not assess posture: firewall and Defender checks unavailable (restricted access?)')
        } elseif ($findings.Count -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary (
                '{0} concern(s): {1}{2}' -f $findings.Count, ($findings -join '; '), $unavailableSuffix)
        } else {
            Complete-ToolRun $run -Status Success -Summary (
                'Firewall: {0}; Defender: {1}{2}' -f $firewallStatus, $defenderStatus, $unavailableSuffix)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
