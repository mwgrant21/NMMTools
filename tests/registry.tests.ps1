BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:Registry = Import-PowerShellDataFile (Join-Path $repoRoot 'src\registry\tools.psd1')
    $script:Tools = @($script:Registry.Tools)
}

Describe 'Tool registry structure' {
    It 'has at least one tool' {
        $script:Tools.Count | Should -BeGreaterThan 0
    }

    It 'every entry has all required keys' {
        $required = 'Id','LegacyId','Name','Category','Function','Description',
                    'RequiresAdmin','SilentCapable','Risk','Tags'
        foreach ($t in $script:Tools) {
            foreach ($k in $required) {
                $t.ContainsKey($k) | Should -BeTrue -Because "entry '$($t.Id)' must define $k"
            }
        }
    }

    It 'has unique Ids' {
        $dupes = $script:Tools | Group-Object { $_.Id } | Where-Object Count -gt 1
        $dupes | Should -BeNullOrEmpty
    }

    It 'has unique LegacyIds' {
        $dupes = $script:Tools | Group-Object { $_.LegacyId } | Where-Object Count -gt 1
        $dupes | Should -BeNullOrEmpty
    }

    It 'uses only valid Risk values' {
        foreach ($t in $script:Tools) {
            $t.Risk | Should -BeIn @('ReadOnly','Modifies','Disruptive')
        }
    }

    It 'uses kebab-case slugs for Id' {
        foreach ($t in $script:Tools) {
            $t.Id | Should -Match '^[a-z0-9]+(-[a-z0-9]+)*$'
        }
    }
}