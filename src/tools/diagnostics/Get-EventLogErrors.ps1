function Get-EventLogErrors {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'event-log-errors'

        $yesterday = (Get-Date).AddHours(-24)

        $evtErrors = @()
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName   = 'System', 'Application'
            Level     = 2
            StartTime = $yesterday
        } -MaxEvents 20 -ErrorAction SilentlyContinue -ErrorVariable evtErrors)

        # Distinguish real access/query failures from the benign "no matching events" non-terminating error
        $realFailures = @($evtErrors | Where-Object { $_.Exception.Message -notlike '*No events were found*' })
        if ($realFailures.Count -gt 0 -and $events.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary ('Event log query failed: {0}' -f $realFailures[0].Exception.Message)
            return
        }

        if ($events.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary '0 errors in last 24h'
            return
        }

        Write-ToolOutput ('Recent errors found: {0} (showing up to 10)' -f $events.Count)
        # Scan rows use Detail; each event is a table row
        foreach ($e in ($events | Select-Object -First 10)) {
            Write-ToolOutput ('{0:g}  {1}  ID {2}' -f $e.TimeCreated, $e.ProviderName, $e.Id) -Level Detail
        }

        Complete-ToolRun $run -Status Warning -Summary ('{0} errors in last 24h' -f $events.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
