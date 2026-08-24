Describe 'GUI STA entry point' {

    BeforeAll {
        $script:RepoRoot = Split-Path $PSScriptRoot -Parent
        $script:UiSource = Join-Path $script:RepoRoot 'src\core\09-ui-wpf.ps1'
    }

    It 'does not hand the UI to a raw [Threading.Thread] with a scriptblock ThreadStart' {
        # THE BUG THIS GUARDS
        #
        # Start-GuiMenu used to do:
        #     [System.Threading.Thread]::new([System.Threading.ThreadStart]{ Start-GuiMenuSTA })
        #
        # A PowerShell scriptblock converted to a .NET delegate needs a Runspace on
        # the thread that invokes it. A freshly constructed Threading.Thread has
        # none, so Start-GuiMenuSTA could not even be resolved: the thread died
        # with no window, no error, and no log line. Reproduced under
        # `powershell.exe -mta`, where the branch is taken and the function never
        # runs at all.
        #
        # There is no way to fix this in place - any code that would set up a
        # runspace on that thread is itself PowerShell that needs a runspace to
        # run. So the pattern must not come back.
        # Assert on a count, not the raw text: a -Match failure against an 80 KB
        # file prints the entire file into the test output and buries the result.
        # Skip comment lines: the fix deliberately quotes the old antipattern in a
        # comment explaining why it can never come back, and that must not trip the
        # guard on itself.
        $hits = @(Select-String -LiteralPath $script:UiSource -Pattern 'ThreadStart\]\s*\{' |
                  Where-Object { $_.Line.TrimStart() -notmatch '^#' })
        $detail = ($hits | ForEach-Object { 'line {0}: {1}' -f $_.LineNumber, $_.Line.Trim() }) -join ' | '
        $hits.Count | Should -Be 0 -Because "a scriptblock ThreadStart on a fresh thread has no runspace and dies silently ($detail)"
    }

    It 'sends an MTA host down a relaunch/fallback path instead of a raw thread' {
        $text = Get-Content -LiteralPath $script:UiSource -Raw
        $fn = [regex]::Match($text, '(?ms)^function Start-GuiMenu\b.*?^\}').Value
        $fn | Should -Not -BeNullOrEmpty -Because 'Start-GuiMenu must exist'
        $fn | Should -Match 'ApartmentState'      -Because 'it still has to detect the apartment state'
        $fn | Should -Match '-STA'                -Because 'the MTA path should relaunch into an STA host'
        $fn | Should -Match 'Start-ConsoleMenu'   -Because 'if the GUI cannot be started it must degrade, not vanish'
    }

    It 'runs the real apartment-state decision correctly in an actual MTA host' {
        # Executes the decision in a genuine MTA powershell.exe. Static checks
        # cannot tell us which branch a real MTA host takes; only running one can.
        # Start-GuiMenuSTA and Start-ConsoleMenu are stubbed so nothing opens a
        # window, and the relaunch is stubbed so no process is spawned - what is
        # under test is purely which branch fires.
        $harness = Join-Path ([System.IO.Path]::GetTempPath()) ('nmm-sta-{0}.ps1' -f ([guid]::NewGuid().ToString('N')))
        $marker  = Join-Path ([System.IO.Path]::GetTempPath()) ('nmm-sta-{0}.txt' -f ([guid]::NewGuid().ToString('N')))

        $text = Get-Content -LiteralPath $script:UiSource -Raw
        $fn   = [regex]::Match($text, '(?ms)^function Start-GuiMenu\b.*?^\}').Value

        $body = @"
`$MarkerPath = '$marker'
function Note { param(`$m) Add-Content -LiteralPath `$MarkerPath -Value `$m }
function Start-GuiMenuSTA { Note 'BRANCH: direct STA' }
function Start-ConsoleMenu { Note 'BRANCH: console fallback' }
function Write-Host { param([Parameter(ValueFromRemainingArguments)]`$a) }
function Start-Process {
    param([Parameter(ValueFromRemainingArguments)]`$a)
    Note 'BRANCH: STA relaunch'
    return [PSCustomObject]@{ ExitCode = 0 }
}
`$LogPath = `$null
$fn
Note ('apartment=' + [System.Threading.Thread]::CurrentThread.GetApartmentState())
Start-GuiMenu
"@
        Set-Content -LiteralPath $harness -Value $body -Encoding ASCII

        try {
            $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -mta -File $harness 2>&1
            $out = @(if (Test-Path -LiteralPath $marker) { Get-Content -LiteralPath $marker } else { @() })

            ($out -join '; ') | Should -Match 'apartment=MTA' -Because 'the harness must actually be MTA for this test to mean anything'
            # The whole point: SOMETHING must happen. The old code produced nothing.
            $branch = @($out | Where-Object { $_ -like 'BRANCH:*' })
            $branch.Count | Should -BeGreaterThan 0 -Because 'the old raw-thread code silently did nothing at all on an MTA host'
            $branch[0] | Should -Not -Be 'BRANCH: direct STA' -Because 'an MTA host must not fall through to the direct STA call'
        } finally {
            Remove-Item -LiteralPath $harness -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $marker  -ErrorAction SilentlyContinue
        }
    }
}
