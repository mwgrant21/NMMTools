function Get-ReliabilityHistory {
    [CmdletBinding()]
    param(
        [switch]$Silent,   # required by dispatcher even when unused
        [int]$HoursBack = 24
    )

    $run = $null
    try {
        $run = New-ToolRun -Id 'reliability-history'

        $cutoff = (Get-Date).AddHours(-$HoursBack)

        $records = @(Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction Stop |
            Where-Object { $_.TimeGenerated -ge $cutoff })

        if ($records.Count -eq 0) {
            Write-ToolOutput ('No reliability records in the last {0}h.' -f $HoursBack)
            Complete-ToolRun $run -Status Success -Summary ('0 reliability events in last {0}h' -f $HoursBack)
            return
        }

        $bySource = $records | Group-Object SourceName, EventIdentifier | Sort-Object Count -Descending

        Write-ToolOutput ('Reliability events in last {0}h: {1}' -f $HoursBack, $records.Count)
        foreach ($grp in ($bySource | Select-Object -First 10)) {
            $latest = ($grp.Group | Sort-Object TimeGenerated -Descending | Select-Object -First 1)
            Write-ToolOutput ('{0}x  {1}  (event {2})  last {3:g}' -f
                $grp.Count, $latest.SourceName, $latest.EventIdentifier, $latest.TimeGenerated) -Level Detail
        }

        $topSources = ($bySource | Select-Object -First 3 | ForEach-Object { $_.Group[0].SourceName }) -join ', '
        Complete-ToolRun $run -Status Warning -Summary (
            '{0} reliability events in last {1}h; top source(s): {2}' -f $records.Count, $HoursBack, $topSources)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
