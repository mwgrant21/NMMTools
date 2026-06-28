BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\10-jira.ps1')
}

Describe 'Test-NmmJiraKey' {
    It 'accepts well-formed keys' {
        Test-NmmJiraKey -Key 'DESK-12345' | Should -BeTrue
        Test-NmmJiraKey -Key 'ABC1-7'     | Should -BeTrue
    }
    It 'rejects malformed keys' {
        Test-NmmJiraKey -Key 'desk-12345' | Should -BeFalse   # lowercase
        Test-NmmJiraKey -Key 'DESK12345'  | Should -BeFalse   # no dash
        Test-NmmJiraKey -Key '12-34'      | Should -BeFalse   # no leading letter
        Test-NmmJiraKey -Key ''           | Should -BeFalse
        Test-NmmJiraKey -Key $null        | Should -BeFalse
    }
}

Describe 'Get-NmmJiraConfigPath' {
    It 'honors the override' {
        $script:JiraConfigPathOverride = 'C:\temp\fake-jira.json'
        Get-NmmJiraConfigPath | Should -Be 'C:\temp\fake-jira.json'
        $script:JiraConfigPathOverride = $null
    }
    It 'defaults under ProgramData when no override' {
        $script:JiraConfigPathOverride = $null
        Get-NmmJiraConfigPath | Should -Match 'NMMTools.jira\.json$'
    }
}

Describe 'Jira config' {
    BeforeEach {
        $script:JiraConfigPathOverride = Join-Path $env:TEMP ('nmm-jira-test-{0}.json' -f (Get-Random))
    }
    AfterEach {
        if ($script:JiraConfigPathOverride -and (Test-Path $script:JiraConfigPathOverride)) {
            Remove-Item $script:JiraConfigPathOverride -Force -ErrorAction SilentlyContinue
        }
        $script:JiraConfigPathOverride = $null
    }

    It 'returns null for a missing file' {
        Import-NmmJiraConfig | Should -BeNullOrEmpty
    }
    It 'returns null and does not throw on corrupt json' {
        Set-Content -Path $script:JiraConfigPathOverride -Value '{ not json' -Encoding UTF8
        { Import-NmmJiraConfig } | Should -Not -Throw
        Import-NmmJiraConfig | Should -BeNullOrEmpty
    }
    It 'returns null when a required field is missing' {
        '{ "BaseUrl": "https://x.atlassian.net", "Email": "a@b.c" }' |
            Set-Content -Path $script:JiraConfigPathOverride -Encoding UTF8
        Import-NmmJiraConfig | Should -BeNullOrEmpty
    }
    It 'loads a plaintext config, encrypts it at rest, and round-trips the token' {
        @{ BaseUrl='https://acme.atlassian.net/'; Email='svc@acme.com'; Token='secret-123'; TokenProtected=$false } |
            ConvertTo-Json | Set-Content -Path $script:JiraConfigPathOverride -Encoding UTF8

        $cfg = Import-NmmJiraConfig
        $cfg.BaseUrl | Should -Be 'https://acme.atlassian.net'   # trailing slash trimmed
        $cfg.Email   | Should -Be 'svc@acme.com'
        $cfg.Token   | Should -Be 'secret-123'

        # File must now be encrypted at rest.
        $raw = Get-Content $script:JiraConfigPathOverride -Raw | ConvertFrom-Json
        $raw.TokenProtected | Should -BeTrue
        $raw.Token | Should -Not -Be 'secret-123'

        # Second load decrypts back to the original token.
        (Import-NmmJiraConfig).Token | Should -Be 'secret-123'
    }
    It 'protect/unprotect round-trips' {
        $c = Protect-NmmJiraToken -Plain 'abc-xyz'
        $c | Should -Not -Be 'abc-xyz'
        Unprotect-NmmJiraToken -Cipher $c | Should -Be 'abc-xyz'
    }
}
