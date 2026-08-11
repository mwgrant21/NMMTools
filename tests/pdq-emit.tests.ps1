BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    & (Join-Path $script:RepoRoot 'build.ps1') -Pdq -SkipAnalyzer | Out-Null
    $script:PdqDir   = Join-Path $script:RepoRoot 'dist\pdq'
    $script:Registry = Import-PowerShellDataFile (Join-Path $script:RepoRoot 'src\registry\tools.psd1')
    $script:Flagged  = @(@($script:Registry.Tools) | Where-Object { $_.PdqDeployable })
}

Describe 'PDQ per-tool emitter' {
    It 'creates the output directory' {
        Test-Path $script:PdqDir | Should -BeTrue
    }

    It 'emits exactly one script per flagged tool and none for unflagged tools' {
        $emitted  = @(Get-ChildItem $script:PdqDir -Filter *.ps1 | ForEach-Object { $_.BaseName })
        $expected = @($script:Flagged | ForEach-Object { $_.Id })
        ($emitted | Sort-Object) -join ',' | Should -Be (($expected | Sort-Object) -join ',')
    }

    It 'emits scripts that parse with zero errors' {
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0 -Because ('{0} must parse' -f $f.Name)
        }
    }

    It 'emits scripts with no analyzer errors' {
        Import-Module PSScriptAnalyzer
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $findings = Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error
            @($findings).Count | Should -Be 0 -Because ('{0} must be analyzer-clean' -f $f.Name)
        }
    }

    It 'emits scripts that reference no function from the dropped cores' {
        # The headless build omits 05-ui-console, 06-usage, 09-ui-wpf and 10-jira.
        # No tool references them today, but nothing stops one gaining such a call
        # later - and the failure would be a CommandNotFoundException on every
        # endpoint rather than anything visible at build time.
        #
        # Matched via the AST, not a text search. The retained cores legitimately
        # NAME dropped-core functions in comments (02-output.ps1 documents the
        # runspace-affinity rule by pointing at Start-GuiMenuSTA), and a text
        # search cannot tell a call from a mention. CommandAst nodes are actual
        # invocations; comments are not CommandAst nodes at all.
        #
        # Known limit: this sees statically-named commands, so an indirect call
        # (& $name, Invoke-Expression) would slip past. The codebase does not do
        # that, and the alternative - text matching - has already produced false
        # positives on documentation.
        $dropped = @('05-ui-console.ps1','06-usage.ps1','09-ui-wpf.ps1','10-jira.ps1')
        $names   = @()
        foreach ($d in $dropped) {
            $text   = Get-Content (Join-Path $script:RepoRoot ('src\core\' + $d)) -Raw
            $names += [regex]::Matches($text, '(?m)^function\s+([\w-]+)') |
                      ForEach-Object { $_.Groups[1].Value }
        }
        $offenders = @()
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$null)
            $commands = $ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)
            foreach ($c in $commands) {
                $name = $c.GetCommandName()
                if ($name -and ($names -contains $name)) {
                    $offenders += ('{0}:{1} calls {2}' -f $f.Name, $c.Extent.StartLineNumber, $name)
                }
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty
    }

    It 'emits UTF-8 scripts with no BOM and no non-ASCII bytes' {
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
                Should -BeFalse -Because ('{0} must have no BOM' -f $f.Name)
            @($bytes | Where-Object { $_ -gt 127 }).Count |
                Should -Be 0 -Because ('{0} must be ASCII-only' -f $f.Name)
        }
    }

    It 'emits scripts that never override the error preference' {
        # The toolkit runs at the default Continue and relies on per-tool
        # try/catch. A generated script that set Stop would make the same tool
        # take a different path under PDQ than in the toolkit.
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            Get-Content $f.FullName -Raw |
                Should -Not -Match 'ErrorActionPreference\s*=' -Because ('{0} must not set the error preference' -f $f.Name)
        }
    }

    It 'emits scripts with no #Requires -RunAsAdministrator' {
        # The dispatcher's admin gate returns Refused, which maps to exit 4 and
        # tells you in the PDQ results grid why the tool did not run. #Requires
        # would hard-fail with a generic error instead.
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            Get-Content $f.FullName -Raw |
                Should -Not -Match '(?m)^#Requires\s+-RunAsAdministrator' -Because ('{0} must gate admin via the dispatcher' -f $f.Name)
        }
    }

    It 'emits scripts that set the Pdq sink before the -Version branch' {
        # -Version exists to be readable on an endpoint. If it ran before
        # Set-OutputSink, the banner would go to the default Console sink and
        # PDQ would capture nothing for the one command whose job is to answer
        # "what is actually deployed here".
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $c       = Get-Content $f.FullName -Raw
            $sink    = $c.IndexOf('Set-OutputSink -Sink Pdq')
            $version = $c.IndexOf('if ($Version)')
            $sink    | Should -BeGreaterThan -1 -Because ('{0} must set the Pdq sink' -f $f.Name)
            $version | Should -BeGreaterThan $sink -Because ('{0} must set the sink before -Version' -f $f.Name)
        }
    }

    It 'carries the same provenance as the main artifact' {
        $artifact = Get-Content (Join-Path $script:RepoRoot 'dist\NMMTools.ps1') -Raw
        $header   = [regex]::Match($artifact, "ToolkitCommit\s*=\s*'([^']+)'")
        $header.Success | Should -BeTrue
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            Get-Content $f.FullName -Raw |
                Should -Match ("ToolkitCommit\s*=\s*'{0}'" -f [regex]::Escape($header.Groups[1].Value))
        }
    }

    It 'emits scripts that never invoke a language keyword as a command' {
        # The spec asks for ps51-runtime.tests.ps1 to cover dist\pdq. It lives
        # here instead: that file scans src\ with no build step, and pointing it
        # at generated output would make it depend on build.ps1 -Pdq having run
        # in another test file. This file already builds with -Pdq in BeforeAll.
        # Same check, same class - `(if ($x) { 'a' } else { 'b' })` parses fine
        # and throws CommandNotFoundException at runtime on PS 5.1.
        $keywords = @('if','else','elseif','switch','foreach','for','while','do',
                      'try','catch','finally','return','throw','param','begin',
                      'process','end','until','trap','data')
        $offenders = @()
        foreach ($f in Get-ChildItem $script:PdqDir -Filter *.ps1) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$null, [ref]$null)
            $commands = $ast.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true)
            foreach ($c in $commands) {
                $name = $c.GetCommandName()
                if ($name -and $keywords -contains $name) {
                    $offenders += ('{0}:{1} {2}' -f $f.Name, $c.Extent.StartLineNumber, $name)
                }
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty
    }

    It 'removes scripts for tools that lost the flag' {
        $stale = Join-Path $script:PdqDir 'zzz-stale-tool.ps1'
        Set-Content -Path $stale -Value '# stale'
        & (Join-Path $script:RepoRoot 'build.ps1') -Pdq -SkipAnalyzer | Out-Null
        Test-Path $stale | Should -BeFalse
    }
}
