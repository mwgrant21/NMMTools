BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\03-results.ps1')
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\05-ui-console.ps1')
    . (Join-Path $repoRoot 'src\core\06-usage.ps1')
    Set-OutputSink -Sink Silent
    # Point usage at a non-existent file so the un-mocked existing tests see no Common Fixes section.
    $script:UsageFilePathOverride = Join-Path $env:TEMP ('nmm-usage-ui-none-{0}.json' -f (Get-Random))

    function New-FakeTool {
        param([string]$Legacy, [string]$Category, [string]$Name, [string]$Desc = 'fake description',
              [string]$Risk = 'ReadOnly', [bool]$Admin = $false)
        @{ Id = "fake-$Legacy"; LegacyId = "$Legacy"; Name = $Name; Category = $Category
           Function = "Invoke-Fake$Legacy"; Description = $Desc; RequiresAdmin = $Admin
           SilentCapable = $true; Risk = $Risk; Tags = @('fake') }
    }
}

AfterAll {
    Set-OutputSink -Sink Console
    $script:UsageFilePathOverride = $null
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

Describe 'Get-CategoryColor' {
    It 'maps each category to its v8 color' {
        (Get-CategoryColor 'Diagnostics') | Should -Be 'Cyan'
        (Get-CategoryColor 'Cloud')       | Should -Be 'Yellow'
        (Get-CategoryColor 'Repair')      | Should -Be 'Red'
        (Get-CategoryColor 'Laptop')      | Should -Be 'Green'
        (Get-CategoryColor 'Browser')     | Should -Be 'White'
        (Get-CategoryColor 'User')        | Should -Be 'Blue'
        (Get-CategoryColor 'Security')    | Should -Be 'DarkYellow'
        (Get-CategoryColor 'QuickFix')    | Should -Be 'Magenta'
    }
    It 'falls back to Gray for an unknown category' {
        (Get-CategoryColor 'Nope') | Should -Be 'Gray'
    }
    It 'returns valid ConsoleColor names' {
        foreach ($cat in @('Browser','Cloud','Diagnostics','Laptop','QuickFix','Repair','Security','User','Nope')) {
            { [System.ConsoleColor](Get-CategoryColor $cat) } | Should -Not -Throw
        }
    }
}

Describe 'Get-NmmRiskBadge' {
    It 'returns empty for a read-only non-admin tool' {
        Get-NmmRiskBadge @{ Risk = 'ReadOnly'; RequiresAdmin = $false } | Should -Be ''
    }
    It 'returns [M] for a Modifies tool and [!] for a Disruptive tool' {
        Get-NmmRiskBadge @{ Risk = 'Modifies';   RequiresAdmin = $false } | Should -Be '[M]'
        Get-NmmRiskBadge @{ Risk = 'Disruptive'; RequiresAdmin = $false } | Should -Be '[!]'
    }
    It 'appends the admin marker when RequiresAdmin' {
        $tri = [char]0x25B2
        Get-NmmRiskBadge @{ Risk = 'Modifies';   RequiresAdmin = $true } | Should -Be ('[M]' + $tri)
        Get-NmmRiskBadge @{ Risk = 'Disruptive'; RequiresAdmin = $true } | Should -Be ('[!]' + $tri)
    }
    It 'shows only the admin marker for a read-only admin tool' {
        $tri = [char]0x25B2
        Get-NmmRiskBadge @{ Risk = 'ReadOnly'; RequiresAdmin = $true } | Should -Be ([string]$tri)
    }
    It 'returns empty for unknown/missing risk and does not throw' {
        { Get-NmmRiskBadge @{ RequiresAdmin = $false } } | Should -Not -Throw
        Get-NmmRiskBadge @{ Risk = 'Weird'; RequiresAdmin = $false } | Should -Be ''
    }
}

Describe 'Invoke-ToolWithGate' {
    BeforeEach {
        Mock Invoke-NmmTool { 'Success' }
        Mock Read-Host { '' }
        Mock Add-NmmUsage { }
    }
    It 'runs a read-only tool without prompting' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='RO'; Category='Diagnostics'; Risk='ReadOnly'; RequiresAdmin=$false; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Read-ToolChoice -Times 0 -Scope It
        Assert-MockCalled Invoke-NmmTool  -Times 1 -Scope It
    }
    It 'does not run a disruptive tool when the user answers No' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='Boom'; Category='Repair'; Risk='Disruptive'; RequiresAdmin=$true; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Read-ToolChoice -Times 1 -Scope It
        Assert-MockCalled Invoke-NmmTool  -Times 0 -Scope It
    }
    It 'runs a disruptive tool when the user answers Yes' {
        Mock Read-ToolChoice { 'Yes' }
        $tool = @{ Id='t'; Name='Boom'; Category='Repair'; Risk='Disruptive'; RequiresAdmin=$true; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Invoke-NmmTool -Times 1 -Scope It
    }
    It 'prompts risky tools with a default of No' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='Mod'; Category='Repair'; Risk='Modifies'; RequiresAdmin=$false; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Read-ToolChoice -Times 1 -Scope It -ParameterFilter { $Default -eq 'No' }
    }
    It 'records the menu run in the usage store' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='RO'; Category='Diagnostics'; Risk='ReadOnly'; RequiresAdmin=$false; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Add-NmmUsage -Times 1 -Scope It -ParameterFilter { $Id -eq 't' }
    }
    It 'does not record usage when a risky tool is cancelled' {
        Mock Read-ToolChoice { 'No' }
        $tool = @{ Id='t'; Name='Boom'; Category='Repair'; Risk='Disruptive'; RequiresAdmin=$true; Description='d' }
        Invoke-ToolWithGate -Tool $tool
        Assert-MockCalled Add-NmmUsage -Times 0 -Scope It
    }
}

