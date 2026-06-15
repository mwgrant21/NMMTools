BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\05-ui-console.ps1')
    Set-OutputSink -Sink Silent

    function New-FakeTool {
        param([string]$Legacy, [string]$Category, [string]$Name, [string]$Desc = 'fake description')
        @{ Id = "fake-$Legacy"; LegacyId = "$Legacy"; Name = $Name; Category = $Category
           Function = "Invoke-Fake$Legacy"; Description = $Desc; RequiresAdmin = $false
           SilentCapable = $true; Risk = 'ReadOnly'; Tags = @('fake') }
    }
}

AfterAll {
    Set-OutputSink -Sink Console
}

Describe 'Show-LandingMenu all-visible layout' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
    }

    It 'lists every tool name and its description, grouped by category header with counts' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '1'  'Diagnostics' 'System Information'      'os hardware summary'),
            (New-FakeTool '2'  'Diagnostics' 'Disk Space Analysis'    'per volume capacity'),
            (New-FakeTool '54' 'User'        'Windows Search Rebuild'  'restart wsearch rebuild index')
        ) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'System Information'
        $text | Should -Match 'os hardware summary'
        $text | Should -Match 'Disk Space Analysis'
        $text | Should -Match 'Windows Search Rebuild'
        $text | Should -Match 'restart wsearch rebuild index'
        $text | Should -Match '-- Diagnostics \(2 tools\) --'
        $text | Should -Match '-- User \(1 tools\) --'
    }

    It 'returns no value (no category-letter map)' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool '1' 'Diagnostics' 'A'), (New-FakeTool '2' 'Cloud' 'B') ) }
        $result = Show-LandingMenu 6>$null
        $result | Should -BeNullOrEmpty
    }

    It 'orders tools within a category by LegacyId, numeric before Q#, without throwing on Q ids' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool 'Q3' 'QuickFix' 'QF Three'),
            (New-FakeTool 'Q1' 'QuickFix' 'QF One'),
            (New-FakeTool '10' 'QuickFix' 'Ten'),
            (New-FakeTool '2'  'QuickFix' 'Two')
        ) }
        $script:raw = $null
        { $script:raw = Show-LandingMenu 6>&1 } | Should -Not -Throw
        $raw = $script:raw
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text.IndexOf('Two')    | Should -BeLessThan $text.IndexOf('Ten')
        $text.IndexOf('Ten')    | Should -BeLessThan $text.IndexOf('QF One')
        $text.IndexOf('QF One') | Should -BeLessThan $text.IndexOf('QF Three')
    }

    It 'flags admin tools and shows the run/search/exit hint' {
        $admin = New-FakeTool '93' 'Security' 'Defender Status'
        $admin.RequiresAdmin = $true
        $script:RegistryData = @{ Tools = @($admin) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'Defender Status \[admin\]'
        $text | Should -Match 'Q3'
        $text | Should -Match 'X = exit'
    }
}

Describe 'Get-NmmLegacyIdSortKey' {
    It 'sorts numeric ids as integers' {
        (Get-NmmLegacyIdSortKey '9') | Should -BeLessThan (Get-NmmLegacyIdSortKey '10')
    }
    It 'sorts Q ids after numeric ids and in Q order' {
        (Get-NmmLegacyIdSortKey '106') | Should -BeLessThan (Get-NmmLegacyIdSortKey 'Q1')
        (Get-NmmLegacyIdSortKey 'Q1')  | Should -BeLessThan (Get-NmmLegacyIdSortKey 'Q9')
    }
    It 'does not throw on an unexpected id' {
        { Get-NmmLegacyIdSortKey 'weird' } | Should -Not -Throw
    }
}

Describe 'Get-WrappedLines' {
    It 'wraps text to the given width without exceeding it' {
        $lines = Get-WrappedLines -Text 'the quick brown fox jumps over the lazy dog' -Width 15
        @($lines).Count | Should -BeGreaterThan 1
        foreach ($l in $lines) { $l.Length | Should -BeLessOrEqual 15 }
    }
    It 'returns an empty array for blank text' {
        @(Get-WrappedLines -Text '   ' -Width 40).Count | Should -Be 0
    }
}
