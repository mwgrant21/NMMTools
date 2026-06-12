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
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][ValidateSet('Success','Failed','Warning','Skipped')][string]$Status,
        [string]$Summary = ''
    )
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
        if ($run.Duration) { $dur = '{0:mm\:ss}' -f $run.Duration }
        [void]$sb.AppendLine(('[{0}] {1} ({2})' -f $run.Status.ToUpper(), $run.Name, $dur))
        if ($run.Summary) { [void]$sb.AppendLine('    ' + $run.Summary) }
    }
    $text = $sb.ToString()
    if ($Path) { Set-Content -Path $Path -Value $text -Encoding UTF8 }
    return $text
}
