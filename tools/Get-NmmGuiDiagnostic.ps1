#requires -Version 5.1
<#
.SYNOPSIS
    Diagnose GUI-mode CommandNotFoundException failures in NMMTools (for example
    Add-GuiOutputRecord / Show-GuiPrompt not recognized inside the drain timer).

.DESCRIPTION
    Read-only. Does NOT launch the toolkit and changes nothing. Answers four
    questions, in the order they would explain the failure:

      1. WHICH BUILD is on this machine (size, commit, header banner)? A commit
         mismatch against the ship report means the rest is moot. The SHA256 is
         reported but not asserted - it changes on every build.
      2. WHAT HOST is running it - apartment state above all. Start-GuiMenu
         takes a different code path when the host is MTA, and on that path the
         GUI thread has no runspace, so toolkit functions cannot resolve.
      3. IS THE FILE INTACT - parse it and confirm the GUI functions are really
         defined, and that the reported failing lines are the calls we expect.
         Catches truncation and partial copies.
      4. IS THIS WINDOW THE KIND THAT BREAKS by-name resolution - rebuild the
         pre-9.3.3 pattern (script-scope function called from a DispatcherTimer
         tick bound with .GetNewClosure()) and see whether it resolves here.

    On (4), read the result carefully. It measures THIS SCRIPT's own scope, not
    the toolkit's, and it deliberately keeps the old by-name shape so it stays a
    detector. A FAILED result on a 9.3.3 machine is EXPECTED and correct - it
    means the window reproduces the conditions that used to kill the GUI, not
    that the GUI is still broken. The line that answers "does this machine have
    the fix" is the version, and the handler-call shapes under file integrity.

.PARAMETER Artifact
    Path to NMMTools.ps1. Defaults to the Desktop copy, then C:\NMMTools.ps1,
    then a copy sitting beside this script.

.PARAMETER OutDir
    Where to write the report. Defaults to this script's own folder, so running
    it from the USB drops the report back onto the USB.

.NOTES
    Write-Host is used intentionally for coloured interactive console output.
    This is an operator-run diagnostic, not a PDQ Deploy step - the same
    exception Invoke-NmmCaptureRun.ps1 and Get-NmmEnvironmentProbe.ps1 rely on.

    Run it in the SAME window where the failure appears. If the toolkit
    self-elevated into a second window, run it in THAT window - the apartment
    state and host of the failing process are the whole point.
#>
[CmdletBinding()]
param(
    [string]$Artifact,
    [string]$OutDir
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = $(if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path })
}
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $OutDir ('nmm-gui-diag-{0}-{1}.txt' -f $env:COMPUTERNAME, $stamp)

$lines = New-Object System.Collections.Generic.List[string]
function Add-Line { param([string]$Text = '') $lines.Add($Text) | Out-Null; Write-Host $Text }

