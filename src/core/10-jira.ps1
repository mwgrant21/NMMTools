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

function Protect-NmmJiraToken {
    param([Parameter(Mandatory)][string]$Plain)
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Plain)
    $enc   = [System.Security.Cryptography.ProtectedData]::Protect(
                $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Convert]::ToBase64String($enc)
}

function Unprotect-NmmJiraToken {
    param([Parameter(Mandatory)][string]$Cipher)
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $enc = [Convert]::FromBase64String($Cipher)
    $dec = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $enc, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

function Import-NmmJiraConfig {
    $path = Get-NmmJiraConfigPath
    if (-not (Test-Path $path -PathType Leaf)) { return $null }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }
    if (-not $json) { return $null }

    $baseUrl  = [string]$json.BaseUrl
    $email    = [string]$json.Email
    $rawToken = [string]$json.Token
    if ([string]::IsNullOrWhiteSpace($baseUrl) -or
        [string]::IsNullOrWhiteSpace($email)   -or
        [string]::IsNullOrWhiteSpace($rawToken)) { return $null }

    $protected = $false
    if ($null -ne $json.TokenProtected) { $protected = [bool]$json.TokenProtected }

    if ($protected) {
        try { $token = Unprotect-NmmJiraToken -Cipher $rawToken } catch { return $null }
    } else {
        $token = $rawToken
        # First run after deployment: re-save with the token encrypted. Non-fatal on failure.
        try {
            $cipher = Protect-NmmJiraToken -Plain $token
            $out = [ordered]@{ BaseUrl = $baseUrl; Email = $email; Token = $cipher; TokenProtected = $true }
            $dir = Split-Path $path -Parent
            if ($dir -and -not (Test-Path $dir -PathType Container)) {
                New-Item -ItemType Directory -Force $dir | Out-Null
            }
            ($out | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }
    return @{ BaseUrl = $baseUrl.TrimEnd('/'); Email = $email; Token = $token }
}
