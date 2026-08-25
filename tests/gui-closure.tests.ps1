# Guards the class of bug that made the GUI unusable from an already-elevated
# PowerShell window (NMMTools 9.0.1 - 9.3.2).
#
# .GetNewClosure() wraps a scriptblock in a dynamic module. Command lookup from
# inside a module session state chains to the SESSION scope, never to the script
# scope that defined the scriptblock. Under -File the script scope IS the
# top-level scope, so by-name calls resolve and the bug is invisible. Launched
# from an already-open window - which is what happens when the technician is
# already admin, because Invoke-ElevationCheck then does NOT relaunch with
# -File - the script scope is a child of global, the module walks straight past
# it, and every handler throws CommandNotFoundException.
#
# Two gates, deliberately: the runtime one proves the captured-variable shape
# survives the failing launch mode; the static one proves 09-ui-wpf.ps1 actually
# uses that shape. Neither alone is sufficient.

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:UiFile   = Join-Path $script:RepoRoot 'src\core\09-ui-wpf.ps1'

    function Invoke-InNestedScope {
        # Runs a script the way an already-elevated technician does: typed at a
        # prompt, so the script scope is a CHILD of global rather than the
        # top-level scope that -File produces.
        param([Parameter(Mandatory)][string]$ScriptPath)
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $in = "& '{0}'`r`nexit`r`n" -f $ScriptPath
        $tmpIn = [System.IO.Path]::GetTempFileName()
        [System.IO.File]::WriteAllText($tmpIn, $in, (New-Object System.Text.UTF8Encoding($false)))
        try {
            return (Get-Content -LiteralPath $tmpIn -Raw | & $ps -NoProfile -ExecutionPolicy Bypass -Command - 2>&1) -join "`n"
        } finally {
            Remove-Item -LiteralPath $tmpIn -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'GUI handlers survive launch from an already-open PowerShell window' {

    It 'resolves a helper from a GetNewClosure DispatcherTimer tick in a nested scope' {
        $harness = Join-Path ([System.IO.Path]::GetTempPath()) ('nmm-closure-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $body = @'
Add-Type -AssemblyName PresentationFramework, WindowsBase -ErrorAction Stop
function Add-GuiOutputRecordStub { param($Sync, $Record) return ('rendered:' + $Record) }

$sync = [hashtable]::Synchronized(@{})
# THE SHAPE UNDER TEST: capture the function object, do not rely on name lookup.
$fnAdd = ${function:Add-GuiOutputRecordStub}
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [System.TimeSpan]::FromMilliseconds(25)
$timer.Add_Tick({
    $s = $sync
    try   { $s['r'] = & $fnAdd -Sync $s -Record 'x' }
    catch { $s['r'] = 'FAIL: ' + $_.Exception.GetType().Name }
    $timer.Stop()
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
}.GetNewClosure())
$timer.Start()
[System.Windows.Threading.Dispatcher]::Run()
[Console]::Out.WriteLine('RESULT=' + $sync['r'])
'@
        [System.IO.File]::WriteAllText($harness, $body, (New-Object System.Text.UTF8Encoding($false)))
        try {
            $out = Invoke-InNestedScope -ScriptPath $harness
            $out | Should -Match 'RESULT=rendered:x'
        } finally {
            Remove-Item -LiteralPath $harness -Force -ErrorAction SilentlyContinue
        }
    }

    It 'a captured function still sees the script scope Function: drive when called from a closure' {
        # New-NmmToolRunspace seeds the tool Runspace from Get-ChildItem Function:. The
        # Jira fix calls it through a captured reference from inside a closure, so this
        # asserts the captured scriptblock still executes in its DEFINING session state -
        # if it ran in the closure's module scope it would clone an empty function table
        # and every tool in that Runspace would vanish.
        $harness = Join-Path ([System.IO.Path]::GetTempPath()) ('nmm-fnscope-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $body = @'
function Get-NmmMarkerHelper { 'marker' }
function Get-NmmVisibleCount { @(Get-ChildItem Function: | Where-Object { $_.Name -eq 'Get-NmmMarkerHelper' }).Count }
$fnCount = ${function:Get-NmmVisibleCount}
$probe = [hashtable]::Synchronized(@{})
$sb = { $probe['seen'] = & $fnCount }.GetNewClosure()
& $sb
[Console]::Out.WriteLine('SEEN=' + $probe['seen'])
'@
        [System.IO.File]::WriteAllText($harness, $body, (New-Object System.Text.UTF8Encoding($false)))
        try {
            $out = Invoke-InNestedScope -ScriptPath $harness
            $out | Should -Match 'SEEN=1'
        } finally {
            Remove-Item -LiteralPath $harness -Force -ErrorAction SilentlyContinue
        }
    }

    It 'has no GetNewClosure handler in 09-ui-wpf.ps1 that calls a toolkit function by name' {
        $defined = @{}
        foreach ($sf in (Get-ChildItem (Join-Path $script:RepoRoot 'src') -Recurse -Filter *.ps1)) {
            $a = [System.Management.Automation.Language.Parser]::ParseFile($sf.FullName, [ref]$null, [ref]$null)
            foreach ($d in $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                $defined[$d.Name] = $true
            }
        }
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:UiFile, [ref]$null, [ref]$null)
        $closures = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $n.Member.Value -eq 'GetNewClosure' }, $true))

        # Commands inside an .AddScript({...}) body are NOT resolved by the closure's
        # session state - that scriptblock is handed to a PowerShell instance bound to
        # the tool Runspace, whose InitialSessionState already carries the toolkit's
        # functions. Excluding those extents keeps the gate precise instead of flagging
        # a construct that is correct. (Runtime proof that the Runspace really is seeded
        # correctly is the third test in this file.)
        $addScriptExtents = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $n.Member.Value -eq 'AddScript' }, $true) | ForEach-Object { $_.Extent })

        $offenders = @()
        foreach ($c in $closures) {
            $calls = @($c.Expression.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                Where-Object {
                    $cmd = $_
                    -not (@($addScriptExtents | Where-Object {
                        $cmd.Extent.StartOffset -ge $_.StartOffset -and $cmd.Extent.EndOffset -le $_.EndOffset
                    }).Count)
                } |
                ForEach-Object {
                    $e = $_.CommandElements[0]
                    if ($e -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $e.Value }
                } | Where-Object { $defined.ContainsKey($_) } | Sort-Object -Unique)
            if ($calls.Count -gt 0) {
                $offenders += ('line {0}: {1}' -f $c.Extent.StartLineNumber, ($calls -join ', '))
            }
        }
        $offenders -join ' | ' | Should -BeNullOrEmpty
    }
}
