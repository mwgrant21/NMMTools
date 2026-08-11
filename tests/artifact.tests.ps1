BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    & (Join-Path $repoRoot 'build.ps1') -SkipAnalyzer | Out-Null
    $script:Artifact = Join-Path $repoRoot 'dist\NMMTools.ps1'
}

Describe 'Built artifact' {
    It 'exists' {
        Test-Path $script:Artifact | Should -BeTrue
    }

    It 'parses with zero errors under the PS 5.1 parser' {
        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $script:Artifact, [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }

    It 'bakes build provenance into the artifact as runtime variables' {
        $content = Get-Content $script:Artifact -Raw
        $content | Should -Match "ToolkitVersion\s*=\s*'\d+\.\d+\.\d+'"
        $content | Should -Match "ToolkitCommit\s*=\s*'([0-9a-f]{7,}(-dirty)?|unknown)'"
        $content | Should -Match "ToolkitBuildDate\s*=\s*'\d{4}-\d{2}-\d{2} \d{2}:\d{2}'"
    }

    It 'keeps the param block ahead of the provenance block' {
        # The param block must remain the first statement in the artifact or the
        # whole file fails to run. Injecting the provenance block above it would
        # parse fine and break every invocation.
        $content = Get-Content $script:Artifact -Raw
        $paramIndex      = $content.IndexOf('param(')
        $provenanceIndex = $content.IndexOf('ToolkitVersion')
        $paramIndex      | Should -BeGreaterThan -1
        $provenanceIndex | Should -BeGreaterThan $paramIndex
    }

    It 'renders the header comment and the runtime block from one capture' {
        $content = Get-Content $script:Artifact -Raw
        $header  = [regex]::Match($content, '# NMM System Toolkit v(\S+) \((\S+)\) \| built (\d{4}-\d{2}-\d{2} \d{2}:\d{2})')
        $header.Success | Should -BeTrue
        $content | Should -Match ("ToolkitCommit\s*=\s*'{0}'"    -f [regex]::Escape($header.Groups[2].Value))
        $content | Should -Match ("ToolkitBuildDate\s*=\s*'{0}'" -f [regex]::Escape($header.Groups[3].Value))
    }

    It 'writes the artifact as UTF-8 without a BOM' {
        # NOTE: this assertion only has teeth when the suite runs under Windows
        # PowerShell 5.1. Under PS 7 a regression to Set-Content -Encoding UTF8
        # still produces a BOM-less file, so this passes on broken code. The
        # structural test below is what actually holds the line; this one is
        # direct evidence on the real bytes when run on the 5.1 target.
        $bytes = [System.IO.File]::ReadAllBytes($script:Artifact)
        $bytes.Length | Should -BeGreaterThan 3
        $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasBom | Should -BeFalse -Because 'the shipped artifact must be UTF-8 without BOM on every shell'
    }

    It 'writes the artifact with an explicit BOM-less encoding, not Set-Content' {
        # Set-Content -Encoding UTF8 means "with BOM" on PS 5.1 and "without BOM"
        # on PS 7, so using it makes the shipped bytes depend on which shell ran
        # the build - two artifacts from one commit. This is shell-independent
        # and is the real regression guard for the test above.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $build    = Get-Content (Join-Path $repoRoot 'build.ps1') -Raw
        $build | Should -Match 'WriteAllText\('
        $build | Should -Match 'UTF8Encoding\(\$false\)'
        $build | Should -Not -Match 'Set-Content\s+-Path\s+\$artifact'
    }

    It 'contains the core functions and pilot tools' {
        $content = Get-Content $script:Artifact -Raw
        foreach ($fn in 'Write-ToolOutput','Read-ToolChoice','New-ToolRun','Complete-ToolRun',
                        'Resolve-NmmTool','Invoke-NmmTool','Get-SystemUptime','Start-TempFilesCleanup',
                        'Start-ConsoleMenu') {
            $content | Should -Match ("function {0}" -f [regex]::Escape($fn))
        }
    }

    It 'lists tools when run with -ListTools' {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact -ListTools
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'system-uptime'
        ($out -join "`n") | Should -Match 'temp-cleanup'
    }

    It 'prints provenance and exits 0 with -Version' {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact -Version
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'NMM System Toolkit v\d+\.\d+\.\d+'
        ($out -join "`n") | Should -Match 'Commit: '
        ($out -join "`n") | Should -Match 'Built: '
    }

    It 'runs a read-only tool silently with exit code 0' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact `
            -Tool system-uptime -Silent | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 for an unknown tool' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artifact `
            -Tool does-not-exist -Silent | Out-Null
        $LASTEXITCODE | Should -Be 1
    }

    It 'builds clean with the analyzer gate enabled' {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        { & (Join-Path $repoRoot 'build.ps1') *> $null } | Should -Not -Throw
    }
}