Describe 'Format-MenuColumns' {
    It 'packs cells column-major' {
        $rows = Format-MenuColumns -Cells @('A','B','C','D','E') -Columns 2 -ColumnWidth 5
        @($rows).Count | Should -Be 3
        $rows[0] | Should -Match 'A'
        $rows[0] | Should -Match 'D'
        $rows[1] | Should -Match 'B'
        $rows[1] | Should -Match 'E'
        $rows[2] | Should -Match 'C'
        $rows[2] | Should -Not -Match 'D'
    }
    It 'puts the left half in column 1 and the right half in column 2' {
        $rows = Format-MenuColumns -Cells @('one','two','three','four') -Columns 2 -ColumnWidth 8
        $rows[0] | Should -Match 'one'
        $rows[0] | Should -Match 'three'
        $rows[1] | Should -Match 'two'
        $rows[1] | Should -Match 'four'
    }
    It 'returns an empty array for no cells' {
        @(Format-MenuColumns -Cells @() -Columns 2 -ColumnWidth 10).Count | Should -Be 0
    }
    It 'uses one cell per row with a single column' {
        @(Format-MenuColumns -Cells @('a','b','c') -Columns 1 -ColumnWidth 10).Count | Should -Be 3
    }
}

Describe 'Show-LandingMenu two-column layout' {
    BeforeEach {
        $script:ToolRuns = New-Object System.Collections.ArrayList
    }

    It 'lists every tool title under a category banner with a count, without descriptions' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '1'  'Diagnostics' 'System Information'      'UNIQUEDESCTOKEN'),
            (New-FakeTool '2'  'Diagnostics' 'Disk Space Analysis'    'another desc'),
            (New-FakeTool '54' 'User'        'Windows Search Rebuild'  'yet another')
        ) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'System Information'
        $text | Should -Match 'Disk Space Analysis'
        $text | Should -Match 'Windows Search Rebuild'
        $text | Should -Match 'Diagnostics \(2 tools\)'
        $text | Should -Match 'User \(1 tools\)'
        $text | Should -Not -Match 'UNIQUEDESCTOKEN'
    }

    It 'renders Q-prefixed QuickFix ids without throwing and returns nothing' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool 'Q1' 'QuickFix' 'Office Quick Fix'),
            (New-FakeTool 'Q9' 'QuickFix' 'Browser Backup Quick Fix')
        ) }
        $script:result = 'sentinel'
        { $script:result = Show-LandingMenu 6>$null } | Should -Not -Throw
        $script:result | Should -BeNullOrEmpty
    }

    It 'shows the run/search/exit hint' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool '1' 'Diagnostics' 'System Information') ) }
        $raw = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'Q3'
        $text | Should -Match 'X = exit'
    }

    It 'shows risk/admin badges and a legend, and no badge for read-only tools' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '73' 'Repair'      'System Repair Suite' 'desc' 'Disruptive' $true),
            (New-FakeTool '1'  'Diagnostics' 'System Information'   'desc' 'ReadOnly'   $false)
        ) }
        $raw  = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $tri  = [char]0x25B2

        $repairRow = ($text -split "`n" | Where-Object { $_ -match 'System Repair Suite' }) -join ''
        $repairRow | Should -Match '\[!\]'
        $repairRow | Should -Match ([regex]::Escape($tri))

        $roRow = ($text -split "`n" | Where-Object { $_ -match 'System Information' }) -join ''
        $roRow | Should -Not -Match '\[M\]'
        $roRow | Should -Not -Match '\[!\]'
        $roRow | Should -Not -Match ([regex]::Escape($tri))

        $text | Should -Match 'Legend:'
        $text | Should -Match '\[!\] disruptive'
    }
}

