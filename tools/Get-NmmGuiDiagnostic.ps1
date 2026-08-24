#requires -Version 5.1
<#
.SYNOPSIS
    Diagnose GUI-mode CommandNotFoundException failures in NMMTools (for example
    Add-GuiOutputRecord / Show-GuiPrompt not recognized inside the drain timer).

.DESCRIPTION
    Read-only. Does NOT launch the toolkit and changes nothing. Answers four
    questions, in the order they would explain the failure:

      1. WHICH BUILD is on this machine (size, SHA256, header banner)? A hash
         mismatch against the ship report means the rest is moot.
      2. WHAT HOST is running it - apartment state above all. Start-GuiMenu
         takes a different code path when the host is MTA, and on that path the
         GUI thread has no runspace, so toolkit functions cannot resolve.
      3. IS THE FILE INTACT - parse it and confirm the GUI functions are really
         defined, and that the reported failing lines are the calls we expect.
         Catches truncation and partial copies.
      4. DOES THE STRUCTURE ACTUALLY FAIL HERE - rebuild the artifact's own
         pattern (script-scope function called from a DispatcherTimer tick
         bound with .GetNewClosure()) using THIS machine's PowerShell, and see
         whether it resolves. This is the part that cannot be answered remotely.

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
    Add-Line '  *** THIS IS AN MTA HOST. Start-GuiMenu will hand the UI to a raw'
    Add-Line '  *** [Threading.Thread] whose scriptblock has NO runspace, so toolkit'
    Add-Line '  *** functions cannot resolve on it. Re-run the toolkit from a host'
    Add-Line '  *** started with -STA and see whether the errors disappear.'
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
    Add-Line ('  size            : {0:N0} bytes   (v9.3.0 acfd64d = 819,310)' -f $bytes.Length)
    Add-Line ('  SHA256          : {0}' -f (Get-FileHash -LiteralPath $Artifact -Algorithm SHA256).Hash)
    Add-Line  '  expected        : 709DA2076ADCBA62CACD8330D7F2E6001B66BDD8CE2E8F41431ECD6648C6A349'
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
    foreach ($n in @(2681, 2697)) {
        if ($src.Count -ge $n) { Add-Line ('  line {0,-6}     : {1}' -f $n, $src[$n - 1].Trim()) }
        else { Add-Line ('  line {0,-6}     : (file has only {1} lines)' -f $n, $src.Count) }
    }
}

# ---- 4. does the pattern actually fail on THIS machine? ------------------
Add-Line ''
Add-Line '--- live structural test (this machine, this PowerShell) ---'
Add-Line '  Rebuilds the artifact pattern: a script-scope function called from a'
Add-Line '  DispatcherTimer tick bound with .GetNewClosure().'
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

    if ($apartment -ne 'STA') {
        Add-Line '  SKIPPED - host is MTA, so a Dispatcher cannot run on this thread.'
        Add-Line '  That by itself is consistent with the reported failure.'
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
Add-Line 'Send this file back. The lines that matter most: APARTMENT STATE,'
Add-Line 'SHA256 vs expected, any MISSING function, and the live test RESULT.'

[System.IO.File]::WriteAllText($report, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ('Report written to: {0}' -f $report) -ForegroundColor Green
