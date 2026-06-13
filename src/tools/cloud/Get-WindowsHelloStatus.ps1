function Get-WindowsHelloStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-hello'

        # Check Passport-for-Work GPO key - presence means Hello is policy-configured
        $helloPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork' -ErrorAction SilentlyContinue

        if ($helloPolicy) {
            Write-ToolOutput 'Hello policy: Enabled via Group Policy (PassportForWork key present)'
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

        # Verdict covers Hello policy + hardware (MFA-readiness); Warning unless both are present
        $policyState = if ($helloPolicy) { 'policy configured' } else { 'no policy' }
        $bioSummary  = if ($bioDevices.Count -gt 0) { '{0} biometric device(s)' -f $bioDevices.Count } else { 'no biometric devices' }

        if ($helloPolicy -and $bioDevices.Count -gt 0) {
            Complete-ToolRun $run -Status Success -Summary ('Windows Hello/MFA ready: {0}; {1}' -f $policyState, $bioSummary)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('Windows Hello/MFA: {0}; {1}' -f $policyState, $bioSummary)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
