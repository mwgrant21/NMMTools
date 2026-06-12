BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
}

Describe 'Write-ToolOutput' {
    It 'appends to the log file when a log path is set' {
        $dir = Join-Path $env:TEMP "nmm-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $dir | Out-Null
        Set-OutputSink -Sink Console -LogDirectory $dir
        Write-ToolOutput 'hello from test' -Level Info
        $logFile = Get-ChildItem $dir -Filter *.log | Select-Object -First 1
        $logFile | Should -Not -BeNullOrEmpty
        Get-Content $logFile.FullName -Raw | Should -Match 'hello from test'
        Remove-Item $dir -Recurse -Force
        Set-OutputSink -Sink Console   # reset: no log directory
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
}
