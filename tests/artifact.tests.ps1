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
}
