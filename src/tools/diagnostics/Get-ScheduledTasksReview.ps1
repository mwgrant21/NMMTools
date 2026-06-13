function Get-ScheduledTasksReview {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'scheduled-tasks'

        # v8: Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } — all tasks, not filtered to non-Microsoft
        $tasks = @(Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } | Sort-Object TaskName)

        if ($tasks.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No active (non-Disabled) scheduled tasks found'
            return
        }

        Write-ToolOutput ('Active scheduled tasks: {0}' -f $tasks.Count)
        # Each task is a scan row; Detail level for the listing
        foreach ($task in $tasks) {
            Write-ToolOutput ('{0,-52}  [{1}]' -f $task.TaskName, $task.State) -Level Detail
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} active scheduled task(s) found' -f $tasks.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
