# Target-user resolution.
#
# HKCU: and $env:APPDATA resolve against the account the PROCESS runs as, not
# the person sitting at the machine. Three of our launch contexts break that
# assumption:
#
#   - a technician elevates with their own admin credentials on a standard
#     user's laptop (UAC over-the-shoulder), so the toolkit runs as the admin
#   - PDQ Deploy runs the step as SYSTEM
#   - a scheduled task runs under whatever principal it was registered with
#
# In all three the per-user repair lands in the wrong hive and the wrong
# profile, the write genuinely succeeds, and the tool reports Success. Only the
# single case where the technician is fixing their OWN machine behaves as
# intended - which is exactly why this class of bug survives desk testing.
#
# Get-TargetUserContext resolves the account a tool should actually modify and
# reports honestly when it cannot. Tools must treat Resolved = $false as
# "refuse the per-user work", never as "fall back to HKCU:".

function Get-TargetUserContext {
    [CmdletBinding()]
    param([switch]$Refresh)

    if ($script:TargetUserContext -and -not $Refresh) { return $script:TargetUserContext }

    $ctx = [PSCustomObject]@{
        Resolved     = $false   # can per-user state be reached at all
        IsRedirected = $false   # target account differs from the process account
        # TRUE only when the calling process IS the target user. Test this -
        # never '-not $ctx.IsRedirected' - because IsRedirected is also $false
        # in the failure paths (no interactive user, identity unreadable), so
        # '-not IsRedirected' takes the "we are the user, go ahead" branch in
        # exactly the case where nothing is known.
        IsCurrentUser = $false
        ProcessName  = $null
        ProcessSid   = $null
        UserName     = $null
        # Safe for string formatting before the target is known, so messages
        # never render as 'settings for  could not be read'.
        DisplayName  = 'the logged-on user'
        Sid          = $null
        HiveRoot     = 'HKCU:'  # prefix for per-user registry paths
        ProfilePath  = $null
        AppData      = $null
        LocalAppData = $null
        Reason       = ''
    }

    # --- who is this process ---
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $ctx.ProcessName = $id.Name
        $ctx.ProcessSid  = $id.User.Value
    } catch {
        $ctx.Reason = 'could not read the process identity'
        $script:TargetUserContext = $ctx
        return $ctx
    }

    # --- who is logged on at the console ---
    $loggedOn = $null
    try {
        $loggedOn = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    } catch { }
    if ([string]::IsNullOrWhiteSpace($loggedOn)) {
        try {
            $loggedOn = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($loggedOn)) {
        # No interactive user (PDQ against an unattended machine, for example).
        # Per-user work is impossible, not merely redirected.
        $ctx.Reason = 'no interactive user is logged on'
        $script:TargetUserContext = $ctx
        return $ctx
    }
    $ctx.UserName    = $loggedOn
    $ctx.DisplayName = $loggedOn

    try {
        $nt      = New-Object System.Security.Principal.NTAccount($loggedOn)
        $ctx.Sid = $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        $ctx.Reason = ("could not resolve a SID for '{0}'" -f $loggedOn)
        $script:TargetUserContext = $ctx
        return $ctx
    }

    # --- same account: HKCU: and the process environment are already correct ---
    if ($ctx.Sid -eq $ctx.ProcessSid) {
        $ctx.Resolved      = $true
        $ctx.IsRedirected  = $false
        $ctx.IsCurrentUser = $true
        $ctx.HiveRoot     = 'HKCU:'
        $ctx.ProfilePath  = $env:USERPROFILE
        $ctx.AppData      = $env:APPDATA
        $ctx.LocalAppData = $env:LOCALAPPDATA
        $ctx.Reason       = 'process account is the logged-on user'
        $script:TargetUserContext = $ctx
        return $ctx
    }

    # --- different account: redirect to the logged-on user's hive ---
    $ctx.IsRedirected = $true
    $hiveRoot = 'Registry::HKEY_USERS\{0}' -f $ctx.Sid

    if (-not (Test-Path -LiteralPath $hiveRoot)) {
        # The hive is only mounted while the user has an active session. Loading
        # ntuser.dat by hand is out of scope here: it can corrupt a live profile
        # and needs an unload that survives every failure path.
        $ctx.Reason = ("the hive for '{0}' is not loaded (user not signed in)" -f $loggedOn)
        $script:TargetUserContext = $ctx
        return $ctx
    }

    # ProfileImagePath is authoritative; C:\Users\<name> is a guess that breaks
    # on renamed accounts, .DOMAIN suffixes, and relocated profile roots.
    $profilePath = $null
    $plKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\{0}' -f $ctx.Sid
    if (Test-Path -LiteralPath $plKey) {
        $profilePath = (Get-ItemProperty -LiteralPath $plKey -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
        if ($profilePath) { $profilePath = [System.Environment]::ExpandEnvironmentVariables($profilePath) }
    }
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $ctx.Reason = ("no ProfileImagePath for SID {0}" -f $ctx.Sid)
        $script:TargetUserContext = $ctx
        return $ctx
    }
    $ctx.ProfilePath = $profilePath

    # Shell Folders carries the user's REAL AppData locations, which differ from
    # <profile>\AppData\Roaming wherever folder redirection is in play.
    $shellFolders = '{0}\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -f $hiveRoot
    $appData      = $null
    $localAppData = $null
    if (Test-Path -LiteralPath $shellFolders) {
        $sf = Get-ItemProperty -LiteralPath $shellFolders -ErrorAction SilentlyContinue
        if ($sf) {
            $appData      = $sf.'AppData'
            $localAppData = $sf.'Local AppData'
        }
    }
    # Shell Folders lives in the TARGET USER'S OWN HIVE, so these two values are
    # attacker-supplied: a standard user can set 'Local AppData' to C:\Windows
    # and steer an elevated delete out of their profile entirely. ProfileImagePath
    # above is safe (HKLM, admin-only); these are not. Accept them only if they
    # still resolve inside the profile, and say so loudly when rejecting - a
    # blank-value fallback alone does not catch a malicious value.
    $safeUnder = {
        param([string]$Candidate)
        if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }
        try {
            $c = [System.IO.Path]::GetFullPath([System.Environment]::ExpandEnvironmentVariables($Candidate))
            $r = [System.IO.Path]::GetFullPath($profilePath)
        } catch { return $false }
        if (-not $r.EndsWith([System.IO.Path]::DirectorySeparatorChar)) { $r += [System.IO.Path]::DirectorySeparatorChar }
        return ($c + [System.IO.Path]::DirectorySeparatorChar).StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)
    }
    foreach ($pair in @(@{ Name = 'AppData'; Val = $appData }, @{ Name = 'Local AppData'; Val = $localAppData })) {
        if (-not [string]::IsNullOrWhiteSpace($pair.Val) -and -not (& $safeUnder $pair.Val)) {
            $ctx.Reason = ("Shell Folders '{0}' points outside the profile ({1}); using the default instead" -f $pair.Name, $pair.Val)
            if ($pair.Name -eq 'AppData') { $appData = $null } else { $localAppData = $null }
        }
    }
    if ([string]::IsNullOrWhiteSpace($appData))      { $appData      = Join-Path $profilePath 'AppData\Roaming' }
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = Join-Path $profilePath 'AppData\Local' }

    $ctx.HiveRoot     = $hiveRoot
    $ctx.AppData      = $appData
    $ctx.LocalAppData = $localAppData
    $ctx.Resolved     = $true
    $ctx.Reason       = ("redirected from '{0}' to the logged-on user '{1}'" -f $ctx.ProcessName, $loggedOn)

    $script:TargetUserContext = $ctx
    return $ctx
}

