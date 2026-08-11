<#
.SYNOPSIS
    Captures why NMM Toolkit tools report "cmdlet not found" on a given machine.

.DESCRIPTION
    Run this ON THE MACHINE WHERE TOOLS ARE FAILING, in the SAME window the
    technician uses to launch NMMTools.ps1. It records the host, language
    mode, module availability, and the resolution status of every command the
    toolkit depends on, then writes a report to the Desktop.

    Read-only. Makes no changes.

.PARAMETER Artifact
    Path to the built NMMTools.ps1 being used. Defaults to the Desktop copy.

.NOTES
    Write-Host is used intentionally for interactive console output.
    This is an operator-run diagnostic, not a PDQ Deploy step.
#>
[CmdletBinding()]
param(
    [string]$Artifact = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'NMMTools.ps1'),
    [string]$OutFile  = (Join-Path ([Environment]::GetFolderPath('Desktop')) ('nmm-env-probe-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

$ErrorActionPreference = 'Continue'
$lines = New-Object System.Collections.Generic.List[string]
function Add-Line { param([string]$Text) $lines.Add($Text); Write-Host $Text }

Add-Line ('NMM environment probe  {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Line ('=' * 70)

# --- 1. Host and engine -------------------------------------------------
Add-Line ''
Add-Line '--- host / engine ---'
Add-Line ('  computer        : {0}' -f $env:COMPUTERNAME)
Add-Line ('  user            : {0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
Add-Line ('  PSVersion       : {0}' -f $PSVersionTable.PSVersion)
Add-Line ('  PSEdition       : {0}' -f $PSVersionTable.PSEdition)
Add-Line ('  host            : {0}' -f $Host.Name)
Add-Line ('  process         : {0}' -f ([System.Diagnostics.Process]::GetCurrentProcess().ProcessName))
Add-Line ('  64-bit process  : {0}' -f [Environment]::Is64BitProcess)
Add-Line ('  language mode   : {0}' -f $ExecutionContext.SessionState.LanguageMode)
Add-Line ('  execution policy: {0}' -f (Get-ExecutionPolicy))
Add-Line ('  elevated        : {0}' -f ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

# ConstrainedLanguage breaks .NET calls the toolkit relies on.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Add-Line ''
    Add-Line ('  *** LANGUAGE MODE IS {0} - this alone breaks many tools ***' -f $ExecutionContext.SessionState.LanguageMode)
    Add-Line '      Usually caused by AppLocker or WDAC script policy.'
}

# --- 2. Module availability ---------------------------------------------
Add-Line ''
Add-Line '--- modules the toolkit depends on ---'
$modules = @('BitLocker','BitsTransfer','ConfigDefender','Defender','Dism','PnpDevice',
             'VpnClient','NetAdapter','NetTCPIP','NetSecurity','ScheduledTasks','Storage',
             'PKI','PrintManagement','Appx','CimCmdlets','Microsoft.PowerShell.LocalAccounts')
foreach ($m in $modules) {
    $available = [bool](Get-Module -ListAvailable -Name $m -ErrorAction SilentlyContinue)
    Add-Line ('  {0,-38} {1}' -f $m, $(if ($available) { 'present' } else { '*** MISSING ***' }))
}

# --- 3. Command resolution ----------------------------------------------
# Derived from the artifact itself rather than a curated list, so nothing the
# toolkit actually calls can be missed.
Add-Line ''
Add-Line '--- command resolution (every command the artifact invokes) ---'
$missingCmdlets = @()
$missingExes    = @()
$probed         = 0

if (Test-Path $Artifact) {
    $tk = $null; $pe = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Artifact, [ref]$tk, [ref]$pe)

    # Names the artifact defines itself are not external dependencies.
    $selfDefined = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        [void]$selfDefined.Add($fn.Name)
    }

    $names = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $n = $c.GetCommandName()
        if (-not $n -or $n -match '^\$' -or $selfDefined.Contains($n)) { continue }
        [void]$names.Add($n)
    }

    # A language keyword showing up as a command is a CODE defect in the
    # artifact - `(if ...)` used as an expression - not a missing dependency.
    $keywords = @('if','else','elseif','switch','foreach','for','while','do','try',
                  'catch','finally','return','throw','param','begin','process','end')
    $keywordBugs = @()

    foreach ($n in ($names | Sort-Object)) {
        $probed++
        $found = Get-Command $n -ErrorAction SilentlyContinue
        if (-not $found) {
            if ($keywords -contains $n.ToLower()) {
                $keywordBugs += $n
                Add-Line ('  {0,-34} *** CODE BUG: keyword used as a command ***' -f $n)
            }
            elseif ($n -match '\.exe$' -or $n -cmatch '^[a-z0-9]+$') { $missingExes += $n; Add-Line ('  {0,-34} *** NOT FOUND ***' -f $n) }
            else { $missingCmdlets += $n; Add-Line ('  {0,-34} *** NOT FOUND ***' -f $n) }
        } else {
            Add-Line ('  {0,-34} ok  ({1})' -f $n, $found.CommandType)
        }
    }
    Add-Line ('  -- probed {0} distinct commands from the artifact --' -f $probed)
    if ($keywordBugs.Count -gt 0) {
        Add-Line ''
        Add-Line ('  *** {0} KEYWORD-AS-COMMAND DEFECT(S) IN THIS BUILD: {1}' -f $keywordBugs.Count, ($keywordBugs -join ', '))
        Add-Line '      These throw "The term ''if'' is not recognized as the name of a cmdlet"'
        Add-Line '      at runtime. Fixed by rebuilding from current source.'
    }
} else {
    Add-Line '  SKIPPED - artifact not found, cannot derive the command list'
}

# --- 4. The artifact itself ---------------------------------------------
Add-Line ''
Add-Line '--- artifact ---'
if (Test-Path $Artifact) {
    $item = Get-Item $Artifact
    Add-Line ('  path     : {0}' -f $item.FullName)
    Add-Line ('  size     : {0:N0} bytes' -f $item.Length)
    Add-Line ('  modified : {0}' -f $item.LastWriteTime)
    $header = (Get-Content $Artifact -TotalCount 3) -join ' | '
    Add-Line ('  header   : {0}' -f $header)
} else {
    Add-Line ('  *** artifact not found at {0} ***' -f $Artifact)
}

# --- 5. Verdict ----------------------------------------------------------
Add-Line ''
Add-Line '=== SUMMARY ==='
if ($missingCmdlets.Count -gt 0) {
    Add-Line ('  MISSING CMDLETS ({0}): {1}' -f $missingCmdlets.Count, ($missingCmdlets -join ', '))
} else {
    Add-Line '  all probed cmdlets resolve'
}
if ($missingExes.Count -gt 0) {
    Add-Line ('  MISSING EXECUTABLES ({0}): {1}' -f $missingExes.Count, ($missingExes -join ', '))
} else {
    Add-Line '  all probed executables resolve'
}
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Add-Line ('  LANGUAGE MODE: {0} - primary suspect' -f $ExecutionContext.SessionState.LanguageMode)
}

[System.IO.File]::WriteAllText($OutFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ('Report written to: {0}' -f $OutFile) -ForegroundColor Green
