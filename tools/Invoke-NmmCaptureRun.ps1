<#
.SYNOPSIS
    Wraps a real NMM Toolkit run and captures everything needed to diagnose a
    fleet-only failure, then zips it.

.DESCRIPTION
    Run this INSTEAD OF NMMTools.ps1, from the SAME elevated PowerShell window
    the technician normally uses. It does not change how the toolkit runs: the
    artifact is invoked in-process with the call operator, so the elevation
    state, host, apartment state, and language mode are identical to a normal
    launch.

    It records, into one folder on the Desktop:

      context.txt              host, engine, identity, elevation, artifact
                               provenance and encoding
      hive-compare-before.txt  camera/mic consent state in BOTH the elevated
      hive-compare-after.txt   account's hive and the LOGGED-ON user's hive
      transcript.txt           everything printed in this console window
      errors.txt               every error record raised during the run
      log\NMMTools-*.log       the toolkit's own session log (forced on)
      env-probe.txt            Get-NmmEnvironmentProbe output, if present

    The hive comparison is the point. When a technician elevates with their own
    admin credentials on a standard user's laptop, the elevated process runs as
    the ADMIN account, so every HKCU: write in a tool lands in the admin's hive
    instead of the affected user's. These two files show that directly.

    Read-only apart from what the toolkit itself does.

.PARAMETER Artifact
    Path to NMMTools.ps1. Defaults to C:\NMMTools.ps1, then the Desktop copy.

.PARAMETER Mode
    Launch mode handed to the artifact. Defaults to GUI, matching the artifact's
    own default.

.PARAMETER Tool
    Optional tool slug or legacy number. When supplied the artifact is run with
    -Tool instead of opening a menu, which is the fastest reproduction path.

.PARAMETER Silent
    Passed through to the artifact. Only meaningful with -Tool.

.PARAMETER NoRun
    Capture context and hive state only; do not launch the toolkit.

.EXAMPLE
    .\Invoke-NmmCaptureRun.ps1
    Opens the toolkit GUI as usual and captures the whole session.

.EXAMPLE
    .\Invoke-NmmCaptureRun.ps1 -Tool teams-camera-repair
    Reproduces the camera/mic repair failure with the least noise.

.NOTES
    Write-Host is used intentionally for interactive console output. This is an
    operator-run diagnostic, not a PDQ Deploy step - the same exception already
    documented in Get-NmmEnvironmentProbe.ps1.

    PowerShell 5.1 target. ASCII only. Writes UTF-8 without BOM.
#>
[CmdletBinding()]
param(
    [string]$Artifact,
    [ValidateSet('GUI','Console')][string]$Mode = 'GUI',
    [string]$Tool,
    [switch]$Silent,
    [switch]$NoRun,
    [string]$OutRoot = ([Environment]::GetFolderPath('Desktop'))
)

# Deliberately Continue, not Stop: this wrapper must survive a broken machine
# and still produce a bundle. Every section guards its own failures.
$ErrorActionPreference = 'Continue'

# ---- Resolve the artifact ------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Artifact)) {
    $candidates = @(
        'C:\NMMTools.ps1',
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'NMMTools.ps1')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { $Artifact = $c; break }
    }
}
if ([string]::IsNullOrWhiteSpace($Artifact) -or -not (Test-Path -LiteralPath $Artifact -PathType Leaf)) {
    Write-Host 'ERROR: Could not find NMMTools.ps1. Pass -Artifact <path>.' -ForegroundColor Red
    exit 2
}
$Artifact = (Resolve-Path -LiteralPath $Artifact).Path

