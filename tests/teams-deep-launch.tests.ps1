# Repair-TeamsDeep reported Failed after a fully successful repair, because the
# cosmetic "relaunch Teams" step at the end threw and escaped to the tool's outer
# catch (MATTHEWGR_L3, 2026-08-25).
#
# Two independent defects in one line:
#   Start-Process 'ms-teams:' -ErrorAction SilentlyContinue
#   1. -ErrorAction only suppresses NON-terminating errors. Start-Process raises
#      a TERMINATING error when it cannot resolve the target as an application,
#      so the flag does nothing and only try/catch contains it. The throw skips
#      every Complete-ToolRun -Status Success/Warning branch below it and lands
#      in the outer catch as Failed.
#   2. It ignores $ctx. The tool uses Get-TargetUserContext to make sure it
#      repairs the LOGGED-ON user's Teams, then launches Teams as whatever
#      account the process runs as - the exact mix-up the context object exists
#      to prevent when a technician elevates with their own credentials.

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:ToolFile = Join-Path $script:RepoRoot 'src\tools\user\Repair-TeamsDeep.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ToolFile, [ref]$null, [ref]$null)

    function Get-LaunchCall {
        @($script:Ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.CommandElements[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $n.CommandElements[0].Value -eq 'Start-Process' }, $true))
    }
}

Describe 'Start-Process failure containment (characterization)' {
    # Not red-green: this pins PowerShell behaviour so nobody "simplifies" the
    # fix back to -ErrorAction. If this ever fails, the premise changed.
    It 'is NOT contained by -ErrorAction SilentlyContinue' {
        { Start-Process -FilePath 'C:\definitely\nonexistent-xyz.exe' -ErrorAction SilentlyContinue } |
            Should -Throw
    }
    It 'IS contained by try/catch' {
        $caught = $false
        try { Start-Process -FilePath 'C:\definitely\nonexistent-xyz.exe' -ErrorAction SilentlyContinue }
        catch { $caught = $true }
        $caught | Should -BeTrue
    }
}

Describe 'Repair-TeamsDeep relaunch cannot fail the repair' {

    It 'wraps the launch in its own try, not just the tool outer try' {
        $calls = Get-LaunchCall
        $calls.Count | Should -BeGreaterThan 0
        $tries = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] }, $true))
        foreach ($c in $calls) {
            $enclosing = @($tries | Where-Object {
                $c.Extent.StartOffset -ge $_.Body.Extent.StartOffset -and
                $c.Extent.EndOffset   -le $_.Body.Extent.EndOffset
            })
            # >1 means there is a local try inside the tool's outermost one.
            $enclosing.Count | Should -BeGreaterThan 1 -Because 'a throw contained only by the outer catch reports the whole repair as Failed'
        }
    }

    It 'gates the launch on the target-user context' {
        $calls = Get-LaunchCall
        foreach ($c in $calls) {
            # Walk up to the nearest enclosing if-statement and require it to
            # test IsCurrentUser - never '-not IsRedirected', which is also false
            # in the failure paths where nothing is known.
            $ifs = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true) |
                Where-Object {
                    $c.Extent.StartOffset -ge $_.Extent.StartOffset -and
                    $c.Extent.EndOffset   -le $_.Extent.EndOffset
                })
            $gated = @($ifs | Where-Object { $_.Clauses[0].Item1.Extent.Text -match 'IsCurrentUser' })
            $gated.Count | Should -BeGreaterThan 0 -Because 'launching Teams as the wrong account is what $ctx exists to prevent'
        }
    }
}
