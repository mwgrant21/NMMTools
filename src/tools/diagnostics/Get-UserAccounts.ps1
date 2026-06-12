function Get-UserAccounts {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'user-accounts'

        $users = @(Get-LocalUser | Select-Object Name, Enabled, LastLogon)

        if ($users.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No local user accounts found'
            return
        }

        # Scan rows use Detail; each user account is a table row
        foreach ($u in $users) {
            $lastLogonStr = if ($u.LastLogon) { '{0:g}' -f $u.LastLogon } else { 'never' }
            Write-ToolOutput ('{0,-24} Enabled: {1,-5} LastLogon: {2}' -f
                $u.Name, $u.Enabled, $lastLogonStr) -Level Detail
        }

        $enabledCount  = @($users | Where-Object { $_.Enabled }).Count
        $disabledCount = @($users | Where-Object { -not $_.Enabled }).Count
        Complete-ToolRun $run -Status Success -Summary (
            '{0} local users ({1} enabled, {2} disabled)' -f $users.Count, $enabledCount, $disabledCount)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
