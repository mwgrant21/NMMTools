function Update-GroupPolicy {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'group-policy-update'

        # Precheck: domain membership - local policy always applies; machine policy also applies when domain-joined
        $domainJoined = $false
        try {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $domainJoined = [bool]$cs.PartOfDomain
        } catch {
            Write-ToolOutput 'Unable to determine domain membership; assuming workgroup.' -Level Detail
        }

        if ($domainJoined) {
            Write-ToolOutput 'Domain-joined: both machine and user policy will be refreshed.' -Level Detail
        } else {
            Write-ToolOutput 'Not domain-joined: only local policy applies; gpupdate will still refresh it.' -Level Detail
        }

        # Precheck: admin - machine policy is silently skipped by gpupdate when not elevated
        if (-not $script:IsAdmin) {
            Write-ToolOutput 'Not running as admin: machine policy refresh will be skipped; user policy will still apply.' -Level Detail
        }

        # Run gpupdate /force; in PS 5.1, 2>&1 wraps stderr lines as ErrorRecord objects - stringify each
        Write-ToolOutput 'Running gpupdate /force...' -Level Detail
        $gpOutput = & gpupdate /force 2>&1
        $exitCode = $LASTEXITCODE

        foreach ($line in $gpOutput) {
            $text = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                Write-ToolOutput $text -Level Detail
            }
        }

        # Verdict: never Failed just for DC unreachability - that is a Warning
        if ($exitCode -eq 0) {
            $scopeNote = 'user'
            if ($script:IsAdmin) { $scopeNote = 'user+machine' }
            Complete-ToolRun $run -Status Success -Summary ('Group Policy refreshed ({0})' -f $scopeNote)
        } else {
            Complete-ToolRun $run -Status Warning -Summary (
                'gpupdate completed with warnings (exit {0}); see detail' -f $exitCode)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
