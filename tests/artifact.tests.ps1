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
