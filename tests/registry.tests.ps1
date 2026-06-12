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

    It 'every string field is non-empty' {
        $stringFields = 'Id','LegacyId','Name','Category','Function','Description'
        foreach ($t in $script:Tools) {
            foreach ($k in $stringFields) {
                [string]::IsNullOrWhiteSpace($t[$k]) | Should -BeFalse `
                    -Because "entry '$($t.Id)' field $k must not be blank"
            }
        }
    }

    It 'uses numeric strings for LegacyId' {
        foreach ($t in $script:Tools) {
            $t.LegacyId | Should -Match '^\d+$' -Because "entry '$($t.Id)' LegacyId must be a plain number string"
        }
    }

    It 'declares Tags as an array' {
        foreach ($t in $script:Tools) {
            $t.Tags -is [array] | Should -BeTrue -Because "entry '$($t.Id)' Tags must be an array"
        }
    }
}

Describe 'Registry-to-function mapping' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $toolFiles = Get-ChildItem (Join-Path $repoRoot 'src\tools') -Recurse -Filter *.ps1
        $script:DefinedFunctions = foreach ($f in $toolFiles) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                ForEach-Object { $_.Name }
        }
    }

    It 'every registry Function exists in a tools file' {
        foreach ($t in $script:Tools) {
            $script:DefinedFunctions | Should -Contain $t.Function `
                -Because "registry entry '$($t.Id)' points at $($t.Function)"
        }
    }

    It 'every tool-file function has a registry entry' {
        foreach ($fn in $script:DefinedFunctions) {
            @($script:Tools | Where-Object { $_.Function -eq $fn }).Count |
                Should -Be 1 -Because "$fn must be registered exactly once"
        }
    }
}
