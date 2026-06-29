# Jira Cloud ticket export. Pushes the session summary onto an existing issue as a
# comment. Supports two config paths:
#   Personal : %APPDATA%\NMMTools\jira.json  (CurrentUser DPAPI  - checked first)
#   Shared   : %PROGRAMDATA%\NMMTools\jira.json (LocalMachine DPAPI - team fallback)
# All config/network failures are returned, never thrown -
# the Ticket Export dialog must never crash on them.

$script:JiraConfigPathOverride = $null   # tests set this to a temp file

function Get-NmmJiraConfigPath {
    if ($script:JiraConfigPathOverride) { return $script:JiraConfigPathOverride }
    $base = [Environment]::GetFolderPath('ApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:APPDATA }
    return (Join-Path $base 'NMMTools\jira.json')
}

function Get-NmmJiraSharedConfigPath {
    $base = [Environment]::GetFolderPath('CommonApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:PROGRAMDATA }
    return (Join-Path $base 'NMMTools\jira.json')
}

function Test-NmmJiraKey {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return ($Key -cmatch '^[A-Z][A-Z0-9]+-\d+$')
}

function Protect-NmmJiraToken {
    param(
        [Parameter(Mandatory)][string]$Plain,
        [string]$Scope = 'CurrentUser'
    )
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $bytes     = [System.Text.Encoding]::UTF8.GetBytes($Plain)
    $dpiaScope = [System.Security.Cryptography.DataProtectionScope]::$Scope
    $enc       = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, $dpiaScope)
    return [Convert]::ToBase64String($enc)
}

function Unprotect-NmmJiraToken {
    param(
        [Parameter(Mandatory)][string]$Cipher,
        [string]$Scope = 'CurrentUser'
    )
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $enc       = [Convert]::FromBase64String($Cipher)
    $dpiaScope = [System.Security.Cryptography.DataProtectionScope]::$Scope
    $dec       = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, $dpiaScope)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

function Save-NmmJiraConfig {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][string]$Token
    )
    $path = Get-NmmJiraConfigPath
    $dir  = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir -PathType Container)) {
        New-Item -ItemType Directory -Force $dir | Out-Null
    }
    # Save plain text; Import-NmmJiraConfig will encrypt on first load
    $out = [ordered]@{ BaseUrl = $BaseUrl.TrimEnd('/'); Email = $Email; Token = $Token; TokenProtected = $false }
    ($out | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
}

function Save-NmmJiraSharedConfig {
    # Writes the team/shared key to %PROGRAMDATA%\NMMTools\jira.json.
    # Requires admin rights. Saved as plain text; first Import encrypts with
    # LocalMachine DPAPI so any user on that machine can read it.
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][string]$Token
    )
    $path = Get-NmmJiraSharedConfigPath
    $dir  = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir -PathType Container)) {
        New-Item -ItemType Directory -Force $dir | Out-Null
    }
    $out = [ordered]@{ BaseUrl = $BaseUrl.TrimEnd('/'); Email = $Email; Token = $Token; TokenProtected = $false }
    ($out | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
}

function Import-NmmJiraConfigFromPath {
    # Internal: load and (if needed) auto-encrypt config at a specific path/scope.
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Scope = 'CurrentUser'
    )
    if (-not (Test-Path $Path -PathType Leaf)) { return $null }
    try {
        $json = Get-Content $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
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
        try { $token = Unprotect-NmmJiraToken -Cipher $rawToken -Scope $Scope } catch { return $null }
    } else {
        $token = $rawToken
        # First load: encrypt the plain-text token in place. Non-fatal on failure.
        try {
            $cipher = Protect-NmmJiraToken -Plain $token -Scope $Scope
            $out = [ordered]@{ BaseUrl = $baseUrl; Email = $email; Token = $cipher; TokenProtected = $true }
            $dir = Split-Path $Path -Parent
            if ($dir -and -not (Test-Path $dir -PathType Container)) {
                New-Item -ItemType Directory -Force $dir | Out-Null
            }
            ($out | ConvertTo-Json) | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
        } catch { }
    }
    return @{ BaseUrl = $baseUrl.TrimEnd('/'); Email = $email; Token = $token }
}

function Import-NmmJiraConfig {
    # Personal config (%APPDATA%) takes priority over shared (%PROGRAMDATA%).
    # Tests can override the personal path via $script:JiraConfigPathOverride.
    $personal = Import-NmmJiraConfigFromPath -Path (Get-NmmJiraConfigPath) -Scope 'CurrentUser'
    if ($null -ne $personal) { return $personal }

    # Only fall through to shared path when no override is set (tests use override only).
    if (-not $script:JiraConfigPathOverride) {
        $shared = Import-NmmJiraConfigFromPath -Path (Get-NmmJiraSharedConfigPath) -Scope 'LocalMachine'
        if ($null -ne $shared) { return $shared }
    }
    return $null
}

function ConvertTo-NmmJiraError {
    # Status extraction targets Windows PowerShell 5.1 (the runtime): there,
    # Invoke-RestMethod throws a WebException whose .Response.StatusCode is a
    # populated enum, so the 401/403/404 messages resolve. On pwsh 7 the
    # exception model differs and .Response is often null, collapsing to the
    # generic "Could not reach Jira" message - acceptable, since 5.1 is target.
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
        401     { return @{ Success = $false; Message = 'Authentication failed - check your Jira API token.' } }
        403     { return @{ Success = $false; Message = 'Authentication failed - check your Jira API token.' } }
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
    $cfg = try { Import-NmmJiraConfig } catch { $null }
    if ($null -eq $cfg) {
        return @{ Success = $false; Message = 'Jira is not configured for this user.' }
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

    $attribution = 'NMMToolkit export by {0} on {1}' -f $env:USERNAME, $env:COMPUTERNAME
    $wrapped     = "{0}`n{{code}}`n{1}`n{{code}}" -f $attribution, $Body

    # Try JSM service desk endpoint first so the comment lands as an internal
    # note (not visible to the customer). Falls back to the standard API for
    # non-JSM projects where the service desk endpoint returns 404.
    $sdUrl      = '{0}/rest/servicedeskapi/request/{1}/comment' -f $cfg.BaseUrl, $Key
    $sdPayload  = @{ body = $wrapped; public = $false } | ConvertTo-Json
    $sdHeaders  = $headers.Clone()
    $sdHeaders['X-ExperimentalApi'] = 'opt-in'
    $posted = $false
    try {
        Invoke-RestMethod -Method Post -Uri $sdUrl -Headers $sdHeaders `
            -ContentType 'application/json' -Body $sdPayload -TimeoutSec 30 -ErrorAction Stop | Out-Null
        $posted = $true
    } catch {
        $errStatus = $null
        try { $errStatus = [int]$_.Exception.Response.StatusCode } catch { }
        if ($errStatus -ne 404) {
            return (ConvertTo-NmmJiraError -ErrorRecord $_ -Key $Key)
        }
    }

    if (-not $posted) {
        $commentUrl = '{0}/rest/api/2/issue/{1}/comment' -f $cfg.BaseUrl, $Key
        $payload    = @{ body = $wrapped } | ConvertTo-Json
        try {
            Invoke-RestMethod -Method Post -Uri $commentUrl -Headers $headers `
                -ContentType 'application/json' -Body $payload -TimeoutSec 30 -ErrorAction Stop | Out-Null
        } catch {
            return (ConvertTo-NmmJiraError -ErrorRecord $_ -Key $Key)
        }
    }
    return @{ Success = $true; Message = ('Added comment to {0}.' -f $Key) }
}
