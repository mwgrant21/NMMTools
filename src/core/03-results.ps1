# Session run tracking. Every tool run starts with New-ToolRun and ends with
# Complete-ToolRun (success OR failure), so the transcript is always complete.

$script:ToolRuns = New-Object System.Collections.ArrayList
$script:SessionStart = Get-Date

function New-ToolRun {
    param([Parameter(Mandatory)][string]$Id)
    $tool = @($script:RegistryData.Tools) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    $name = $Id
    if ($tool) { $name = $tool.Name }
    $run = [PSCustomObject]@{
        Id       = $Id
        Name     = $name
        Started  = Get-Date
        Duration = $null
        Status   = 'Running'
        Summary  = ''
    }
    [void]$script:ToolRuns.Add($run)
    Write-ToolOutput ''
    Write-ToolOutput ('=== {0} ===' -f $name)
    return $run
}

function Complete-ToolRun {
    param(
        $Run,
        [Parameter(Mandatory)][ValidateSet('Success','Failed','Warning','Skipped')][string]$Status,
        [string]$Summary = ''
    )
    if ($null -eq $Run) {
        Write-ToolOutput '[WARNING] Complete-ToolRun: run reference is null - was New-ToolRun called?' -Level Warning
        return
    }
    if ($Run.Status -ne 'Running') {
        Write-ToolOutput ("[WARNING] Complete-ToolRun: '{0}' already completed as {1}; ignoring duplicate completion." -f $Run.Name, $Run.Status) -Level Warning
        return
    }
    $Run.Status = $Status
    $Run.Summary = $Summary
    $Run.Duration = (Get-Date) - $Run.Started
    $level = switch ($Status) {
        'Success' { 'Success' }
        'Failed'  { 'Error' }
        'Warning' { 'Warning' }
        default   { 'Detail' }
    }
    Write-ToolOutput ('[{0}] {1}' -f $Status.ToUpper(), $Summary) -Level $level

    # Record the use for the menu's Common Fixes section - interactive runs only, so PDQ/-Silent
    # endpoint runs leave no usage file. Placed last so the null-run and duplicate-completion
    # early-returns above skip it. Add-NmmUsage swallows IO errors, so this cannot break a run.
    if ($script:OutputSink -ne 'Silent') {
        Add-NmmUsage -Id $Run.Id
    }
}

function Export-TicketSummary {
    param([string]$Path)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('NMM Toolkit Session Summary')
    [void]$sb.AppendLine(('Computer: {0}    User: {1}' -f $env:COMPUTERNAME, $env:USERNAME))
    [void]$sb.AppendLine(('Session:  {0:g} - {1:g}' -f $script:SessionStart, (Get-Date)))
    [void]$sb.AppendLine('')
    if ($script:ToolRuns.Count -eq 0) {
        [void]$sb.AppendLine('No tools were run this session.')
    }
    foreach ($run in $script:ToolRuns) {
        $dur = '--:--'
        if ($run.Duration) {
            if ($run.Duration.TotalHours -ge 1) {
                $dur = '{0:h\:mm\:ss}' -f $run.Duration
            } else {
                $dur = '{0:mm\:ss}' -f $run.Duration
            }
        }
        [void]$sb.AppendLine(('[{0}] {1} ({2})' -f $run.Status.ToUpper(), $run.Name, $dur))
        if ($run.Summary) { [void]$sb.AppendLine('    ' + $run.Summary) }
    }
    $text = $sb.ToString()
    if ($Path) {
        try {
            Set-Content -Path $Path -Value $text -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-ToolOutput "Warning: could not write ticket summary to '$Path' - $_" -Level Warning
        }
    }
    return $text
}
