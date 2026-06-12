BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    Set-OutputSink -Sink Silent
    # Minimal registry stand-in so New-ToolRun can resolve names
    $script:RegistryData = @{
        Tools = @(
            @{ Id = 'fake-tool'; Name = 'Fake Tool'; LegacyId = '0'; Category = 'Test'
               Function = 'Invoke-Fake'; Description = 'x'; RequiresAdmin = $false
               SilentCapable = $true; Risk = 'ReadOnly'; Tags = @('fake') }
        )
    }
}

AfterAll {
    Set-OutputSink -Sink Console
}

Describe 'Tool run tracking' {
    It 'records a completed run with status and duration' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'all good'
        $run.Status | Should -Be 'Success'
        $run.Summary | Should -Be 'all good'
        $run.Duration | Should -Not -BeNullOrEmpty
        $script:ToolRuns | Should -Contain $run
    }

    It 'resolves the display name from the registry' {
        $run = New-ToolRun -Id 'fake-tool'
        $run.Name | Should -Be 'Fake Tool'
        Complete-ToolRun $run -Status Skipped -Summary ''
    }
}

Describe 'Export-TicketSummary' {
    It 'renders machine, user, and each run line' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Failed -Summary 'simulated failure'
        $text = Export-TicketSummary
        $text | Should -Match ([regex]::Escape($env:COMPUTERNAME))
        $text | Should -Match ([regex]::Escape($env:USERNAME))
        $text | Should -Match 'FAILED.*Fake Tool'
        $text | Should -Match 'simulated failure'
    }

    It 'writes the summary to a file when -Path is given' {
        $file = Join-Path $env:TEMP "nmm-ticket-$(Get-Random).txt"
        Export-TicketSummary -Path $file | Out-Null
        Test-Path $file | Should -BeTrue
        Remove-Item $file -Force
    }
}
