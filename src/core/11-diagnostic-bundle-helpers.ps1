# Shared helpers for Invoke-DiagnosticBundle. Plain functions (no registry
# entries) so their pure logic (summary formatting, zip naming) is unit
# testable without mocking the system calls the bundle's checks make.

function Build-DiagnosticBundleSummary {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Runs)

    $pass = @($Runs | Where-Object { $_.Status -eq 'Success' }).Count
    $warn = @($Runs | Where-Object { $_.Status -eq 'Warning' }).Count
    $fail = @($Runs | Where-Object { $_.Status -in 'Failed', 'Skipped' }).Count

    $lines = @()
    foreach ($run in ($Runs | Where-Object { $_.Status -in 'Warning', 'Failed', 'Skipped' })) {
        $tag = $run.Status.ToUpper()
        $lines += ('[{0}] {1,-28} - {2}' -f $tag, $run.Name, $run.Summary)
    }

    [PSCustomObject]@{
        PassCount = $pass
        WarnCount = $warn
        FailCount = $fail
        Lines     = $lines
    }
}

function Get-DiagnosticBundleZipPath {
    param(
        [Parameter(Mandatory)][string]$DesktopPath,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][datetime]$Timestamp
    )
    $name = 'NMM-Diagnostic-Bundle_{0}_{1:yyyyMMdd-HHmmss}.zip' -f $ComputerName, $Timestamp
    Join-Path $DesktopPath $name
}
