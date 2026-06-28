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