Describe 'Invoke-MenuSelection routing' {
    BeforeEach {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '1'  'Diagnostics' 'System Information'),
            (New-FakeTool '2'  'Diagnostics' 'Disk Space Analysis'),
            (New-FakeTool '54' 'User'        'Windows Search Rebuild')
        ) }
        Mock Invoke-ToolWithGate { }
        Mock Read-Host { '' }
    }
    It 'routes a direct number through the gate' {
        Invoke-MenuSelection -Selection '1'
        Assert-MockCalled Invoke-ToolWithGate -Times 1 -Scope It
    }
    It 'runs the single search hit through the gate without a pick prompt' {
        Invoke-MenuSelection -Selection 'Disk Space'
        Assert-MockCalled Invoke-ToolWithGate -Times 1 -Scope It
        Assert-MockCalled Read-Host -Times 0 -Scope It
    }
    It 'lists multiple matches and routes the chosen pick through the gate' {
        Mock Read-Host { '1' }
        Invoke-MenuSelection -Selection 'fake'
        Assert-MockCalled Invoke-ToolWithGate -Times 1 -Scope It
    }
    It 'shows a match list when several tools match' {
        $out = Invoke-MenuSelection -Selection 'fake' 6>&1
        ($out | ForEach-Object { "$_" }) -join "`n" | Should -Match 'Matches for'
    }
    It 'prints a not-found message for no matches' {
        $out = Invoke-MenuSelection -Selection 'zzzzz' 6>&1
        ($out | ForEach-Object { "$_" }) -join "`n" | Should -Match 'Nothing matches'
    }
    It 'warns and does not run when the multi-match pick is not a valid tool number' {
        Mock Read-Host { '999' }
        $out = Invoke-MenuSelection -Selection 'fake' 6>&1
        ($out | ForEach-Object { "$_" }) -join "`n" | Should -Match 'did not match any tool number'
        Assert-MockCalled Invoke-ToolWithGate -Times 0 -Scope It
    }
    It 'does not run anything when the user cancels the multi-match pick with empty input' {
        Invoke-MenuSelection -Selection 'fake'   # BeforeEach Read-Host returns '' (cancel)
        Assert-MockCalled Invoke-ToolWithGate -Times 0 -Scope It
    }
}

Describe 'Common Fixes section' {
    BeforeEach { $script:ToolRuns = New-Object System.Collections.ArrayList }

    It 'renders a Common Fixes section above the categories when usage exists' {
        $script:RegistryData = @{ Tools = @(
            (New-FakeTool '73' 'Repair' 'System Repair Suite' 'desc' 'Disruptive' $true)
        ) }
        Mock Get-NmmCommonFixes { @( (New-FakeTool '73' 'Repair' 'System Repair Suite' 'desc' 'Disruptive' $true) ) }
        $raw  = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Match 'Common Fixes'
        $text | Should -Match 'System Repair Suite'
        ($text.IndexOf('Common Fixes')) | Should -BeLessThan ($text.IndexOf('Repair (1 tools)'))
    }

    It 'omits the Common Fixes section when there is no usage' {
        $script:RegistryData = @{ Tools = @( (New-FakeTool '1' 'Diagnostics' 'System Information') ) }
        Mock Get-NmmCommonFixes { @() }
        $raw  = Show-LandingMenu 6>&1
        $text = ($raw | ForEach-Object { "$_" }) -join "`n"
        $text | Should -Not -Match 'Common Fixes'
    }
}

Describe 'Format-NmmToolCell' {
    It 'right-aligns the risk/admin badge within the cell width' {
        $tri  = [char]0x25B2
        $cell = Format-NmmToolCell -Tool (New-FakeTool '73' 'Repair' 'SFC' 'd' 'Disruptive' $true) -CellMax 30
        $cell.Length | Should -BeLessOrEqual 30
        $cell | Should -Match '\[!\]'
        $cell | Should -Match ([regex]::Escape($tri))
    }
    It 'has no badge characters for a read-only tool' {
        $cell = Format-NmmToolCell -Tool (New-FakeTool '1' 'Diagnostics' 'System Info') -CellMax 30
        $cell | Should -Not -Match '\[M\]'
        $cell | Should -Not -Match '\[!\]'
    }
    It 'truncates a long name with an ellipsis and stays within the width' {
        $cell = Format-NmmToolCell -Tool (New-FakeTool '1' 'Diagnostics' ('X' * 100)) -CellMax 20
        $cell.Length | Should -BeLessOrEqual 20
        $cell | Should -Match '\.\.\.'
    }
}
