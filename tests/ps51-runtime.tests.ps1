# Guards against PS 5.1 defect classes that reach the user as "the command does
# not work", because neither build gate can see them: the artifact parses
# cleanly and PSScriptAnalyzer reports no error.

Describe 'PS 5.1 keyword-as-command' {
    It 'never invokes a language keyword as a command' {
        # `(if ($x) { 'a' } else { 'b' })` parses fine but throws
        # CommandNotFoundException at runtime: in PS 5.1 `if` is a statement,
        # not an expression. The parser records it as a command named 'if'.
        # The fix is always the subexpression form: $(if ($x) { 'a' } else { 'b' }).
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $keywords = @(
            'if', 'else', 'elseif', 'switch', 'foreach', 'for', 'while', 'do',
            'try', 'catch', 'finally', 'return', 'throw', 'param', 'begin',
            'process', 'end', 'until', 'trap', 'data'
        )

        $offenders = @()
        foreach ($f in (Get-ChildItem (Join-Path $repoRoot 'src') -Recurse -Filter *.ps1)) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$tokens, [ref]$errors)

            $commands = $ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)

            foreach ($c in $commands) {
                $name = $c.GetCommandName()
                if ($name -and ($keywords -contains $name.ToLower())) {
                    $offenders += ('{0}:{1} -> {2}' -f
                        $f.Name, $c.Extent.StartLineNumber, $c.Extent.Text)
                }
            }
        }

        $offenders -join '; ' | Should -BeNullOrEmpty -Because 'a bare (if ...) throws CommandNotFoundException at runtime in PS 5.1; use the $(if ...) subexpression form'
    }
}
