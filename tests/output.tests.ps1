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

Describe 'Read-ToolChoice -ExactMatch' {
    It 'returns the choice on an exact, case-sensitive match' {
        Mock Read-Host { 'RESET' }
        Read-ToolChoice -Prompt 'Confirm' -Choices @('RESET','Cancel') -Default 'Cancel' -ExactMatch | Should -Be 'RESET'
    }

    It 'does not select on a prefix match; re-prompts then falls through to the default on Enter' {
        $script:promptCalls = 0
        Mock Read-Host {
            $script:promptCalls++
            if ($script:promptCalls -eq 1) { 'R' } else { '' }
        }
        Read-ToolChoice -Prompt 'Confirm' -Choices @('RESET','Cancel') -Default 'Cancel' -ExactMatch | Should -Be 'Cancel'
        $script:promptCalls | Should -Be 2
    }

    It 'does not select on a wrong-case match; re-prompts then falls through to the default on Enter' {
        $script:promptCalls = 0
        Mock Read-Host {
            $script:promptCalls++
            if ($script:promptCalls -eq 1) { 'reset' } else { '' }
        }
        Read-ToolChoice -Prompt 'Confirm' -Choices @('RESET','Cancel') -Default 'Cancel' -ExactMatch | Should -Be 'Cancel'
        $script:promptCalls | Should -Be 2
    }

    It 'returns the default in silent mode without prompting, even with -ExactMatch' {
        Read-ToolChoice -Prompt 'Confirm' -Choices @('RESET','Cancel') -Default 'Cancel' -Silent -ExactMatch | Should -Be 'Cancel'
    }
}

Describe 'Read-ToolText' {
    It 'returns the default without prompting in silent mode' {
        Read-ToolText -Prompt 'Drive letter' -Default 'Z' -Silent | Should -Be 'Z'
    }

    It 'returns an empty string in silent mode with no default given' {
        Read-ToolText -Prompt 'Drive letter' -Silent | Should -Be ''
    }

    It 'returns the default when the user just presses Enter' {
        Mock Read-Host { '' }
        Read-ToolText -Prompt 'UNC path' -Default 'FALLBACK' | Should -Be 'FALLBACK'
    }

    It 'returns the trimmed typed value' {
        Mock Read-Host { '  \\server\share  ' }
        Read-ToolText -Prompt 'UNC path' | Should -Be '\\server\share'
    }

    It 'falls back to the default when Read-Host throws (non-interactive host)' {
        Mock Read-Host { throw 'noninteractive' }
        Read-ToolText -Prompt 'Drive letter' -Default 'Z' | Should -Be 'Z'
    }
}

Describe 'Start-ToolOutputCapture / Stop-ToolOutputCapture' {
    AfterEach { Set-OutputSink -Sink Console }

    It 'buffers Write-ToolOutput calls instead of writing to console' {
        Set-OutputSink -Sink Console
        Start-ToolOutputCapture
        Write-ToolOutput 'line one'
        Write-ToolOutput 'line two' -Level Warning
        $text = Stop-ToolOutputCapture
        $text | Should -Match 'line one'
        $text | Should -Match 'line two'
    }

    It 'restores the prior sink after Stop-ToolOutputCapture' {
        Set-OutputSink -Sink Silent
        Start-ToolOutputCapture
        Write-ToolOutput 'captured'
        [void](Stop-ToolOutputCapture)
        $script:OutputSink | Should -Be 'Silent'
    }

    It 'restores the prior log path after Stop-ToolOutputCapture' {
        $tmpDir = Join-Path $env:TEMP "nmm-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $tmpDir | Out-Null
        Set-OutputSink -Sink Console -LogDirectory $tmpDir
        $priorLog = $script:LogFilePath
        Start-ToolOutputCapture
        Write-ToolOutput 'should not hit the log file'
        [void](Stop-ToolOutputCapture)
        $script:LogFilePath | Should -Be $priorLog
        Remove-Item $tmpDir -Recurse -Force
    }

    It 'returns an empty string when nothing was written' {
        Start-ToolOutputCapture
        Stop-ToolOutputCapture | Should -Be ''
    }
}

Describe 'Pdq output sink' {
    AfterEach { Set-OutputSink -Sink Console }

    It 'accepts Pdq as a sink' {
        { Set-OutputSink -Sink Pdq } | Should -Not -Throw
    }

    It 'writes to stdout and nothing to the PowerShell success stream' {
        # Two assertions, because either alone is passable by broken code:
        #   - Should -BeNullOrEmpty alone passes if the Pdq branch is deleted
        #     entirely (Write-ToolOutput falls through and returns $null).
        #   - Asserting only that stdout got the line would not catch a change
        #     from [Console]::Out.WriteLine to Write-Output, which is the
        #     regression that matters: Invoke-NmmTool ends with
        #     'return $run.Status', so log lines on the success stream would
        #     fold into that return value and corrupt the exit-code mapping.
        $sw   = New-Object System.IO.StringWriter
        $prev = [Console]::Out
        try {
            [Console]::SetOut($sw)
            Set-OutputSink -Sink Pdq
            $captured = Write-ToolOutput 'must not reach the pipeline' -Level Info
        } finally {
            [Console]::SetOut($prev)
        }
        $captured | Should -BeNullOrEmpty
        $sw.ToString() | Should -Match '\[Info\s+\] must not reach the pipeline'
    }

    It 'still writes to the log file when a log directory is set' {
        # Integration check only, not a discriminator: the log write happens in
        # an unconditional block ahead of sink dispatch and never reads
        # $script:OutputSink, so this passes with the Pdq branch deleted. It is
        # here to confirm the new sink does not break logging, nothing more.
        $script:tmpDir = Join-Path $env:TEMP "nmm-test-$(Get-Random)"
        New-Item -ItemType Directory -Force $script:tmpDir | Out-Null
        Set-OutputSink -Sink Pdq -LogDirectory $script:tmpDir
        Write-ToolOutput 'pdq line to log' -Level Warning
        $logFile = Get-ChildItem $script:tmpDir -Filter *.log | Select-Object -First 1
        $logFile | Should -Not -BeNullOrEmpty
        Get-Content $logFile.FullName -Raw | Should -Match 'pdq line to log'
        Set-OutputSink -Sink Console
        Remove-Item $script:tmpDir -Recurse -Force
        $script:tmpDir = $null
    }

    It 'reaches redirected stdout of a child process' {
        # [Console]::Out and Write-Host are indistinguishable in-process: both
        # appear on the console and both look correct. The sink exists for its
        # behaviour under redirection, which only exists when something redirects.
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $core     = Join-Path $repoRoot 'src\core\02-output.ps1'
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
            ". '$core'; Set-OutputSink -Sink Pdq; Write-ToolOutput 'child stdout probe' -Level Info"
        $LASTEXITCODE | Should -Be 0
        # Assert the level prefix, not just the message text. Write-Host (the
        # Console branch) also reaches a child ConsoleHost's redirected stdout,
        # so matching the bare message cannot distinguish the two sinks - this
        # test passed against the unimplemented sink for exactly that reason.
        # The '[Level  ]' prefix is produced only by the Pdq branch.
        ($out -join "`n") | Should -Match '\[Info\s+\]\s+child stdout probe'
    }
}
