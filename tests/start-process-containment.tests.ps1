# Ratchet: no NEW Start-Process may rely on the tool's outer try for containment.
#
# Start-Process raises a TERMINATING error when it cannot resolve its target as
# an application, and -ErrorAction only suppresses NON-terminating ones. A call
# contained only by the tool's outermost try therefore skips every
# Complete-ToolRun -Status Success/Warning below it and lands in the outer catch
# as Failed - converting a completed repair into a reported failure. That is
# exactly what Repair-TeamsDeep did on MATTHEWGR_L3, 2026-08-25: credentials
# cleared, cache cleared, AppX re-registered, TokenBroker restarted, then a
# cosmetic 'relaunch Teams' threw and the tool said Failed.
#
# 39 pre-existing sites in 23 tools have the same shape. They are recorded below
# rather than swept silently, because not all are wrong - where launching IS the
# repair, failing the tool is correct. Triage is separate work.
#
# The allowlist is a RATCHET, counted per file so it survives line drift:
#   - a file not listed here, or a count above its entry -> new debt, fails
#   - a count BELOW its entry -> something was fixed; decrement it here
# Never raise a number to make this pass. Fix the call instead: wrap it in its
# own try with -ErrorAction Stop, and decide deliberately whether failure should
# change the tool's status.

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent

    # file name -> number of Start-Process calls contained only by the outer try
    $script:Allowed = @{
        'Clear-SavedCredentials.ps1' = 1
        'Clear-TeamsCache.ps1' = 1
        'Get-BluetoothDevices.ps1' = 1
        'Get-DockingDisplays.ps1' = 1
        'Invoke-AvPrepQuickFix.ps1' = 1
        'Invoke-DockingQuickFix.ps1' = 2
        'Invoke-OEMDriverUpdate.ps1' = 3
        'Invoke-OfficeQuickFix.ps1' = 1
        'Invoke-OneDriveQuickFix.ps1' = 2
        'Invoke-TeamsQuickFix.ps1' = 2
        'Optimize-Performance.ps1' = 1
        'Remove-AdobeCC.ps1' = 1
        'Remove-WindowsOld.ps1' = 1
        'Repair-AudioAdvanced.ps1' = 1
        'Repair-Office365.ps1' = 3
        'Repair-OneDriveClient.ps1' = 3
        'Repair-StartMenuTaskbar.ps1' = 3
        'Repair-TeamsAddin.ps1' = 2
        'Repair-TeamsCamera.ps1' = 1
        'Reset-WindowsExplorer.ps1' = 3
        'Reset-WindowsSearch.ps1' = 1
        'Set-DefaultApps.ps1' = 1
        'Test-WebcamAudio.ps1' = 3
    }

    function Get-OuterTryOnlyCounts {
        param([Parameter(Mandatory)][string]$Root)
        $counts = @{}
        foreach ($f in (Get-ChildItem $Root -Recurse -Filter *.ps1)) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $tries = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] }, $true))
            foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $e = $c.CommandElements[0]
                if (-not ($e -is [System.Management.Automation.Language.StringConstantExpressionAst])) { continue }
                if ($e.Value -ne 'Start-Process') { continue }
                $encl = @($tries | Where-Object {
                    $c.Extent.StartOffset -ge $_.Body.Extent.StartOffset -and
                    $c.Extent.EndOffset   -le $_.Body.Extent.EndOffset })
                if ($encl.Count -le 1) {
                    if (-not $counts.ContainsKey($f.Name)) { $counts[$f.Name] = 0 }
                    $counts[$f.Name]++
                }
            }
        }
        return $counts
    }
}

Describe 'Start-Process containment ratchet' {

    It 'introduces no new outer-try-only Start-Process call' {
        $actual = Get-OuterTryOnlyCounts -Root (Join-Path $script:RepoRoot 'src\tools')
        $new = @()
        foreach ($file in ($actual.Keys | Sort-Object)) {
            $budget = 0
            if ($script:Allowed.ContainsKey($file)) { $budget = $script:Allowed[$file] }
            if ($actual[$file] -gt $budget) {
                $new += ('{0}: {1} found, {2} allowed' -f $file, $actual[$file], $budget)
            }
        }
        $new -join ' | ' | Should -BeNullOrEmpty
    }

    It 'has an allowlist with no stale entries' {
        $actual = Get-OuterTryOnlyCounts -Root (Join-Path $script:RepoRoot 'src\tools')
        $stale = @()
        foreach ($file in ($script:Allowed.Keys | Sort-Object)) {
            $found = 0
            if ($actual.ContainsKey($file)) { $found = $actual[$file] }
            if ($found -lt $script:Allowed[$file]) {
                $stale += ('{0}: {1} left, allowlist still says {2} - decrement it' -f $file, $found, $script:Allowed[$file])
            }
        }
        $stale -join ' | ' | Should -BeNullOrEmpty
    }
}