function Get-UserHivePath {
    # Builds a per-user registry path under whichever hive the context resolved
    # to.
    #
    # THROWS when the context is unresolved. This is deliberate and load-bearing.
    # The previous version returned 'HKCU:\...' in that case - a real, usable
    # path pointing at the CALLING account's hive - so a caller that forgot to
    # gate on Resolved got a plausible wrong answer instead of an error. Four
    # tools did exactly that and reported the technician's registry state as the
    # user's. Same family as the documented @() array-unroll trap: a function
    # that returns a believable value on failure gets mis-consumed at the call
    # site, and no amount of per-file vigilance fixes it reliably.
    #
    # A caller that genuinely wants the calling account's hive must say so with
    # -AllowUnresolved, which makes the intent visible in review.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$SubPath,
        [switch]$AllowUnresolved
    )
    if (-not $Context.Resolved -and -not $AllowUnresolved) {
        throw ("Get-UserHivePath: target user is unresolved ({0}). Gate on `$ctx.Resolved before building per-user paths, or pass -AllowUnresolved if the calling account's hive is genuinely intended." -f $Context.Reason)
    }
    return ('{0}\{1}' -f $Context.HiveRoot.TrimEnd('\'), $SubPath.TrimStart('\'))
}

function Test-UserPathContained {
    # Containment gate for any path an ELEVATED process is about to delete or
    # write under a target user's profile.
    #
    # WHY THIS EXISTS: redirecting per-user work to the logged-on user points an
    # elevated process at a tree the standard user fully controls. Two ways that
    # is abused, both reproduced non-elevated on a 5.1 box:
    #
    #   1. Directory junction. A user turns
    #      %LOCALAPPDATA%\Packages\MSTeams_...\LocalCache into a junction to
    #      C:\Windows\System32, then opens a ticket. Get-ChildItem enumerates
    #      THROUGH the junction and the piped Remove-Item deletes the real
    #      target. mklink /J needs no privilege.
    #   2. Shell Folders. AppData / Local AppData are read from the user's OWN
    #      hive, so the user can point the profile root at C:\Windows and move
    #      the whole operation outside their profile.
    #
    # Either check alone is bypassable, so both run: reject reparse points, AND
    # assert the resolved path is still inside the profile. Returns $true only
    # when the path is safe to recurse into.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not $Context.Resolved) { return $false }
    if ([string]::IsNullOrWhiteSpace($Context.ProfilePath)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }

    # 1. Reparse point (junction / symlink / mount point) - never recurse.
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-ToolOutput ('SECURITY: refusing to recurse into a reparse point: {0}' -f $Path) -Level Warning
        return $false
    }

    # 2. Containment. GetFullPath normalises '..' and short names; the trailing
    #    separator stops 'C:\Users\bob2' passing as inside 'C:\Users\bob'.
    try {
        $full = [System.IO.Path]::GetFullPath($item.FullName)
        $root = [System.IO.Path]::GetFullPath($Context.ProfilePath)
    } catch {
        return $false
    }
    if (-not $root.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $root = $root + [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not ($full + [System.IO.Path]::DirectorySeparatorChar).StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-ToolOutput ('SECURITY: refusing to act outside the target profile. Path resolves to {0}, which is not under {1}.' -f $full, $Context.ProfilePath) -Level Warning
        return $false
    }
    return $true
}

function Remove-UserPathContent {
    # The ONLY sanctioned way to clear a directory under a target user's
    # profile. Replaces the bare
    #   Get-ChildItem $d -Force | Remove-Item -Recurse -Force
    # pattern, which follows junctions straight out of the profile.
    #
    # Children are individually re-checked: the parent passing containment does
    # not make its children safe, because any child can itself be a junction.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path
    )

    if (-not (Test-UserPathContained -Context $Context -Path $Path)) { return $false }

    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        if ($child.PSIsContainer) {
            if ($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                # Delete the LINK itself, never its contents.
                Write-ToolOutput ('  removing reparse point without following it: {0}' -f $child.FullName) -Level Detail
                try { [System.IO.Directory]::Delete($child.FullName, $false) } catch { }
                continue
            }
            if (-not (Test-UserPathContained -Context $Context -Path $child.FullName)) { continue }
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Remove-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    return $true
}

function Write-UserContextNotice {
    # Puts the target account in the log before any per-user write happens, so a
    # log read months later shows which hive was actually touched.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    if (-not $Context.Resolved) {
        Write-ToolOutput ('Cannot reach the logged-on user''s settings: {0}.' -f $Context.Reason) -Level Warning
        Write-ToolOutput ('Running as: {0}' -f $Context.ProcessName) -Level Detail
        return
    }
    if ($Context.IsRedirected) {
        Write-ToolOutput ('Running as {0}, applying user settings to {1}' -f $Context.ProcessName, $Context.UserName) -Level Info
        Write-ToolOutput ('Target hive   : {0}' -f $Context.HiveRoot) -Level Detail
        Write-ToolOutput ('Target profile: {0}' -f $Context.ProfilePath) -Level Detail
    } else {
        Write-ToolOutput ('Applying user settings to {0} (current session)' -f $Context.UserName) -Level Detail
    }
}
