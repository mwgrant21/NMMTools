function Get-WindowsHelloStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-hello'

        # Check Passport-for-Work GPO key - presence means Hello is policy-configured
        $helloPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork' -ErrorAction SilentlyContinue

        if ($helloPolicy) {
            Write-ToolOutput 'Hello policy: Managed via Group Policy (PassportForWork key present)'
        } else {
            Write-ToolOutput 'Hello policy: Not configured via Group Policy' -Level Warning
        }

        # Enumerate biometric devices (Hello-capable hardware); covers MFA-readiness (absorbed tool 27)
        $bioDevices = @(Get-PnpDevice -Class 'Biometric' -ErrorAction SilentlyContinue)

        if ($bioDevices.Count -gt 0) {
            # Report FriendlyName and Status for each biometric device
            foreach ($dev in $bioDevices) {
                Write-ToolOutput ('Biometric: {0} [{1}]' -f $dev.FriendlyName, $dev.Status) -Level Detail
            }
        } else {
            Write-ToolOutput 'No biometric devices found' -Level Detail
        }

        # Verdict keys on biometric hardware, not GPO policy. Absent PassportForWork
        # policy is normal (Hello is often set up via Settings/Intune, not Group Policy).
        if ($bioDevices.Count -gt 0) {
            if ($helloPolicy) { $policyNote = 'policy enforced via GPO' } else { $policyNote = 'no GPO policy (per-user/Intune config is normal)' }
            Complete-ToolRun $run -Status Success -Summary ('{0} biometric device(s); {1}' -f $bioDevices.Count, $policyNote)
        } else {
            if ($helloPolicy) { $noteNoHw = 'policy configured but no biometric hardware present' } else { $noteNoHw = 'no GPO policy and no biometric hardware' }
            Complete-ToolRun $run -Status Warning -Summary ('Windows Hello: {0}' -f $noteNoHw)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
