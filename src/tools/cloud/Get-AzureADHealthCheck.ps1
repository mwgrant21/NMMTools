function Get-AzureADHealthCheck {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'azure-ad-health'

        # Run dsregcmd and extract the four join-state fields - offline-valid, no network needed
        $dsregOutput = & dsregcmd /status
        $matched = @($dsregOutput | Select-String 'AzureAdJoined', 'DomainJoined', 'WorkplaceJoined', 'DeviceId')

        if ($matched.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'dsregcmd returned no join-state lines (command unavailable or device not AAD-capable)'
            return
        }

        # Emit each matched join-state line at Detail level
        foreach ($line in $matched) {
            Write-ToolOutput $line.Line.Trim() -Level Detail
        }

        # Build one-line verdict from parsed YES/NO values
        $azJoined  = $matched | Where-Object { $_.Line -match 'AzureAdJoined\s*:\s*YES' }
        $domJoined = $matched | Where-Object { $_.Line -match 'DomainJoined\s*:\s*YES' }
        $wpJoined  = $matched | Where-Object { $_.Line -match 'WorkplaceJoined\s*:\s*YES' }

        $parts = @()
        if ($azJoined)  { $parts += 'Azure AD joined' }   else { $parts += 'not Azure AD joined' }
        if ($domJoined) { $parts += 'domain joined' }      else { $parts += 'not domain joined' }
        if ($wpJoined)  { $parts += 'workplace joined' }

        Complete-ToolRun $run -Status Success -Summary ($parts -join '; ')
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
