# Jira Cloud ticket export. Pushes the session summary onto an existing issue as a
# comment. Config + shared service-account token live in %PROGRAMDATA%\NMMTools\jira.json;
# the token is DPAPI-encrypted (LocalMachine) at rest. All config/network failures are
# returned, never thrown - the Ticket Export dialog must never crash on them.

$script:JiraConfigPathOverride = $null   # tests set this to a temp file

function Get-NmmJiraConfigPath {
    if ($script:JiraConfigPathOverride) { return $script:JiraConfigPathOverride }
    $base = [Environment]::GetFolderPath('CommonApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:ProgramData }
    return (Join-Path $base 'NMMTools\jira.json')
}

function Test-NmmJiraKey {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return ($Key -cmatch '^[A-Z][A-Z0-9]+-\d+$')
}
