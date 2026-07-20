function Invoke-DiagnosticBundle {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    $workDir = $null
    try {
        $run = New-ToolRun -Id 'diagnostic-bundle'

        $window = Read-ToolChoice -Prompt 'Time window for history-based checks' `
            -Choices @('24h', '7d') -Default '24h' -Silent:$Silent
        $hoursBack = 24
        if ($window -eq '7d') { $hoursBack = 168 }
        Write-ToolOutput ('Time window: {0} ({1}h)' -f $window, $hoursBack)

        $windowAware = 'Get-EventLogErrors', 'Get-ReliabilityHistory', 'Get-CrashDumpInventory'
        $checks = @(
            'Get-EventLogErrors',
            'Get-ReliabilityHistory',
            'Get-WindowsUpdates',
            'Get-DeviceManagerErrors',
            'Get-NetworkDiagnostics',
            'Get-AzureADHealthCheck',
            'Get-GroupPolicyResult',
            'Get-BSODCrashDumpParser',
            'Get-CrashDumpInventory',
            'Get-InstalledSoftware',
            'Get-SystemUptime',
            'Get-PendingRebootStatus'
        )

        $timestamp = Get-Date
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $workDir = Join-Path $env:TEMP ('NMMTools-Bundle-{0}-{1:yyyyMMdd-HHmmss}' -f $env:COMPUTERNAME, $timestamp)
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null

        $startIdx = $script:ToolRuns.Count
        foreach ($fn in $checks) {
            Write-ToolOutput ('Running {0}...' -f $fn) -Level Detail
            Start-ToolOutputCapture
            try {
                if ($windowAware -contains $fn) {
                    & $fn -Silent:$Silent -HoursBack $hoursBack
                } else {
                    & $fn -Silent:$Silent
                }
            } catch {
                Write-ToolOutput ('{0} threw: {1}' -f $fn, $_.Exception.Message) -Level Error
            }
            $raw = Stop-ToolOutputCapture
            $rawFile = Join-Path $workDir ('{0}.txt' -f $fn)
            Set-Content -Path $rawFile -Value $raw -Encoding UTF8
        }

        $bundleRuns = @($script:ToolRuns.GetRange($startIdx, $script:ToolRuns.Count - $startIdx))
        $summary = Build-DiagnosticBundleSummary -Runs $bundleRuns

        Write-ToolOutput ('Health summary   PASS {0}   WARN {1}   FAIL {2}' -f
            $summary.PassCount, $summary.WarnCount, $summary.FailCount)
        foreach ($line in $summary.Lines) { Write-ToolOutput ('  ' + $line) -Level Detail }

        $summaryLines = @()
        $summaryLines += 'NMM Diagnostic Bundle'
        $summaryLines += ('Time window: {0}' -f $window)
        $summaryLines += ('Health summary   PASS {0}   WARN {1}   FAIL {2}' -f
            $summary.PassCount, $summary.WarnCount, $summary.FailCount)
        $summaryLines += $summary.Lines
        $summaryLines += ''
        $summaryLines += (Export-TicketSummary -Runs $bundleRuns)
        $summaryFile = Join-Path $workDir 'summary.txt'
        Set-Content -Path $summaryFile -Value ($summaryLines -join "`r`n") -Encoding UTF8

        $zipPath = Get-DiagnosticBundleZipPath -DesktopPath $desktopPath -ComputerName $env:COMPUTERNAME -Timestamp $timestamp
        Compress-Archive -Path (Join-Path $workDir '*') -DestinationPath $zipPath -Force -ErrorAction Stop

        Write-ToolOutput ('Bundle: {0}' -f $zipPath) -Level Success

        Complete-ToolRun $run -Status Success -Summary (
            '{0} checks | PASS {1} WARN {2} FAIL {3} | {4}' -f
            $checks.Count, $summary.PassCount, $summary.WarnCount, $summary.FailCount, $zipPath)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
    finally {
        if ($workDir -and (Test-Path -LiteralPath $workDir)) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
