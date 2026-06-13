function Get-IntuneHealthCheck {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'intune-health'

        # Enumerate MDM enrollment subkeys; non-admin sessions may not be able to read this hive
        $mdmEnrollments = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Enrollments\*' -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderID -like '*MS DM Server*' })

        if ($mdmEnrollments.Count -eq 0) {
            # Improvement over v8: empty result may mean not enrolled OR may mean access denied - flag both
            Complete-ToolRun $run -Status Warning -Summary 'No MDM enrollment found (note: reading enrollment state may require admin)'
            return
        }

        # Report provider and UPN for each matched enrollment record
        foreach ($enrollment in $mdmEnrollments) {
            $upn      = if ($enrollment.UPN)        { $enrollment.UPN }        else { '(UPN not set)' }
            $provider = if ($enrollment.ProviderID) { $enrollment.ProviderID } else { '(provider unknown)' }
            Write-ToolOutput ('Provider : {0}' -f $provider) -Level Detail
            Write-ToolOutput ('UPN      : {0}' -f $upn)      -Level Detail
        }

        $firstUpn = if ($mdmEnrollments[0].UPN) { $mdmEnrollments[0].UPN } else { 'UPN not set' }
        Complete-ToolRun $run -Status Success -Summary ('Enrolled in Intune/MDM; UPN: {0}' -f $firstUpn)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
