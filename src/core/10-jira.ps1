# Jira Cloud ticket export. Pushes the session summary onto an existing issue as a
# comment. Supports three config paths checked in order:
#   Personal : %APPDATA%\NMMTools\jira.json              (CurrentUser DPAPI)
#   Machine  : %PROGRAMDATA%\NMMTools\jira.json          (LocalMachine DPAPI)
#   Network  : \\prodnmmfs3\it\matts ps scripts\NMMTools\jira.json (plaintext, NTFS-restricted)
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

function Get-NmmJiraNetworkConfigPath {
    return '\\prodnmmfs3\it\matts ps scripts\NMMTools\jira.json'
}

function Test-NmmJiraKey {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
    return ($Key -cmatch '^[A-Z][A-Z0-9]+-\d+$')
}

function Set-NmmJiraFileAcl {
    # Restricts a Jira config file to Administrators + SYSTEM only, non-inherited. The
    # shared %PROGRAMDATA% path previously relied on ProgramData's default inherited ACL
    # (BUILTIN\Users: Read), which made a machine-wide team credential readable by any local
    # user - this locks the FILE itself, not the parent NMMTools directory (which other
    # tools also write to, e.g. the OnBase self-heal log and download staging dirs, and must
    # keep its normal permissions).
    param([Parameter(Mandatory)][string]$Path)
    & icacls "$Path" /inheritance:r /grant:r 'SYSTEM:F' /grant:r 'BUILTIN\Administrators:F' | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Test-NmmJiraFileAclSafe {
    # Refuses to trust a shared config file whose ACL grants access wider than
    # Administrators/SYSTEM - a config that predates this hardening, or one an attacker
    # widened after the fact, must not be silently loaded.
    param([Parameter(Mandatory)][string]$Path)
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        foreach ($rule in $acl.Access) {
            if ($rule.IdentityReference.Value -match '^(BUILTIN\\Users|Everyone|NT AUTHORITY\\Authenticated Users)$') {
                return $false
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Protect-NmmJiraToken {
    param(
        [Parameter(Mandatory)][string]$Plain,
        [ValidateSet('CurrentUser', 'LocalMachine')][string]$Scope = 'CurrentUser'
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
        [ValidateSet('CurrentUser', 'LocalMachine')][string]$Scope = 'CurrentUser'
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
    # Encrypt before the first write rather than leaving plaintext on disk until the next
    # Import call happens to run - a technician who configures Jira and closes the toolkit
    # previously left a plaintext API token on disk indefinitely.
    $cipher = Protect-NmmJiraToken -Plain $Token -Scope 'CurrentUser'
    $out = [ordered]@{ BaseUrl = $BaseUrl.TrimEnd('/'); Email = $Email; Token = $cipher; TokenProtected = $true }
    ($out | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
}

function Save-NmmJiraSharedConfig {
    # Writes the team/shared key to %PROGRAMDATA%\NMMTools\jira.json. Requires admin rights.
    # Encrypted with LocalMachine DPAPI (decryptable by any principal on THIS machine, which
    # is the point - any technician on this machine can use the shared credential) AND the
    # file itself is ACL-locked to Administrators+SYSTEM, since ProgramData's default
    # inherited ACL alone would let any local standard user read the file directly, bypassing
    # the DPAPI protection's intended scope entirely.
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

    # Lock the ACL before any content (including the encrypted token) is written - locking
    # after the fact would leave the file briefly under the wider inherited ACL.
    New-Item -Path $path -ItemType File -Force -ErrorAction Stop | Out-Null
    if (-not (Set-NmmJiraFileAcl -Path $path)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        throw 'Could not restrict jira.json permissions to Administrators/SYSTEM - refusing to save the shared Jira credential unprotected.'
    }

    $cipher = Protect-NmmJiraToken -Plain $Token -Scope 'LocalMachine'
    $out = [ordered]@{ BaseUrl = $BaseUrl.TrimEnd('/'); Email = $Email; Token = $cipher; TokenProtected = $true }
    ($out | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
}

function Import-NmmJiraConfigFromPath {
    # Internal: load config at a specific path. When NoEncrypt is false (default)
    # and the token is plain-text, auto-encrypts in place on first load.
    # Pass -NoEncrypt for the network share path where write-back is unwanted.
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Scope = 'CurrentUser',
        [switch]$NoEncrypt
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
        if (-not $NoEncrypt) {
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
    }
    return @{ BaseUrl = $baseUrl.TrimEnd('/'); Email = $email; Token = $token }
}

function Save-NmmJiraNetworkConfig {
    # Writes the shared team key to the IT network share as plain text.
    # NTFS permissions on the folder control who can read/write it.
    # Do not set TokenProtected - the file must stay readable by all machines.
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Email,
        [Parameter(Mandatory)][string]$Token
    )
    $path = Get-NmmJiraNetworkConfigPath
    $dir  = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir -PathType Container)) {
        New-Item -ItemType Directory -Force $dir | Out-Null
    }
    $out = [ordered]@{ BaseUrl = $BaseUrl.TrimEnd('/'); Email = $Email; Token = $Token; TokenProtected = $false }
    ($out | ConvertTo-Json) | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop
}

function Import-NmmJiraConfig {
    # Priority: personal (%APPDATA%) > machine (%PROGRAMDATA%) > network share.
    # Tests override the personal path via $script:JiraConfigPathOverride and
    # skip the machine/network paths so they don't pick up real credentials.
    $personal = Import-NmmJiraConfigFromPath -Path (Get-NmmJiraConfigPath) -Scope 'CurrentUser'
    if ($null -ne $personal) { return $personal }

    if (-not $script:JiraConfigPathOverride) {
        $sharedPath = Get-NmmJiraSharedConfigPath
        # Refuse to trust the shared config if its ACL doesn't match what Save-NmmJiraSharedConfig
        # writes (Administrators/SYSTEM only) - a file that predates this hardening, or one
        # whose permissions were widened after the fact, must fail closed rather than be
        # silently read by any local user's process.
        if ((Test-Path $sharedPath -PathType Leaf) -and (Test-NmmJiraFileAclSafe -Path $sharedPath)) {
            $machine = Import-NmmJiraConfigFromPath -Path $sharedPath -Scope 'LocalMachine'
            if ($null -ne $machine) { return $machine }
        }

        # Network share: plaintext, no write-back (other machines must read same file).
        $network = Import-NmmJiraConfigFromPath -Path (Get-NmmJiraNetworkConfigPath) -NoEncrypt
        if ($null -ne $network) { return $network }
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
    # The setup dialog validates https:// at entry, but a config file loaded from disk (shared
    # ProgramData or network-share path) is never re-validated - a hand-edited or stale
    # http:// BaseUrl here would send the Basic-auth token in the clear.
    if ($cfg.BaseUrl -notmatch '^https://') {
        return @{ Success = $false; Message = 'Jira base URL is not https:// - refusing to send credentials. Re-run Jira setup.' }
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

    # Post via the standard REST API with the sd.public.comment property set to
    # internal:true. This is Atlassian's documented way to create an internal
    # agent note in JSM without using the experimental service desk endpoint,
    # which had visibility inconsistencies across agent views.
    $commentUrl = '{0}/rest/api/2/issue/{1}/comment' -f $cfg.BaseUrl, $Key
    $payload    = [ordered]@{
        body       = $wrapped
        properties = @(
            @{ key = 'sd.public.comment'; value = @{ internal = $true } }
        )
    } | ConvertTo-Json -Depth 5
    try {
        Invoke-RestMethod -Method Post -Uri $commentUrl -Headers $headers `
            -ContentType 'application/json' -Body $payload -TimeoutSec 30 -ErrorAction Stop | Out-Null
    } catch {
        return (ConvertTo-NmmJiraError -ErrorRecord $_ -Key $Key)
    }
    return @{ Success = $true; Message = ('Added comment to {0}.' -f $Key) }
}
