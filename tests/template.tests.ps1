BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:Registry = Import-PowerShellDataFile (Join-Path $repoRoot 'src\registry\tools.psd1')
    $script:Tools = @($script:Registry.Tools)
    $script:ToolAsts = @{}
    foreach ($f in (Get-ChildItem (Join-Path $repoRoot 'src\tools') -Recurse -Filter *.ps1)) {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) { throw "Parse errors in $($f.Name)" }
        foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            $script:ToolAsts[$fn.Name] = $fn
        }
    }
}

Describe 'Tool template compliance' {
    It 'analyzes at least the two pilot tools' {
        $script:ToolAsts.Count | Should -BeGreaterThan 1
    }

    It 'every tool function uses an approved PowerShell verb' {
        $approved = (Get-Verb).Verb
        foreach ($name in $script:ToolAsts.Keys) {
            ($name -split '-')[0] | Should -BeIn $approved -Because "$name must use an approved verb"
        }
    }

    It 'every tool function declares a Silent switch (required by the dispatcher)' {
        foreach ($name in $script:ToolAsts.Keys) {
            $params = $script:ToolAsts[$name].Body.ParamBlock.Parameters.Name.VariablePath.UserPath
            $params | Should -Contain 'Silent' -Because "$name is invoked with -Silent:`$Silent"
        }
    }

    It 'every tool function calls New-ToolRun and Complete-ToolRun' {
        foreach ($name in $script:ToolAsts.Keys) {
            $calls = $script:ToolAsts[$name].FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() }
            $calls | Should -Contain 'New-ToolRun' -Because "$name must bracket its run"
            $calls | Should -Contain 'Complete-ToolRun' -Because "$name must record an outcome"
        }
    }

    It 'every New-ToolRun -Id literal matches the registry entry for that function' {
        foreach ($name in $script:ToolAsts.Keys) {
            $entry = $script:Tools | Where-Object { $_.Function -eq $name } | Select-Object -First 1
            $entry | Should -Not -BeNullOrEmpty -Because "$name needs a registry entry"
            $idCalls = $script:ToolAsts[$name].FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                $args[0].GetCommandName() -eq 'New-ToolRun' }, $true)
            foreach ($call in $idCalls) {
                $idArg = $null
                for ($i = 0; $i -lt $call.CommandElements.Count; $i++) {
                    $el = $call.CommandElements[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -eq 'Id') {
                        $idArg = $call.CommandElements[$i + 1]
                    }
                }
                $idArg | Should -Not -BeNullOrEmpty -Because "$name must pass -Id to New-ToolRun"
                $idArg.Value | Should -Be $entry.Id -Because "$name's New-ToolRun -Id must match its registry Id (a mismatch silently breaks PDQ exit codes)"
            }
        }
    }
}
