BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\04-dispatch.ps1')
    . (Join-Path $repoRoot 'src\core\06-usage.ps1')
    $script:RegistryData = @{ Tools = @(
        @{ Id='tool-a'; LegacyId='1'; Name='Tool A'; Category='Diagnostics'; Function='Invoke-A'; Description='a'; RequiresAdmin=$false; SilentCapable=$true; Risk='ReadOnly'; Tags=@('a') },
        @{ Id='tool-b'; LegacyId='2'; Name='Tool B'; Category='Diagnostics'; Function='Invoke-B'; Description='b'; RequiresAdmin=$false; SilentCapable=$true; Risk='ReadOnly'; Tags=@('b') },
        @{ Id='tool-c'; LegacyId='3'; Name='Tool C'; Category='Diagnostics'; Function='Invoke-C'; Description='c'; RequiresAdmin=$false; SilentCapable=$true; Risk='ReadOnly'; Tags=@('c') }
    ) }
}

Describe 'Usage store' {
    BeforeEach {
        $script:UsageFilePathOverride = Join-Path $env:TEMP ('nmm-usage-test-{0}.json' -f (Get-Random))
    }
    AfterEach {
        if ($script:UsageFilePathOverride -and (Test-Path $script:UsageFilePathOverride)) {
            Remove-Item $script:UsageFilePathOverride -Force -ErrorAction SilentlyContinue
        }
        $script:UsageFilePathOverride = $null
    }

    It 'records and reads back a count and timestamp' {
        Add-NmmUsage -Id 'tool-a'
        Add-NmmUsage -Id 'tool-a'
        $u = Import-NmmUsage
        $u['tool-a']['Count'] | Should -Be 2
        [string]::IsNullOrWhiteSpace($u['tool-a']['Last']) | Should -BeFalse
    }
    It 'returns an empty hashtable for a missing file' {
        (Import-NmmUsage).Count | Should -Be 0
    }
    It 'returns empty and does not throw on a corrupt file' {
        Set-Content -Path $script:UsageFilePathOverride -Value '{ not json' -Encoding UTF8
        { Import-NmmUsage } | Should -Not -Throw
        (Import-NmmUsage).Count | Should -Be 0
    }
    It 'ranks by count descending' {
        1..5 | ForEach-Object { Add-NmmUsage -Id 'tool-a' }
        1..2 | ForEach-Object { Add-NmmUsage -Id 'tool-b' }
        1..9 | ForEach-Object { Add-NmmUsage -Id 'tool-c' }
        $top = Get-NmmCommonFixes -Max 2
        @($top).Count | Should -Be 2
        $top[0].Id | Should -Be 'tool-c'
        $top[1].Id | Should -Be 'tool-a'
    }
    It 'breaks ties by most recent use' {
        Add-NmmUsage -Id 'tool-a'
        Start-Sleep -Milliseconds 20
        Add-NmmUsage -Id 'tool-b'
        (Get-NmmCommonFixes -Max 2)[0].Id | Should -Be 'tool-b'
    }
    It 'preserves sub-second precision in Last across a save/load round trip' {
        # ConvertFrom-Json coerces an ISO-8601 string back into [DateTime], and
        # [string] on a DateTime renders the culture short format
        # (MM/dd/yyyy HH:mm:ss) - dropping the fractional seconds that the
        # most-recent-use tie-break depends on.
        Add-NmmUsage -Id 'tool-a'
        $last = (Import-NmmUsage)['tool-a']['Last']
        $last | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+'
    }
    It 'ranks a later year above an earlier one regardless of month digits' {
        # Guards the culture-format string sort: as plain text '12/01/2025'
        # sorts above '08/11/2026', so the more recent tool would rank last.
        $store = [PSCustomObject]@{ Version = 1; Tools = [PSCustomObject]@{
            'tool-a' = @{ Count = 1; Last = '2025-12-01T10:00:00.0000000-06:00' }
            'tool-b' = @{ Count = 1; Last = '2026-08-11T10:00:00.0000000-06:00' }
        } }
        Set-Content -Path $script:UsageFilePathOverride -Value ($store | ConvertTo-Json -Depth 4) -Encoding UTF8
        (Get-NmmCommonFixes -Max 2)[0].Id | Should -Be 'tool-b'
    }
    It 'skips ids no longer in the registry' {
        Add-NmmUsage -Id 'ghost-tool'
        Add-NmmUsage -Id 'tool-a'
        @(Get-NmmCommonFixes -Max 6).Id | Should -Not -Contain 'ghost-tool'
        @(Get-NmmCommonFixes -Max 6).Id | Should -Contain 'tool-a'
    }
    It 'returns an empty array when there is no usage' {
        @(Get-NmmCommonFixes -Max 6).Count | Should -Be 0
    }
    It 'respects -Max' {
        foreach ($id in 'tool-a','tool-b','tool-c') { Add-NmmUsage -Id $id }
        @(Get-NmmCommonFixes -Max 2).Count | Should -Be 2
    }
}
