BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\11-diagnostic-bundle-helpers.ps1')
}

Describe 'Build-DiagnosticBundleSummary' {
    It 'counts pass, warn, and fail runs separately' {
        $runs = @(
            [PSCustomObject]@{ Name = 'A'; Status = 'Success'; Summary = 'ok' }
            [PSCustomObject]@{ Name = 'B'; Status = 'Warning'; Summary = 'reboot pending' }
            [PSCustomObject]@{ Name = 'C'; Status = 'Failed';  Summary = 'query failed' }
            [PSCustomObject]@{ Name = 'D'; Status = 'Skipped'; Summary = '' }
        )
        $result = Build-DiagnosticBundleSummary -Runs $runs
        $result.PassCount | Should -Be 1
        $result.WarnCount | Should -Be 1
        $result.FailCount | Should -Be 2
    }

    It 'formats one line per non-passing run, omitting Success' {
        $runs = @(
            [PSCustomObject]@{ Name = 'System Information'; Status = 'Success'; Summary = 'ok' }
            [PSCustomObject]@{ Name = 'Pending Reboot'; Status = 'Warning'; Summary = 'Windows Update requires reboot' }
        )
        $result = Build-DiagnosticBundleSummary -Runs $runs
        $result.Lines.Count | Should -Be 1
        $result.Lines[0] | Should -Match '\[WARNING\]'
        $result.Lines[0] | Should -Match 'Pending Reboot'
        $result.Lines[0] | Should -Match 'Windows Update requires reboot'
    }

    It 'handles an empty run set without throwing' {
        { Build-DiagnosticBundleSummary -Runs @() } | Should -Not -Throw
        $result = Build-DiagnosticBundleSummary -Runs @()
        $result.PassCount | Should -Be 0
        $result.Lines.Count | Should -Be 0
    }
}

Describe 'Get-DiagnosticBundleZipPath' {
    It 'builds a Desktop-rooted path with computer name and timestamp' {
        $ts = Get-Date '2026-07-19 22:10:00'
        $path = Get-DiagnosticBundleZipPath -DesktopPath 'C:\Users\tech\Desktop' -ComputerName 'WKSTN-042' -Timestamp $ts
        $path | Should -Be 'C:\Users\tech\Desktop\NMM-Diagnostic-Bundle_WKSTN-042_20260719-221000.zip'
    }
}
