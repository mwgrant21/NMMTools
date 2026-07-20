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

    # Source of truth for valid Complete-ToolRun statuses: the ValidateSet on its
    # Status parameter in 03-results.ps1 (read via AST so the test tracks the code).
    $parseErrors = $null
    $resultsAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repoRoot 'src\core\03-results.ps1'), [ref]$null, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) { throw 'Parse errors in 03-results.ps1' }
    $completeFn = $resultsAst.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq 'Complete-ToolRun' }, $true) | Select-Object -First 1
    $statusParam = $completeFn.Body.ParamBlock.Parameters |
        Where-Object { $_.Name.VariablePath.UserPath -eq 'Status' }
    $script:ValidStatuses = @(($statusParam.Attributes |
        Where-Object { $_.TypeName.Name -eq 'ValidateSet' }).PositionalArguments.Value)
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

    It 'every Complete-ToolRun -Status literal is in the real ValidateSet' {
        # Guards doc/source drift: a bad literal (e.g. 'Refused', dispatcher-only)
        # parses and builds fine but throws a binding error at runtime that the
        # tool's own catch swallows into a baffling Failed summary.
        $script:ValidStatuses.Count | Should -BeGreaterThan 0 -Because 'the ValidateSet must be readable from 03-results.ps1'
        foreach ($name in $script:ToolAsts.Keys) {
            $calls = $script:ToolAsts[$name].FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                $args[0].GetCommandName() -eq 'Complete-ToolRun' }, $true)
            foreach ($call in $calls) {
                for ($i = 0; $i -lt $call.CommandElements.Count; $i++) {
                    $el = $call.CommandElements[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -eq 'Status') {
                        $statusArg = $call.CommandElements[$i + 1]
                        if ($statusArg -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $statusArg.Value | Should -BeIn $script:ValidStatuses -Because "$name passes -Status '$($statusArg.Value)', which Complete-ToolRun's ValidateSet rejects at runtime"
                        }
                    }
                }
            }
        }
    }
}