Add-Line ('NMM GUI diagnostic  {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Line ('=' * 70)

# ---- 2. host (first, because apartment state drives everything) ----------
Add-Line ''
Add-Line '--- host ---'
$apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
Add-Line ('  computer        : {0}' -f $env:COMPUTERNAME)
Add-Line ('  user            : {0}' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)
try {
    $pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    Add-Line ('  elevated        : {0}' -f $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
} catch { Add-Line '  elevated        : (could not determine)' }
Add-Line ('  APARTMENT STATE : {0}   <-- MTA takes the broken Start-GuiMenu branch' -f $apartment)
Add-Line ('  PSVersion       : {0}' -f $PSVersionTable.PSVersion)
Add-Line ('  PSEdition       : {0}' -f $PSVersionTable.PSEdition)
Add-Line ('  host name       : {0}' -f $Host.Name)
Add-Line ('  process         : {0}' -f (Get-Process -Id $PID).ProcessName)
Add-Line ('  64-bit process  : {0}' -f [Environment]::Is64BitProcess)
Add-Line ('  language mode   : {0}' -f $ExecutionContext.SessionState.LanguageMode)
if ($apartment -ne 'STA') {
    Add-Line ''
    Add-Line '  *** THIS IS AN MTA HOST. Builds BEFORE 9.3.1 handed the UI to a raw'
    Add-Line '  *** [Threading.Thread] whose scriptblock had NO runspace, so toolkit'
    Add-Line '  *** functions could not resolve on it and the GUI died silently.'
    Add-Line '  *** 9.3.1 relaunches into an STA host instead. If this machine is on'
    Add-Line '  *** an older build, that alone explains the failure - update first.'
}

# ---- 1. which build ------------------------------------------------------
Add-Line ''
Add-Line '--- artifact ---'
if ([string]::IsNullOrWhiteSpace($Artifact)) {
    $candidates = @(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'NMMTools.ps1'),
        'C:\NMMTools.ps1',
        $(if ($PSScriptRoot) { Join-Path $PSScriptRoot 'NMMTools.ps1' } else { $null })
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { $Artifact = $c; break }
    }
}
$astOk = $false
if ([string]::IsNullOrWhiteSpace($Artifact) -or -not (Test-Path -LiteralPath $Artifact -PathType Leaf)) {
    Add-Line '  NMMTools.ps1 NOT FOUND. Pass -Artifact <path>.'
} else {
    $Artifact = (Resolve-Path -LiteralPath $Artifact).Path
    $bytes = [System.IO.File]::ReadAllBytes($Artifact)
    Add-Line ('  path            : {0}' -f $Artifact)
    Add-Line ('  size            : {0:N0} bytes' -f $bytes.Length)
    # Report the hash, do not assert it. build.ps1 stamps a minute-resolution
    # timestamp into the header, so the SHA256 changes on EVERY build and
    # identifies one specific build, never a version. The commit string below is
    # the stable thing to compare.
    Add-Line ('  SHA256          : {0}' -f (Get-FileHash -LiteralPath $Artifact -Algorithm SHA256).Hash)
    # Compare the VERSION, not the commit: pinning a commit means this file has
    # to be edited every time the toolkit is rebuilt, and the edit itself changes
    # the commit. The version is what actually answers "does this machine have
    # the fix?" and is stable across rebuilds. [System.Version] so 9.3.10 does
    # not compare as older than 9.3.9.
    $minVersion = [System.Version]'9.3.1'
    $haveVersion = $null
    $haveCommit  = ''
    $banner = (Get-Content -LiteralPath $Artifact -TotalCount 2)[1]
    if ($banner -match 'v(\d+\.\d+\.\d+)\s+\(([0-9a-f]{7,40})\)') {
        $haveVersion = [System.Version]$matches[1]
        $haveCommit  = $matches[2]
    }
    Add-Line ('  commit          : {0}' -f $haveCommit)
    if ($null -eq $haveVersion) {
        Add-Line '  version         : UNREADABLE - the banner is not in the expected format'
    } elseif ($haveVersion -lt $minVersion) {
        Add-Line ('  version         : {0}   *** OLDER THAN {1} - predates the MTA GUI fix' -f $haveVersion, $minVersion)
        Add-Line '                    On an MTA host this build alone explains the failure. Update first.'
    } else {
        Add-Line ('  version         : {0}   (>= {1}, includes the MTA GUI fix)' -f $haveVersion, $minVersion)
    }
    Add-Line ('  UTF-8 BOM       : {0}   (expected False)' -f ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    foreach ($h in (Get-Content -LiteralPath $Artifact -TotalCount 3)) { Add-Line ('  header          : {0}' -f $h) }

    # ---- 3. file intact: parse and locate the functions and call sites ----
    Add-Line ''
    Add-Line '--- file integrity (AST) ---'
    $perr = $null
    $ast  = [System.Management.Automation.Language.Parser]::ParseFile($Artifact, [ref]$null, [ref]$perr)
    Add-Line ('  parse errors    : {0}' -f @($perr).Count)
    foreach ($e in (@($perr) | Select-Object -First 3)) {
        Add-Line ('     {0} @line {1}' -f $e.Message, $e.Extent.StartLineNumber)
    }
    if ($ast) {
        $astOk = $true
        $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        Add-Line ('  functions found : {0}' -f $defs.Count)
        foreach ($want in @('Add-GuiOutputRecord','Show-GuiPrompt','Show-GuiTextPrompt','Start-GuiMenuSTA','Start-GuiMenu','New-NmmToolRunspace')) {
            $hit = @($defs | Where-Object { $_.Name -eq $want })
            if ($hit.Count -eq 0) {
                Add-Line ('     MISSING  : {0}   <-- file is truncated or partial' -f $want)
            } else {
                Add-Line ('     defined  : {0,-22} line {1}{2}' -f $want, $hit[0].Extent.StartLineNumber, $(if ($hit.Count -gt 1) { '  (DUPLICATE x' + $hit.Count + ')' } else { '' }))
            }
        }
    }
    $src = Get-Content -LiteralPath $Artifact
    Add-Line ('  total lines     : {0}' -f $src.Count)
    # Locate the handler calls by CONTENT, not by hardcoded line number - those
    # shift with every build and would make this report quietly wrong.
    #
    # Report WHICH SHAPE is present, never the absence of one. This block used to
    # grep only for the by-name calls, so 9.3.3 - where the fix replaced them with
    # captured references - reported 'NOT FOUND' on a perfectly correct file:
    # success printed in the vocabulary of failure, on the one line a reader
    # scans for trouble. A detector that has not been taught about the fix is
    # worse than no detector, because its output still looks authoritative.
    $handlerShapes = @(
        @{ Name = 'Add-GuiOutputRecord'; Old = 'Add-GuiOutputRecord -Sync'; New = '& $fnAddGuiOutputRecord -Sync' },
        @{ Name = 'Show-GuiPrompt';      Old = 'Show-GuiPrompt -Sync';      New = '& $fnShowGuiPrompt -Sync' },
        @{ Name = 'Show-GuiTextPrompt';  Old = 'Show-GuiTextPrompt -Sync';  New = '& $fnShowGuiTextPrompt -Sync' }
    )
    foreach ($shape in $handlerShapes) {
        $liveLines = { param($needle)
            @(Select-String -LiteralPath $Artifact -Pattern ([regex]::Escape($needle)) |
              Where-Object { $_.Line.TrimStart() -notmatch '^#' })
        }
        $newHits = @(& $liveLines $shape.New)
        $oldHits = @(& $liveLines $shape.Old)
        if ($newHits.Count -gt 0) {
            Add-Line ('  handler call    : {0,-20} FIXED (captured reference) line {1}' -f $shape.Name, $newHits[0].LineNumber)
        } elseif ($oldHits.Count -gt 0) {
            Add-Line ('  handler call    : {0,-20} *** BY-NAME, line {1}' -f $shape.Name, $oldHits[0].LineNumber)
            Add-Line '                    *** This build predates 9.3.3. The GUI will fail with'
            Add-Line '                    *** CommandNotFoundException when launched from an ALREADY'
            Add-Line '                    *** ELEVATED window. Deploy 9.3.3 or later.'
        } else {
            Add-Line ('  handler call    : {0,-20} neither shape present - unexpected build' -f $shape.Name)
        }
    }
}

# ---- 4. does the pattern actually fail on THIS machine? ------------------
Add-Line ''
Add-Line '--- live structural test (this machine, this PowerShell) ---'
Add-Line '  Rebuilds the PRE-9.3.3 pattern: a script-scope function called from a'
Add-Line '  DispatcherTimer tick bound with .GetNewClosure().'
Add-Line '  NOTE: this measures THIS script''s scope, not the toolkit''s. FAILED here'
Add-Line '  on a 9.3.3 machine is EXPECTED - it means this window reproduces the'
Add-Line '  conditions that used to kill the GUI. Judge the fix by the version and'
Add-Line '  the handler-call shapes above, not by this line.'
try {
    Add-Type -AssemblyName PresentationFramework, WindowsBase -ErrorAction Stop
    Add-Line '  WPF assemblies  : loaded'

    function Test-NmmDrainTarget { param($Sync, $Record) return 'RESOLVED' }

    $probe = [hashtable]::Synchronized(@{ Result = $null })
    $drainSync = $probe
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [System.TimeSpan]::FromMilliseconds(50)
    $timer.Add_Tick({
        $s = $drainSync
        try   { $s.Result = 'RESOLVED - the drain-timer pattern works on this host' }
        catch { $s.Result = 'FAILED: ' + $_.Exception.GetType().Name }
        try   { $s.Result = 'call returned: ' + (Test-NmmDrainTarget -Sync $s -Record 'x') }
        catch { $s.Result = 'FAILED: ' + $_.Exception.GetType().Name + ' :: ' + $_.Exception.Message.Split([char]10)[0] }
        $timer.Stop()
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()
    }.GetNewClosure())

    # A Dispatcher, once shut down, can never be restarted on that thread - and the
    # tick above shuts it down deliberately. So a SECOND run of this script in the
    # same PowerShell session could only ever throw, and used to surface as a raw
    # 'Cannot perform requested operation because the Dispatcher shut down', which
    # reads like a fault on the machine under test rather than on this script.
    # Say what actually happened and what to do about it.
    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    if ($apartment -ne 'STA') {
        Add-Line '  SKIPPED - host is MTA, so a Dispatcher cannot run on this thread.'
        Add-Line '  That by itself is consistent with the reported failure.'
    } elseif ($dispatcher.HasShutdownStarted -or $dispatcher.HasShutdownFinished) {
        Add-Line '  SKIPPED - this session has already run the live test once, and a'
        Add-Line '  Dispatcher cannot be restarted on a thread that has shut one down.'
        Add-Line '  Not a fault on this machine. Re-run in a fresh PowerShell window'
        Add-Line '  if you need this measurement.'
    } else {
        $timer.Start()
        [System.Windows.Threading.Dispatcher]::Run()
        Add-Line ('  RESULT          : {0}' -f $(if ($probe.Result) { $probe.Result } else { 'tick never fired' }))
    }
} catch {
    Add-Line ('  live test could not run: {0}' -f $_.Exception.Message)
}

Add-Line ''
Add-Line ('=' * 70)
Add-Line 'Send this file back. The lines that matter most, in order:'
Add-Line '  1. version        - is the fix even on this machine (9.3.3 or later)?'
Add-Line '  2. handler call   - FIXED, or BY-NAME meaning the build predates 9.3.3?'
Add-Line '  3. any MISSING function or parse error - truncated or partial copy?'
Add-Line '  4. APARTMENT STATE and elevated - which launch path was taken?'
Add-Line 'The live test RESULT is about THIS WINDOW, not the toolkit - see the note'
Add-Line 'above it before drawing any conclusion from it.'

[System.IO.File]::WriteAllText($report, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ('Report written to: {0}' -f $report) -ForegroundColor Green