# ---- Capture folder ------------------------------------------------------
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$captureId = 'NMM-capture-{0}-{1}' -f $env:COMPUTERNAME, $stamp
$outDir    = Join-Path $OutRoot $captureId
$logDir    = Join-Path $outDir 'log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-CaptureFile {
    param([string]$Name, [string[]]$Lines)
    $path = Join-Path $outDir $Name
    $text = ($Lines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host ''
Write-Host ('NMM capture run  ->  {0}' -f $outDir) -ForegroundColor Cyan
Write-Host ''

# ---- Identity helpers ----------------------------------------------------
function Get-SidForAccount {
    param([string]$Account)
    if ([string]::IsNullOrWhiteSpace($Account)) { return $null }
    try {
        $nt = New-Object System.Security.Principal.NTAccount($Account)
        return $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        return $null
    }
}

$procIdentity = $null
$procSid      = $null
$isElevated   = $false
try {
    $procIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $procSid      = $procIdentity.User.Value
    $principal    = New-Object Security.Principal.WindowsPrincipal($procIdentity)
    $isElevated   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

$loggedOnUser = $null
try {
    $loggedOnUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
} catch { }
if ([string]::IsNullOrWhiteSpace($loggedOnUser)) {
    try { $loggedOnUser = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName } catch { }
}
$loggedOnSid = Get-SidForAccount -Account $loggedOnUser

$hiveMismatch = $false
if ($procSid -and $loggedOnSid -and ($procSid -ne $loggedOnSid)) { $hiveMismatch = $true }

# ---- context.txt ---------------------------------------------------------
$ctx = New-Object System.Collections.Generic.List[string]
$ctx.Add(('NMM capture run  {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$ctx.Add('=' * 70)
$ctx.Add('')
$ctx.Add('--- host / engine ---')
$ctx.Add(('  computer         : {0}' -f $env:COMPUTERNAME))
$ctx.Add(('  PSVersion        : {0}' -f $PSVersionTable.PSVersion))
$ctx.Add(('  PSEdition        : {0}' -f $PSVersionTable.PSEdition))
$ctx.Add(('  host             : {0}' -f $Host.Name))
$ctx.Add(('  apartment state  : {0}' -f [System.Threading.Thread]::CurrentThread.GetApartmentState()))
$ctx.Add(('  64-bit process   : {0}' -f [Environment]::Is64BitProcess))
$ctx.Add(('  language mode    : {0}' -f $ExecutionContext.SessionState.LanguageMode))
$ctx.Add(('  execution policy : {0}' -f (Get-ExecutionPolicy)))
$ctx.Add(('  UserInteractive  : {0}' -f [Environment]::UserInteractive))
$ctx.Add('')
$ctx.Add('--- identity (the hive question) ---')
$ctx.Add(('  process runs as  : {0}' -f $(if ($procIdentity) { $procIdentity.Name } else { 'unknown' })))
$ctx.Add(('  process SID      : {0}' -f $(if ($procSid) { $procSid } else { 'unknown' })))
$ctx.Add(('  elevated         : {0}' -f $isElevated))
$ctx.Add(('  logged-on user   : {0}' -f $(if ($loggedOnUser) { $loggedOnUser } else { 'none / unknown' })))
$ctx.Add(('  logged-on SID    : {0}' -f $(if ($loggedOnSid) { $loggedOnSid } else { 'unresolved' })))
$ctx.Add(('  HKCU points at   : {0}' -f $(if ($procSid) { $procSid } else { 'unknown' })))
$ctx.Add(('  USERPROFILE      : {0}' -f $env:USERPROFILE))
$ctx.Add(('  APPDATA          : {0}' -f $env:APPDATA))
if ($hiveMismatch) {
    $ctx.Add('')
    $ctx.Add('  *** HIVE MISMATCH ***')
    $ctx.Add('  The elevated process and the logged-on user are DIFFERENT accounts.')
    $ctx.Add('  Every HKCU: write and every $env:APPDATA path in a tool targets the')
    $ctx.Add('  elevated account, NOT the user being helped. Compare the two')
    $ctx.Add('  hive-compare files to see the consequence.')
} else {
    $ctx.Add('')
    $ctx.Add('  Process and logged-on user are the same account (or could not be compared).')
}
$ctx.Add('')
$ctx.Add('--- artifact ---')
$ctx.Add(('  path             : {0}' -f $Artifact))
try {
    $fi = Get-Item -LiteralPath $Artifact
    $ctx.Add(('  size             : {0:N0} bytes' -f $fi.Length))
    $ctx.Add(('  modified         : {0}' -f $fi.LastWriteTime))
} catch { }
try {
    $bytes = [System.IO.File]::ReadAllBytes($Artifact)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $ctx.Add(('  UTF-8 BOM        : {0}' -f $hasBom))
    $sha = (Get-FileHash -LiteralPath $Artifact -Algorithm SHA256).Hash
    $ctx.Add(('  SHA256           : {0}' -f $sha))
} catch { }
try {
    $head = Get-Content -LiteralPath $Artifact -TotalCount 3 -ErrorAction Stop
    foreach ($h in $head) { $ctx.Add(('  header           : {0}' -f $h.TrimStart([char]0xFEFF))) }
} catch { }
$ctx.Add('')
$ctx.Add('--- launch ---')
$ctx.Add(('  mode             : {0}' -f $Mode))
$ctx.Add(('  tool             : {0}' -f $(if ($Tool) { $Tool } else { '(menu)' })))
$ctx.Add(('  silent           : {0}' -f [bool]$Silent))
$ctx.Add(('  forced log dir   : {0}' -f $logDir))
Write-CaptureFile -Name 'context.txt' -Lines $ctx

Write-Host ('  process : {0}' -f $(if ($procIdentity) { $procIdentity.Name } else { 'unknown' }))
Write-Host ('  user    : {0}' -f $(if ($loggedOnUser) { $loggedOnUser } else { 'unknown' }))
if ($hiveMismatch) {
    Write-Host '  HIVE MISMATCH - elevated account differs from logged-on user' -ForegroundColor Yellow
}
Write-Host ''

# ---- Camera / mic consent state in BOTH hives ---------------------------
function Get-ConsentSnapshot {
    param([string]$Label)

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add(('camera / mic consent snapshot  ({0})' -f $Label))
    $out.Add(('captured {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $out.Add('=' * 70)

    $hives = @()
    if ($procSid) {
        $elevLabel = 'not elevated'
        if ($isElevated) { $elevLabel = 'elevated' }
        $hives += [PSCustomObject]@{
            Who = ('TOOLKIT PROCESS ({0}, {1}) - this is what HKCU: resolves to' -f $procIdentity.Name, $elevLabel)
            Sid = $procSid
        }
    }
    if ($loggedOnSid -and ($loggedOnSid -ne $procSid)) {
        $hives += [PSCustomObject]@{ Who = ('LOGGED-ON USER ({0})' -f $loggedOnUser); Sid = $loggedOnSid }
    }

    foreach ($h in $hives) {
        $out.Add('')
        $out.Add(('--- {0} ---' -f $h.Who))
        $out.Add(('  SID: {0}' -f $h.Sid))
        foreach ($cap in @('webcam','microphone')) {
            $base = 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\{1}' -f $h.Sid, $cap
            if (-not (Test-Path -LiteralPath $base)) {
                $out.Add(('  {0,-12}: KEY MISSING (hive not loaded, or consent store never created)' -f $cap))
                continue
            }
            $val = (Get-ItemProperty -LiteralPath $base -Name 'Value' -ErrorAction SilentlyContinue).Value
            $out.Add(('  {0,-12}: {1}' -f $cap, $(if ($val) { $val } else { '(unset)' })))

            $np = Join-Path $base 'NonPackaged'
            if (Test-Path -LiteralPath $np) {
                $npVal = (Get-ItemProperty -LiteralPath $np -Name 'Value' -ErrorAction SilentlyContinue).Value
                $out.Add(('  {0,-12}: NonPackaged = {1}' -f '', $(if ($npVal) { $npVal } else { '(unset)' })))
                Get-ChildItem -LiteralPath $np -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -match 'teams' } |
                    ForEach-Object {
                        $tv = (Get-ItemProperty -LiteralPath $_.PSPath -Name 'Value' -ErrorAction SilentlyContinue).Value
                        $out.Add(('  {0,-12}:   {1} = {2}' -f '', $_.PSChildName, $tv))
                    }
            } else {
                $out.Add(('  {0,-12}: NonPackaged subkey missing' -f ''))
            }
        }
    }

    $out.Add('')
    $out.Add('--- machine-wide policy (HKLM, hive-independent) ---')
    $polKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
    if (Test-Path -LiteralPath $polKey) {
        foreach ($n in @('LetAppsAccessCamera','LetAppsAccessMicrophone')) {
            $pv = (Get-ItemProperty -LiteralPath $polKey -Name $n -ErrorAction SilentlyContinue).$n
            $meaning = 'not set'
            if ($pv -eq 0) { $meaning = '0 = user in control' }
            if ($pv -eq 1) { $meaning = '1 = force allow' }
            if ($pv -eq 2) { $meaning = '2 = FORCE DENY (blocks everything below)' }
            $out.Add(('  {0,-24}: {1}' -f $n, $meaning))
        }
    } else {
        $out.Add('  no AppPrivacy policy key (no GPO/MDM block)')
    }

    $out.Add('')
    $out.Add('--- camera devices ---')
    $cams = @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue)
    if ($cams.Count -eq 0) { $cams = @(Get-PnpDevice -FriendlyName '*camera*' -ErrorAction SilentlyContinue) }
    if ($cams.Count -eq 0) {
        $out.Add('  none found via PnP')
    } else {
        foreach ($c in $cams) {
            $out.Add(('  [{0,-8}] {1}' -f $c.Status, $c.FriendlyName))
            $out.Add(('             {0}' -f $c.InstanceId))
        }
    }

    $out.Add('')
    $out.Add('--- FrameServer service ---')
    $fs = Get-Service -Name 'FrameServer' -ErrorAction SilentlyContinue
    if ($fs) {
        $out.Add(('  status: {0}   startup: {1}' -f $fs.Status, $fs.StartType))
    } else {
        $out.Add('  FrameServer service not present')
    }

    return $out
}

Write-Host '  capturing consent state (before)...'
Write-CaptureFile -Name 'hive-compare-before.txt' -Lines (Get-ConsentSnapshot -Label 'BEFORE the toolkit run')

# ---- Transcript ----------------------------------------------------------
$transcriptPath = Join-Path $outDir 'transcript.txt'
$transcriptOn   = $false
try {
    Start-Transcript -Path $transcriptPath -Force -ErrorAction Stop | Out-Null
    $transcriptOn = $true
} catch {
    Write-Host ('  WARNING: could not start transcript - {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}

# ---- Run the toolkit -----------------------------------------------------
$runError    = $null
$runExitCode = $null
$Error.Clear()

if ($NoRun) {
    Write-Host '  -NoRun specified; skipping the toolkit launch.' -ForegroundColor Yellow
} else {
    Write-Host ''
    Write-Host ('  launching {0}' -f $Artifact) -ForegroundColor Cyan
    Write-Host '  ---------------- toolkit output begins ----------------'
    Write-Host ''

    $argTable = @{ LogPath = $logDir }
    if ($Tool) {
        $argTable['Tool'] = $Tool
        if ($Silent) { $argTable['Silent'] = $true }
    } else {
        $argTable['Mode'] = $Mode
    }

    try {
        # Call operator, NOT Start-Process: the artifact must inherit this
        # window's elevation, host, apartment state, and language mode. An
        # 'exit' inside the artifact ends the artifact, not this wrapper.
        & $Artifact @argTable
        $runExitCode = $LASTEXITCODE
    } catch {
        $runError = $_
        Write-Host ''
        Write-Host ('  TOOLKIT THREW: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }

    Write-Host ''
    Write-Host '  ----------------- toolkit output ends -----------------'
}

# ---- Errors --------------------------------------------------------------
$err = New-Object System.Collections.Generic.List[string]
$err.Add(('error records raised during the run  ({0})' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$err.Add('=' * 70)
$err.Add(('  toolkit $LASTEXITCODE : {0}' -f $(if ($null -ne $runExitCode) { $runExitCode } else { '(none)' })))
$err.Add('')
if ($runError) {
    $err.Add('--- terminating exception from the artifact ---')
    $err.Add(($runError | Format-List * -Force | Out-String))
    $err.Add('--- exception detail ---')
    $err.Add(($runError.Exception | Format-List * -Force | Out-String))
    $err.Add('')
}
$err.Add(('--- $Error stack ({0} record(s), newest first) ---' -f $Error.Count))
if ($Error.Count -eq 0) {
    $err.Add('  (empty - no non-terminating errors surfaced in THIS runspace)')
    $err.Add('  Note: GUI mode runs each tool in a separate runspace. Tool-side')
    $err.Add('  errors land in log\NMMTools-*.log, not here.')
} else {
    $i = 0
    foreach ($e in $Error) {
        $i++
        $err.Add(('===== [{0}] =====' -f $i))
        $err.Add(($e | Format-List * -Force | Out-String))
        if ($e.InvocationInfo) {
            $err.Add(('  at: {0}' -f $e.InvocationInfo.PositionMessage))
        }
    }
}
Write-CaptureFile -Name 'errors.txt' -Lines $err

# ---- Consent state after -------------------------------------------------
Write-Host ''
Write-Host '  capturing consent state (after)...'
Write-CaptureFile -Name 'hive-compare-after.txt' -Lines (Get-ConsentSnapshot -Label 'AFTER the toolkit run')

# ---- Environment probe ---------------------------------------------------
$probe = Join-Path $PSScriptRoot 'Get-NmmEnvironmentProbe.ps1'
if (Test-Path -LiteralPath $probe) {
    Write-Host '  running environment probe...'
    try {
        & $probe -Artifact $Artifact -OutFile (Join-Path $outDir 'env-probe.txt') | Out-Null
    } catch {
        Write-CaptureFile -Name 'env-probe.txt' -Lines @(('probe failed: {0}' -f $_.Exception.Message))
    }
} else {
    Write-CaptureFile -Name 'env-probe.txt' -Lines @(('Get-NmmEnvironmentProbe.ps1 not found next to this script ({0}).' -f $PSScriptRoot))
}

# ---- Toolkit state files -------------------------------------------------
$stateDir = Join-Path $env:ProgramData 'NMMTools'
if (Test-Path -LiteralPath $stateDir) {
    $stateCopy = Join-Path $outDir 'programdata-NMMTools'
    New-Item -ItemType Directory -Force -Path $stateCopy | Out-Null
    Get-ChildItem -LiteralPath $stateDir -File -ErrorAction SilentlyContinue |
        Copy-Item -Destination $stateCopy -ErrorAction SilentlyContinue
}

if ($transcriptOn) {
    try { Stop-Transcript | Out-Null } catch { }
}

# ---- Zip -----------------------------------------------------------------
$zipPath = Join-Path $OutRoot ($captureId + '.zip')
$zipOk   = $false
try {
    Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zipPath -Force -ErrorAction Stop
    $zipOk = $true
} catch {
    Write-Host ('  WARNING: could not zip the capture - {0}' -f $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ''
Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host ' CAPTURE COMPLETE' -ForegroundColor Cyan
Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host ('  folder : {0}' -f $outDir)
if ($zipOk) { Write-Host ('  zip    : {0}' -f $zipPath) }
$logFiles = @(Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue)
Write-Host ('  toolkit log files captured : {0}' -f $logFiles.Count)
if ($logFiles.Count -eq 0) {
    Write-Host '  NOTE: no toolkit log was written. That itself is a finding -' -ForegroundColor Yellow
    Write-Host '        it means the run never reached Set-OutputSink.' -ForegroundColor Yellow
}
if ($hiveMismatch) {
    Write-Host ''
    Write-Host '  HIVE MISMATCH was detected - compare hive-compare-before.txt' -ForegroundColor Yellow
    Write-Host '  against hive-compare-after.txt to see which account the fix hit.' -ForegroundColor Yellow
}
Write-Host ''
