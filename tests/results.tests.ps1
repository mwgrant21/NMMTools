BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\06-usage.ps1')
    Set-OutputSink -Sink Silent
    $script:UsageFilePathOverride = Join-Path $env:TEMP ('nmm-usage-results-{0}.json' -f (Get-Random))
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
    if ($script:UsageFilePathOverride -and (Test-Path $script:UsageFilePathOverride)) {
        Remove-Item $script:UsageFilePathOverride -Force -ErrorAction SilentlyContinue
    }
    $script:UsageFilePathOverride = $null
}

Describe 'Tool run tracking' {
    BeforeEach { $script:ToolRuns = New-Object System.Collections.ArrayList }

    It 'records a completed run with status and duration' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'all good'
        $run.Status | Should -Be 'Success'
        $run.Summary | Should -Be 'all good'
        $run.Duration | Should -BeOfType [TimeSpan]
        $script:ToolRuns | Should -Contain $run
    }

    It 'resolves the display name from the registry' {
        $run = New-ToolRun -Id 'fake-tool'
        $run.Name | Should -Be 'Fake Tool'
        Complete-ToolRun $run -Status Skipped -Summary ''
    }

    It 'falls back to the Id when the tool is not in the registry' {
        $run = New-ToolRun -Id 'not-registered'
        $run.Name | Should -Be 'not-registered'
        Complete-ToolRun $run -Status Skipped
    }

    It 'warns instead of throwing when the run reference is null' {
        { Complete-ToolRun $null -Status Failed -Summary 'x' } | Should -Not -Throw
    }

    It 'ignores a duplicate completion instead of overwriting the result' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'first'
        Complete-ToolRun $run -Status Failed -Summary 'second'
        $run.Status | Should -Be 'Success'
        $run.Summary | Should -Be 'first'
    }

    It 'formats hour-plus durations with an hours component' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'long run'
        $run.Duration = New-TimeSpan -Minutes 65
        Export-TicketSummary | Should -Match '1:05:00'
    }
}

Describe 'Export-TicketSummary' {
    BeforeEach { $script:ToolRuns = New-Object System.Collections.ArrayList }

    It 'renders machine, user, and each run line' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Failed -Summary 'simulated failure'
        $text = Export-TicketSummary
        $text | Should -Match ([regex]::Escape($env:COMPUTERNAME))
        $text | Should -Match ([regex]::Escape($env:USERNAME))
        $text | Should -Match 'FAILED.*Fake Tool'
        $text | Should -Match 'simulated failure'
    }

    It 'notes an empty session' {
        Export-TicketSummary | Should -Match 'No tools were run this session\.'
    }

    It 'writes the summary to a file when -Path is given' {
        $file = Join-Path $env:TEMP "nmm-ticket-$(Get-Random).txt"
        Export-TicketSummary -Path $file | Out-Null
        Test-Path $file | Should -BeTrue
        Get-Content $file -Raw | Should -Match 'NMM Toolkit Session Summary'
        Remove-Item $file -Force
    }
}

Describe 'Usage recording hook' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
        Mock Add-NmmUsage { }
    }
    It 'records a use when the sink is interactive (not Silent)' {
        Set-OutputSink -Sink Console
        try {
            $run = New-ToolRun -Id 'fake-tool'
            Complete-ToolRun $run -Status Success -Summary 'ok'
        } finally {
            Set-OutputSink -Sink Silent
        }
        Assert-MockCalled Add-NmmUsage -Times 1 -Scope It -ParameterFilter { $Id -eq 'fake-tool' }
    }
    It 'does not record a use under the Silent sink' {
        $run = New-ToolRun -Id 'fake-tool'
        Complete-ToolRun $run -Status Success -Summary 'ok'
        Assert-MockCalled Add-NmmUsage -Times 0 -Scope It
    }
}
