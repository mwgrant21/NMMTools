function Get-ServicesStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'services-status'

        $groups = @(Get-Service | Group-Object Status | ForEach-Object {
            [PSCustomObject]@{
                Status = $_.Name
                Count  = $_.Count
            }
        })

        foreach ($g in $groups) {
            $level = if ($g.Status -eq 'Stopped') { 'Warning' } else { 'Info' }
            Write-ToolOutput ('{0,-20} {1} service(s)' -f $g.Status, $g.Count) -Level $level
        }

        $summaryParts = $groups | ForEach-Object { '{0}: {1}' -f $_.Status, $_.Count }
        Complete-ToolRun $run -Status Success -Summary ($summaryParts -join '; ')
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
