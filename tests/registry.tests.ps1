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
                    'RequiresAdmin','SilentCapable','PdqDeployable','Risk','Tags'
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
            $t.LegacyId | Should -Match '^Q?\d+$' -Because "entry '$($t.Id)' LegacyId must be a plain number string (optionally Q-prefixed for QuickFix tools)"
        }
    }

    It 'declares Tags as an array' {
        foreach ($t in $script:Tools) {
            $t.Tags -is [array] | Should -BeTrue -Because "entry '$($t.Id)' Tags must be an array"
        }
    }

    It 'declares PdqDeployable as a boolean on every tool' {
        $offenders = @()
        foreach ($tool in @($script:Registry.Tools)) {
            if (-not $tool.ContainsKey('PdqDeployable')) {
                $offenders += ('{0} (missing)' -f $tool.Id)
            } elseif ($tool.PdqDeployable -isnot [bool]) {
                $offenders += ('{0} (not a bool)' -f $tool.Id)
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty -Because 'every tool must make an explicit decision about PDQ deployment'
    }

    It 'has at least one PdqDeployable tool and system-info is one of them' {
        # Intentionally does not assert an exact count - see the headless
        # invariant test below for why pinning the number would be wrong.
        $flagged = @(@($script:Registry.Tools) | Where-Object { $_.PdqDeployable })
        $flagged.Count | Should -BeGreaterThan 0
        $flagged.Id | Should -Contain 'system-info'
    }

    It 'never flags a tool for PDQ that cannot run headless' {
        # The durable invariant. Deliberately NOT asserting an exact count of
        # flagged tools: the field exists so more tools get opted in later as a
        # data change, and pinning the count would turn that intended change
        # into a test failure. What must never vary is that anything shipped as
        # a standalone PDQ script can run non-interactively - PDQ runs it as
        # SYSTEM with no host to prompt.
        $offenders = @()
        foreach ($tool in @($script:Registry.Tools)) {
            if ($tool.PdqDeployable -and -not $tool.SilentCapable) {
                $offenders += $tool.Id
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty -Because 'a PdqDeployable tool must be SilentCapable'
    }
}

Describe 'Registry-to-function mapping' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $toolFiles = Get-ChildItem (Join-Path $repoRoot 'src\tools') -Recurse -Filter *.ps1
        $script:DefinedFunctions = foreach ($f in $toolFiles) {
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$parseErrors)
            if ($parseErrors -and $parseErrors.Count -gt 0) {
                throw ("Tool file {0} has {1} parse error(s): {2}" -f $f.Name, $parseErrors.Count, $parseErrors[0].Message)
            }
            $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) |
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
