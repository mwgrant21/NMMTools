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

function ConvertTo-NmmJiraError {
    param($ErrorRecord, [string]$Key)
    $status = $null
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and ($resp.PSObject.Properties.Name -contains 'StatusCode')) {
            $status = [int]$resp.StatusCode
        }
    } catch { $status = $null }

    if ($null -eq $status) {
        return @{ Success = $false; Message = ('Could not reach Jira ({0}).' -f $ErrorRecord.Exception.Message) }
    }
    switch ($status) {
        401     { return @{ Success = $false; Message = 'Authentication failed - check the Jira service account token.' } }
        403     { return @{ Success = $false; Message = 'Authentication failed - check the Jira service account token.' } }
        404     { return @{ Success = $false; Message = ('Issue {0} not found or not accessible.' -f $Key) } }
        default { return @{ Success = $false; Message = ('Jira returned an error ({0}).' -f $status) } }
    }
}

function Send-NmmJiraComment {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Body
    )
    if (-not (Test-NmmJiraKey -Key $Key)) {
        return @{ Success = $false; Message = 'Enter a valid issue key, e.g. DESK-12345.' }
    }
    $cfg = Import-NmmJiraConfig
    if ($null -eq $cfg) {
        return @{ Success = $false; Message = 'Jira is not configured on this machine.' }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pair    = '{0}:{1}' -f $cfg.Email, $cfg.Token
    $b64     = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    $headers = @{ Authorization = ('Basic {0}' -f $b64) }

    $verifyUrl = '{0}/rest/api/2/issue/{1}?fields=key' -f $cfg.BaseUrl, $Key
    try {
        Invoke-RestMethod -Method Get -Uri $verifyUrl -Headers $headers -TimeoutSec 30 -ErrorAction Stop | Out-Null
    } catch {
        return (ConvertTo-NmmJiraError -ErrorRecord $_ -Key $Key)
    }

    $commentUrl = '{0}/rest/api/2/issue/{1}/comment' -f $cfg.BaseUrl, $Key
    $wrapped    = "{{code}}`n{0}`n{{code}}" -f $Body
    $payload    = @{ body = $wrapped } | ConvertTo-Json
    try {
        Invoke-RestMethod -Method Post -Uri $commentUrl -Headers $headers `
            -ContentType 'application/json' -Body $payload -TimeoutSec 30 -ErrorAction Stop | Out-Null
    } catch {
        return (ConvertTo-NmmJiraError -ErrorRecord $_ -Key $Key)
    }
    return @{ Success = $true; Message = ('Added comment to {0}.' -f $Key) }
}
