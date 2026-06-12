BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    Set-OutputSink -Sink Silent
    $script:IsAdmin = $true
    $script:RegistryData = @{
        Tools = @(
            @{ Id = 'safe-tool'; LegacyId = '20'; Name = 'Safe Tool'; Category = 'Test'
               Function = 'Invoke-SafeTool'; Description = 'reads things'
               RequiresAdmin = $false; SilentCapable = $true; Risk = 'ReadOnly'
               Tags = @('safe','reading') }
            @{ Id = 'loud-tool'; LegacyId = '99'; Name = 'Loud Tool'; Category = 'Test'
               Function = 'Invoke-LoudTool'; Description = 'needs a human'
               RequiresAdmin = $false; SilentCapable = $false; Risk = 'Disruptive'
               Tags = @('loud') }
        )
    }
    function Invoke-SafeTool {
        param([switch]$Silent)
        $run = New-ToolRun -Id 'safe-tool'
        Complete-ToolRun $run -Status Success -Summary 'ran fine'
    }
    function Invoke-LoudTool { param([switch]$Silent) }
}

AfterAll {
    Set-OutputSink -Sink Console
}

Describe 'Resolve-NmmTool' {
    It 'resolves by slug' {
        (Resolve-NmmTool -Query 'safe-tool').Name | Should -Be 'Safe Tool'
    }
    It 'resolves by legacy menu number' {
        (Resolve-NmmTool -Query '20').Name | Should -Be 'Safe Tool'
    }
    It 'returns nothing for an unknown query' {
        Resolve-NmmTool -Query 'no-such-tool' | Should -BeNullOrEmpty
    }
}

Describe 'Search-NmmTools' {
    It 'matches by tag' {
        @(Search-NmmTools -Term 'reading').Id | Should -Contain 'safe-tool'
    }
    It 'matches by partial name' {
        @(Search-NmmTools -Term 'loud').Id | Should -Contain 'loud-tool'
    }
}

Describe 'Invoke-NmmTool guards' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
    }
    It 'runs a silent-capable tool and reports its run status' {
        $tool = Resolve-NmmTool -Query 'safe-tool'
        Invoke-NmmTool -Tool $tool -Silent | Should -Be 'Success'
    }
    It 'refuses -Silent for a non-silent-capable tool' {
        $tool = Resolve-NmmTool -Query 'loud-tool'
        Invoke-NmmTool -Tool $tool -Silent | Should -Be 'Refused'
    }
    It 'refuses a tool that requires admin when not elevated' {
        $script:IsAdmin = $false
        $tools = @($script:RegistryData.Tools)
        $needsAdmin = $tools[0].Clone()
        $needsAdmin.RequiresAdmin = $true
        Invoke-NmmTool -Tool $needsAdmin | Should -Be 'Refused'
        $script:IsAdmin = $true
    }
}
