BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
}

Describe 'Write-ToolOutput' {
    AfterEach {
        Set-OutputSink -Sink Console
        if ($script:tmpDir -and (Test-Path $script:tmpDir)) {
            Remove-Item $script:tmpDir -Recurse -Force
        }
        $script:tmpDir = $null
    }

    It 'appends to the log file when a log path is set' {
        $script:tmpDir = Join-Path $env:TEMP "nmm-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $script:tmpDir | Out-Null
        Set-OutputSink -Sink Console -LogDirectory $script:tmpDir
        Write-ToolOutput 'hello from test' -Level Info
        $logFile = Get-ChildItem $script:tmpDir -Filter *.log | Select-Object -First 1
        $logFile | Should -Not -BeNullOrEmpty
        Get-Content $logFile.FullName -Raw | Should -Match 'hello from test'
    }

    It 'does not throw when the log file cannot be written' {
        $script:LogFilePath = 'Q:\does\not\exist\nmm.log'
        { Write-ToolOutput 'should not explode' } | Should -Not -Throw
        $script:LogFilePath = $null
    }
}

Describe 'Read-ToolChoice' {
    It 'returns the default without prompting in silent mode' {
        Read-ToolChoice -Prompt 'Continue?' -Default 'No' -Silent | Should -Be 'No'
    }

    It 'returns the default when the user just presses Enter' {
        Mock Read-Host { '' }
        Read-ToolChoice -Prompt 'Continue?' -Default 'Yes' | Should -Be 'Yes'
    }

    It 'matches a partial answer to a choice' {
        Mock Read-Host { 'y' }
        Read-ToolChoice -Prompt 'Continue?' -Choices @('Yes','No') -Default 'No' | Should -Be 'Yes'
    }

    It 'does not crash on wildcard metacharacters; re-prompts then accepts default' {
        $script:promptCalls = 0
        Mock Read-Host { $script:promptCalls++; if ($script:promptCalls -eq 1) { '[y' } else { '' } }
        Read-ToolChoice -Prompt 'Continue?' -Default 'No' | Should -Be 'No'
    }

    It 're-prompts on ambiguous prefix instead of guessing' {
        $script:promptCalls = 0
        Mock Read-Host { $script:promptCalls++; if ($script:promptCalls -eq 1) { 'N' } else { 'No' } }
        Read-ToolChoice -Prompt 'Pick' -Choices @('Network','No') -Default 'Network' | Should -Be 'No'
    }

    It 'falls back to the default when Read-Host throws (non-interactive host)' {
        Mock Read-Host { throw 'noninteractive' }
        Read-ToolChoice -Prompt 'Continue?' -Default 'No' | Should -Be 'No'
    }

    It 'throws when Default is not one of the Choices' {
        { Read-ToolChoice -Prompt 'x' -Choices @('Yes','No') -Default 'Abort' -Silent } | Should -Throw
    }
}
