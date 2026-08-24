# Shared browser helpers for browser-backup-restore and browser-clear.
# Plain functions (no registry entries). Single source of truth for where each
# browser stores its data, so the backup set and the clear set cannot drift apart.

function Get-BrowserCatalog {
    # Chromium (Chrome/Edge/Brave) share identical file-sets and profile layout.
    # Some files (History; Firefox cookies.sqlite) are in BOTH backup and clear sets by design: archived, then removed.
    $chromiumBackup = @('Bookmarks','Bookmarks.bak','Preferences','Secure Preferences',
                        'History','Login Data','Login Data For Account','Web Data')
    $chromiumClearF = @('Cookies','Cookies-journal','History','History-journal',
                        'History Provider Cache','Top Sites','Top Sites-journal','Visited Links')
    $chromiumClearD = @('Cache','Code Cache','GPUCache','Service Worker\CacheStorage',
                        'Service Worker\ScriptCache','Session Storage','Local Storage','IndexedDB',
                        'File System','Network','Current Session','Current Tabs','Last Session','Last Tabs')
    # PreserveFiles must never appear in ClearFiles/ClearDirs (locked by browser-helpers.tests.ps1).
    $chromiumPreserve = @('Login Data','Login Data For Account','Web Data','Bookmarks','Bookmarks.bak')

    @(
        @{ Name = 'Chrome'; Family = 'Chromium'
           BasePath = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data')
           ProcessNames = @('chrome'); ProfileGlobs = @('Default','Profile*')
           BackupFiles = $chromiumBackup; ClearFiles = $chromiumClearF; ClearDirs = $chromiumClearD
           PreserveFiles = $chromiumPreserve; PrefsFile = 'Preferences' }
        @{ Name = 'Edge'; Family = 'Chromium'
           BasePath = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')
           ProcessNames = @('msedge'); ProfileGlobs = @('Default','Profile*')
           BackupFiles = $chromiumBackup; ClearFiles = $chromiumClearF; ClearDirs = $chromiumClearD
           PreserveFiles = $chromiumPreserve; PrefsFile = 'Preferences' }
        @{ Name = 'Brave'; Family = 'Chromium'
           BasePath = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data')
           ProcessNames = @('brave'); ProfileGlobs = @('Default','Profile*')
           BackupFiles = $chromiumBackup; ClearFiles = $chromiumClearF; ClearDirs = $chromiumClearD
           PreserveFiles = $chromiumPreserve; PrefsFile = 'Preferences' }
        @{ Name = 'Firefox'; Family = 'Firefox'
           BasePath = (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles')
           ProcessNames = @('firefox'); ProfileGlobs = @('*')
           BackupFiles = @('places.sqlite','key4.db','logins.json','cookies.sqlite','formhistory.sqlite','prefs.js')
           ClearFiles = @('cookies.sqlite','cookies.sqlite-shm','cookies.sqlite-wal',
                          'favicons.sqlite','favicons.sqlite-shm','favicons.sqlite-wal',
                          'permissions.sqlite','permissions.sqlite-shm','permissions.sqlite-wal','content-prefs.sqlite')
           ClearDirs = @('cache2')
           PreserveFiles = @('key4.db','logins.json','places.sqlite','places.sqlite-shm',
                             'places.sqlite-wal','formhistory.sqlite')
           PrefsFile = $null }
    )
}

function Get-BrowserProfiles {
    # Returns the installed profile directories for one browser (empty array if absent).
    param([Parameter(Mandatory)][hashtable]$Browser)
    if (-not (Test-Path -LiteralPath $Browser.BasePath)) { return @() }
    $dirs = @()
    foreach ($glob in $Browser.ProfileGlobs) {
        $dirs += Get-ChildItem -LiteralPath $Browser.BasePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $glob }
    }
    @($dirs | Sort-Object FullName -Unique)
}

function Get-BrowserBackupRoot {
    # Prefer M:\BrowserBackups\<user>; fall back to <Desktop>\BrowserBackups\<user>.
    # Pure resolver - does NOT create the directory (so the report/-Silent path has no side effect).
    param([string]$PreferredRoot = 'M:\BrowserBackups')
    $preferredDrive = Split-Path $PreferredRoot -Qualifier
    if ($preferredDrive -and (Test-Path -LiteralPath $preferredDrive)) {
        $root = $PreferredRoot
    } else {
        $root = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BrowserBackups'
    }
    Join-Path $root $env:USERNAME
}

function Close-Browsers {
    # Graceful CloseMainWindow, wait, then Kill stragglers. Returns the process names it acted on.
    param([Parameter(Mandatory)][string[]]$ProcessNames)
    $closed = @()
    foreach ($proc in $ProcessNames) {
        $running = @(Get-Process -Name $proc -ErrorAction SilentlyContinue)
        foreach ($p in $running) { try { $p.CloseMainWindow() | Out-Null } catch {} }
        if ($running.Count -gt 0) { $closed += $proc }
    }
    Start-Sleep -Seconds 2
    foreach ($proc in $ProcessNames) {
        Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
    }
    @($closed | Sort-Object -Unique)
}
