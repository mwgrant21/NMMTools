# Shared core helpers (plain functions, not tool functions - no registry entries needed).
# - Invoke-* : repair-suite steps for Invoke-SystemRepairSuite; each returns @{ Status; Summary } (Temp adds MbFreed).
# - Get-NmmProfileVerdict : pure orphaned-profile classifier used by Remove-OrphanedProfile.
# - Resolve-NmmUser* : resolve the EFFECTIVE user's profile path / registry hive, since a
#   RequiresAdmin=true tool touching HKCU or $env:LOCALAPPDATA/$env:APPDATA silently targets
#   SYSTEM's own profile (not any technician's) when invoked under PDQ/SYSTEM context, and
#   would otherwise report a false Success having changed nothing. Pattern originally proven
#   in Get-RingCentralStatus.ps1 (SID -> Win32_UserProfile.LocalPath); generalized here for
#   reuse by any tool that touches the effective user's profile.

function Test-NmmRunningAsSystem {
    try {
        return ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    } catch {
        return $false
    }
}

function Resolve-NmmLoggedOnUserSid {
    # Resolves the SID of the interactively logged-on user via WMI. Only meaningful when
    # running as SYSTEM - an interactive session already IS that user. Returns
    # @{ Sid = <string-or-null>; Reason = <null-or-explanation> }.
    $loggedOnUser = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    # UserName is 'DOMAIN\user' or '' if no one is logged on
    if ([string]::IsNullOrWhiteSpace($loggedOnUser)) {
        return @{ Sid = $null; Reason = 'no interactive user is logged on (running as SYSTEM)' }
    }
    try {
        $sid = (New-Object System.Security.Principal.NTAccount($loggedOnUser)).
            Translate([System.Security.Principal.SecurityIdentifier]).Value
        return @{ Sid = $sid; Reason = $null }
    } catch {
        return @{ Sid = $null; Reason = ('could not resolve SID for logged-on user {0}' -f $loggedOnUser) }
    }
}

function Resolve-NmmUserProfileBase {
    # Resolves the profile root and AppData Local/Roaming base paths for the effective user -
    # $env:LOCALAPPDATA/$env:APPDATA interactively, or the logged-on user's real profile paths
    # when running as SYSTEM (where those env vars point at the SYSTEM profile). Returns
    # @{ ProfileRoot; Local; Roaming; Reason }, all $null except Reason on failure.
    if (-not (Test-NmmRunningAsSystem)) {
        $profileRoot = if ($env:USERPROFILE) { $env:USERPROFILE } else { $null }
        return @{ ProfileRoot = $profileRoot; Local = $env:LOCALAPPDATA; Roaming = $env:APPDATA; Reason = $null }
    }
    $resolved = Resolve-NmmLoggedOnUserSid
    if (-not $resolved.Sid) { return @{ ProfileRoot = $null; Local = $null; Roaming = $null; Reason = $resolved.Reason } }

    $profileObj = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.SID -eq $resolved.Sid } | Select-Object -First 1
    if (-not $profileObj -or -not $profileObj.LocalPath) {
        return @{ ProfileRoot = $null; Local = $null; Roaming = $null; Reason = ('could not resolve profile path for SID {0}' -f $resolved.Sid) }
    }
    return @{
        ProfileRoot = $profileObj.LocalPath
        Local       = (Join-Path $profileObj.LocalPath 'AppData\Local')
        Roaming     = (Join-Path $profileObj.LocalPath 'AppData\Roaming')
        Reason      = $null
    }
}

function Resolve-NmmUserRegistryHive {
    # Resolves the HKCU-equivalent registry root for the effective user - 'HKCU:'
    # interactively, or 'Registry::HKEY_USERS\<SID>' for the logged-on user when running as
    # SYSTEM (where HKCU: is SYSTEM's own hive, not any technician's). The logged-on user's
    # hive is present under HKEY_USERS for the duration of their session - this does not
    # require impersonation or explicit profile-loading. Returns
    # @{ Root = <path-or-null>; Reason = <null-or-explanation> }.
    if (-not (Test-NmmRunningAsSystem)) {
        return @{ Root = 'HKCU:'; Reason = $null }
    }
    $resolved = Resolve-NmmLoggedOnUserSid
    if (-not $resolved.Sid) { return @{ Root = $null; Reason = $resolved.Reason } }

    $hivePath = 'Registry::HKEY_USERS\{0}' -f $resolved.Sid
    if (-not (Test-Path -LiteralPath $hivePath)) {
        return @{ Root = $null; Reason = ('logged-on user''s registry hive is not loaded (SID {0})' -f $resolved.Sid) }
    }
    return @{ Root = $hivePath; Reason = $null }
}

