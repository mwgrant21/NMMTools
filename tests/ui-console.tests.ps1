BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\05-ui-console.ps1')
    Set-OutputSink -Sink Silent

    function New-FakeTool {
        param([int]$N, [string]$Category)
        @{ Id = "fake-tool-$N"; LegacyId = "$N"; Name = "Fake Tool $N"; Category = $Category
           Function = "Invoke-Fake$N"; Description = "fake description $N"; RequiresAdmin = $false
           SilentCapable = $true; Risk = 'ReadOnly'; Tags = @("fake$N") }
    }
}

AfterAll {
    Set-OutputSink -Sink Console
}

Describe 'Show-LandingMenu adaptive layout' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
    }

    It 'lists tools directly and returns an empty map when the registry is small' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool 11 'Diagnostics'), (New-FakeTool 20 'Diagnostics') ) }
        $raw = Show-LandingMenu 6>&1
        $map = $raw | Where-Object { $_ -is [hashtable] }
        $text = ($raw | Where-Object { $_ -isnot [hashtable] } | ForEach-Object { "$_" }) -join "`n"
        $null -eq $map | Should -BeFalse       # guard: a missing return would also give Count 0
        $map -is [hashtable] | Should -BeTrue
        $map.Count | Should -Be 0
        $text | Should -Match 'Fake Tool 11'
        $text | Should -Match 'Fake Tool 20'
        $text | Should -Not -Match 'Diagnostics \(\d+ tools\)'
    }

    It 'orders the flat list by numeric LegacyId' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool 9 'Diagnostics'), (New-FakeTool 100 'Diagnostics'), (New-FakeTool 20 'Diagnostics') ) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | Where-Object { $_ -isnot [hashtable] } | ForEach-Object { "$_" }) -join "`n"
        $text.IndexOf('Fake Tool 9') | Should -BeLessThan $text.IndexOf('Fake Tool 20')
        $text.IndexOf('Fake Tool 20') | Should -BeLessThan $text.IndexOf('Fake Tool 100')
    }

    It 'shows categories and returns a populated map when the registry is large' {
        $tools = @()
        foreach ($i in 1..9)   { $tools += New-FakeTool $i 'CategoryA' }
        foreach ($i in 11..19) { $tools += New-FakeTool $i 'CategoryB' }
        $script:RegistryData = @{ Tools = $tools }   # 18 tools, 2 categories
        $raw = Show-LandingMenu 6>&1
        $map = $raw | Where-Object { $_ -is [hashtable] }
        $text = ($raw | Where-Object { $_ -isnot [hashtable] } | ForEach-Object { "$_" }) -join "`n"
        $map.Count | Should -Be 2
        $map['A'] | Should -Be 'CategoryA'
        $text | Should -Match 'CategoryA \(9 tools\)'
        $text | Should -Not -Match 'Fake Tool 11'   # tool names not listed in category mode
    }

    It 'uses flat mode for a single category even when over the size threshold' {
        $tools = @()
        foreach ($i in 1..20) { $tools += New-FakeTool $i 'OnlyCat' }
        $script:RegistryData = @{ Tools = $tools }
        $raw = Show-LandingMenu 6>&1
        $map = $raw | Where-Object { $_ -is [hashtable] }
        $null -eq $map | Should -BeFalse       # guard: a missing return would also give Count 0
        $map -is [hashtable] | Should -BeTrue
        $map.Count | Should -Be 0
    }
}
