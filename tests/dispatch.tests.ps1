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
            @{ Id = 'risky-tool'; LegacyId = '77'; Name = 'Risky Tool'; Category = 'Test'
               Function = 'Invoke-RiskyTool'; Description = 'silent-capable but disruptive'
               RequiresAdmin = $false; SilentCapable = $true; Risk = 'Disruptive'
               Tags = @('risky') }
            @{ Id = 'ghost-caller'; LegacyId = '78'; Name = 'Ghost Caller'; Category = 'Test'
               Function = 'Invoke-GhostCaller'; Description = 'calls a command that does not exist'
               RequiresAdmin = $false; SilentCapable = $true; Risk = 'ReadOnly'
               Tags = @('ghost') }
        )
    }
    function Invoke-SafeTool {
        param([switch]$Silent)
        $run = New-ToolRun -Id 'safe-tool'
        Complete-ToolRun $run -Status Success -Summary 'ran fine'
    }
    function Invoke-LoudTool { param([switch]$Silent) }
    function Invoke-RiskyTool {
        param([switch]$Silent)
        $run = New-ToolRun -Id 'risky-tool'
        Complete-ToolRun $run -Status Success -Summary 'risky but fine'
    }
    # Mirrors the real tools (Get-RingCentralStatus, Repair-PrinterIssues, ...) that
    # call a module cmdlet BEFORE entering their try/catch, so a missing command
    # escapes the tool and reaches Invoke-NmmTool's own handler.
    function Invoke-GhostCaller {
        param([switch]$Silent)
        Get-NoSuchCommandAtAll | Out-Null
        $run = New-ToolRun -Id 'ghost-caller'
        Complete-ToolRun $run -Status Success -Summary 'never reached'
    }
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
    It 'does not throw on bracket metacharacters in the term' {
        { Search-NmmTools -Term '[x' } | Should -Not -Throw
    }
    It 'matches by description substring' {
        @(Search-NmmTools -Term 'human').Id | Should -Contain 'loud-tool'
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
    It 'refuses -Silent for a disruptive tool without -Force' {
        $tool = Resolve-NmmTool -Query 'risky-tool'
        Invoke-NmmTool -Tool $tool -Silent | Should -Be 'Refused'
    }
    It 'runs a disruptive silent-capable tool with -Silent -Force' {
        $tool = Resolve-NmmTool -Query 'risky-tool'
        Invoke-NmmTool -Tool $tool -Silent -Force | Should -Be 'Success'
    }
    It 'returns Failed instead of throwing when the tool function does not exist' {
        $ghost = @{ Id = 'ghost'; LegacyId = '0'; Name = 'Ghost'; Category = 'Test'
                    Function = 'Invoke-DoesNotExist'; Description = 'x'
                    RequiresAdmin = $false; SilentCapable = $true; Risk = 'ReadOnly'; Tags = @('x') }
        Invoke-NmmTool -Tool $ghost -Silent | Should -Be 'Failed'
    }
}

Describe 'Invoke-NmmTool CommandNotFoundException reporting' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
    }

    It 'names the missing command, not the tool, when the tool body calls a command that does not exist' {
        $tool = Resolve-NmmTool -Query 'ghost-caller'
        Start-ToolOutputCapture
        $status = Invoke-NmmTool -Tool $tool -Silent
        $text = Stop-ToolOutputCapture

        $status | Should -Be 'Failed'
        $text   | Should -Match 'Get-NoSuchCommandAtAll'
        $text   | Should -Not -Match 'registry/implementation drift'
    }

    It 'still blames registry/implementation drift when the tool function itself is missing' {
        $ghost = @{ Id = 'ghost'; LegacyId = '0'; Name = 'Ghost'; Category = 'Test'
                    Function = 'Invoke-DoesNotExist'; Description = 'x'
                    RequiresAdmin = $false; SilentCapable = $true; Risk = 'ReadOnly'; Tags = @('x') }
        Start-ToolOutputCapture
        $status = Invoke-NmmTool -Tool $ghost -Silent
        $text = Stop-ToolOutputCapture

        $status | Should -Be 'Failed'
        $text   | Should -Match 'registry/implementation drift'
        $text   | Should -Match 'Invoke-DoesNotExist'
    }
}