function Invoke-DismRestoreHealth {
    Write-ToolOutput 'DISM RestoreHealth: repairing component store (10-20 min, may contact Windows Update)...' -Level Info
    $lines = @(& "$env:SystemRoot\System32\dism.exe" /Online /Cleanup-Image /RestoreHealth 2>&1)
    $exit = $LASTEXITCODE
    foreach ($line in $lines) {
        $text = [string]$line
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-ToolOutput ('  {0}' -f $text) -Level Detail
        }
    }
    if ($exit -eq 0) {
        return @{ Status = 'Success'; Summary = 'DISM RestoreHealth completed (exit 0)' }
    } elseif ($exit -eq 3010) {
        # ERROR_SUCCESS_REBOOT_REQUIRED - a legitimate success code, not a failure.
        return @{ Status = 'Warning'; Summary = 'DISM RestoreHealth completed but requires a reboot to finish (exit 3010)' }
    } else {
        return @{ Status = 'Failed'; Summary = ('DISM RestoreHealth exited {0}' -f $exit) }
    }
}

function Invoke-SfcScan {
    Write-ToolOutput 'SFC: running sfc /scannow (10-15 min)...' -Level Info
    $savedEnc = [Console]::OutputEncoding
    $lines = @()
    $sfcExit = 0
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $lines = @(& "$env:SystemRoot\System32\sfc.exe" /scannow 2>&1)
        $sfcExit = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $savedEnc
    }
    foreach ($line in $lines) {
        $text = [string]$line
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-ToolOutput ('  {0}' -f $text) -Level Detail
        }
    }
    $allText = ($lines | ForEach-Object { [string]$_ }) -join ' '
    if ($allText -match 'did not find any integrity violations') {
        return @{ Status = 'Success'; Summary = ('SFC: no integrity violations (exit {0})' -f $sfcExit) }
    }
    if ($allText -match 'found corrupt files and successfully repaired') {
        return @{ Status = 'Success'; Summary = ('SFC: corrupt files repaired (exit {0})' -f $sfcExit) }
    }
    if ($allText -match 'found corrupt files but was unable') {
        return @{ Status = 'Warning'; Summary = ('SFC: corrupt files found but repair failed (exit {0}); run DISM then retry' -f $sfcExit) }
    }
    if ($sfcExit -eq 0) {
        return @{ Status = 'Success'; Summary = 'SFC completed (exit 0; check CBS.log for details)' }
    } else {
        return @{ Status = 'Warning'; Summary = ('SFC exited {0}; review CBS.log' -f $sfcExit) }
    }
}

function Invoke-ConservativeTempCleanup {
    Write-ToolOutput 'Temp cleanup: clearing current-process TEMP and C:\Windows\Temp...' -Level Info
    $tempPaths = @($env:TEMP, 'C:\Windows\Temp')
    $totalFreed = [int64]0
    foreach ($path in $tempPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-ToolOutput '  (skipped empty temp path)' -Level Detail
            continue
        }
        if (-not (Test-Path $path)) {
            Write-ToolOutput ('  {0}: not present, skipped' -f $path) -Level Detail
            continue
        }
        $before = [int64]0
        try {
            $sz = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($sz) { $before = [int64]$sz }
        } catch { Write-ToolOutput '  (size measurement unavailable)' -Level Detail }
        Get-ChildItem $path -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        $after = [int64]0
        try {
            $sz = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($sz) { $after = [int64]$sz }
        } catch { Write-ToolOutput '  (size measurement unavailable)' -Level Detail }
        $freed = [math]::Max([int64]0, $before - $after)
        $totalFreed += $freed
        Write-ToolOutput ('  {0}: freed {1:N1} MB' -f $path, ($freed / 1MB)) -Level Info
    }
    $mbFreed = [math]::Round($totalFreed / 1MB, 1)
    return @{ Status = 'Success'; Summary = ('Temp cleanup freed {0:N1} MB' -f $mbFreed); MbFreed = $mbFreed }
}

function Get-NmmProfileVerdict {
    # Pure classification for one user profile, from already-determined facts. Never throws.
    # Returns: 'Protected' | 'Orphan-UnknownSid' | 'Orphan-MissingFolder' | 'Healthy'.
    # Protection wins over everything (a Special/Loaded/own-account profile is never an orphan,
    # even if its SID does not resolve). Then unknown-SID, then missing-folder, else healthy.
    param(
        [bool]$Special,
        [bool]$Loaded,
        [bool]$IsCurrentUser,
        [bool]$SidResolves,
        [bool]$FolderExists
    )
    if ($Special -or $Loaded -or $IsCurrentUser) { return 'Protected' }
    if (-not $SidResolves)  { return 'Orphan-UnknownSid' }
    if (-not $FolderExists) { return 'Orphan-MissingFolder' }
    return 'Healthy'
}
