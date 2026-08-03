function Get-GroupPolicyResult {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'group-policy-result'

        $output = & gpresult /r 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($output)) {
            Write-ToolOutput 'gpresult returned no data.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'gpresult returned no data (RSoP service issue)'
            return
        }

        foreach ($line in ($output -split "`r?`n")) {
            if ($line.Trim()) { Write-ToolOutput $line -Level Detail }
        }

        $lastApplied = ($output -split "`r?`n" | Where-Object { $_ -match 'Last time Group Policy was applied' } | Select-Object -First 1)
        $summary = 'gpresult completed'
        if ($lastApplied) { $summary = $lastApplied.Trim() }
        Complete-ToolRun $run -Status Success -Summary $summary
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
