function Repair-OutlookSearch {
    [CmdletBinding()]
    param([switch]$Silent)

    # Close Outlook gracefully then force; returns $true if Outlook is no longer running.
    function Stop-OutlookGraceful {
        $proc = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue)
        if ($proc.Count -eq 0) { return $true }
        foreach ($p in $proc) { $p.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        if (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0) {
            Stop-Process -Name 'OUTLOOK' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        return (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -eq 0)
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-search-repair'
        $edb = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb"
        $catalogKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Search'
        $searchPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
        $searchSetupKey  = 'HKLM:\SOFTWARE\Microsoft\Windows Search'

        # --- Report ---
        $ws = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if ($ws) {
            $wsLevel = 'Info'
            if ("$($ws.StartType)" -notlike 'Automatic*') { $wsLevel = 'Warning' }
            Write-ToolOutput ('Windows Search (WSearch): {0} (StartType {1})' -f $ws.Status, $ws.StartType) -Level $wsLevel
        } else {
            Write-ToolOutput 'Windows Search service (WSearch) not found.' -Level Warning
        }
        if (Test-Path -LiteralPath $edb) {
            $sizeMB = [math]::Round((Get-Item -LiteralPath $edb -ErrorAction SilentlyContinue).Length / 1MB, 1)
            Write-ToolOutput ('Search index DB: {0} ({1} MB)' -f $edb, $sizeMB) -Level Detail
        } else {
            Write-ToolOutput 'Search index DB (Windows.edb) not found at the default path.' -Level Detail
        }
        $olRunning = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0
        Write-ToolOutput ('Outlook running: {0}' -f $olRunning) -Level Detail
        $catalogRegistered = $false
        if (Test-Path -LiteralPath $catalogKey) {
            $catalogRegistered = $null -ne (Get-ItemProperty -LiteralPath $catalogKey -Name 'Catalog' -ErrorAction SilentlyContinue)
        }
        Write-ToolOutput ('Outlook search catalog registered: {0}' -f $catalogRegistered) -Level Detail

        # Config diagnosis (the usual recurring-breakage causes).
        $preventOutlook = 0
        if (Test-Path -LiteralPath $searchPolicyKey) {
            $pv = (Get-ItemProperty -LiteralPath $searchPolicyKey -Name 'PreventIndexingOutlook' -ErrorAction SilentlyContinue).PreventIndexingOutlook
            if ($pv) { $preventOutlook = [int]$pv }
        }
        if ($preventOutlook -eq 1) {
            Write-ToolOutput 'PreventIndexingOutlook policy is ENABLED - Outlook indexing is disabled by policy.' -Level Warning
        } else {
            Write-ToolOutput 'PreventIndexingOutlook policy: not set (Outlook indexing allowed).' -Level Detail
        }
        $setupOk = (Get-ItemProperty -LiteralPath $searchSetupKey -Name 'SetupCompletedSuccessfully' -ErrorAction SilentlyContinue).SetupCompletedSuccessfully
        Write-ToolOutput ('Windows Search SetupCompletedSuccessfully: {0}' -f $setupOk) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook search repair' `
            -Choices @('None','FixConfig','RestartService','RebuildIndex') -Default 'None' -Silent:$Silent

        switch ($action) {

            'FixConfig' {
                $changes = New-Object System.Collections.Generic.List[string]
                $wnow = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                if ($wnow -and ("$($wnow.StartType)" -eq 'Disabled' -or "$($wnow.StartType)" -eq 'Manual')) {
                    Set-Service -Name 'WSearch' -StartupType Automatic -ErrorAction SilentlyContinue
                    Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                    $changes.Add('WSearch set to Automatic and started')
                }
                $gpoCaveat = $false
                if ($preventOutlook -eq 1) {
                    Set-ItemProperty -LiteralPath $searchPolicyKey -Name 'PreventIndexingOutlook' -Value 0 -ErrorAction SilentlyContinue
                    $recheck = (Get-ItemProperty -LiteralPath $searchPolicyKey -Name 'PreventIndexingOutlook' -ErrorAction SilentlyContinue).PreventIndexingOutlook
                    if ([int]$recheck -eq 0) {
                        $changes.Add('PreventIndexingOutlook policy cleared')
                        Write-ToolOutput 'Cleared PreventIndexingOutlook. If it returns after a gpupdate, it is set by Group Policy - fix the GPO; the toolkit cannot override a domain policy.' -Level Warning
                    } else {
                        $gpoCaveat = $true
                        Write-ToolOutput 'PreventIndexingOutlook could not be cleared (still 1) - it is enforced by Group Policy. Fix the GPO.' -Level Error
                    }
                }
                $wfin = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                $wstart = 'Unknown'
                if ($wfin) { $wstart = "$($wfin.StartType)" }
                if ($changes.Count -eq 0) {
                    Complete-ToolRun $run -Status Success -Summary 'Search config already healthy; no changes needed (run RebuildIndex if search is still broken)'
                } elseif ($gpoCaveat) {
                    Complete-ToolRun $run -Status Warning -Summary ('Applied: {0}; PreventIndexingOutlook is GPO-enforced - fix the GPO' -f ($changes -join '; '))
                } else {
                    Complete-ToolRun $run -Status Success -Summary ('Search config fixed ({0}); WSearch StartType {1}. Run RebuildIndex if search is still broken.' -f ($changes -join '; '), $wstart)
                }
            }

            'RestartService' {
                [void](Stop-OutlookGraceful)
                Restart-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                $now = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status
                if (-not $now) { $now = 'Unknown' }
                if ($now -eq 'Running') {
                    Complete-ToolRun $run -Status Success -Summary 'WSearch restarted (Running); Outlook search will recover'
                } else {
                    Complete-ToolRun $run -Status Warning -Summary ('WSearch restart left status {0}' -f $now)
                }
            }

            'RebuildIndex' {
                $confirm = Read-ToolChoice -Prompt 'Stop WSearch, delete the search index, and rebuild? (15-60 min reindex)' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RebuildIndex cancelled'
                    return
                }
                [void](Stop-OutlookGraceful)
                Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $stopped = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status -eq 'Stopped'
                $deleted = $false
                if ($stopped) {
                    $dir = Split-Path -Parent $edb
                    if (Test-Path -LiteralPath $edb) {
                        Remove-Item -LiteralPath $edb -Force -ErrorAction SilentlyContinue
                    }
                    Get-ChildItem -LiteralPath $dir -Filter '*.log' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                    $deleted = -not (Test-Path -LiteralPath $edb)
                }
                if (Test-Path -LiteralPath $catalogKey) {
                    Remove-ItemProperty -LiteralPath $catalogKey -Name 'Catalog' -ErrorAction SilentlyContinue
                }
                Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $now = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status
                if (-not $now) { $now = 'Unknown' }
                if (-not $stopped) {
                    Complete-ToolRun $run -Status Warning -Summary 'WSearch did not stop; index not deleted (Windows.edb is locked while WSearch runs)'
                } elseif ($now -ne 'Running') {
                    Complete-ToolRun $run -Status Warning -Summary ('Index removed but WSearch status is {0}' -f $now)
                } elseif (-not $deleted) {
                    Complete-ToolRun $run -Status Warning -Summary 'WSearch restarted but Windows.edb still present; rebuild may not have triggered'
                } else {
                    Complete-ToolRun $run -Status Success -Summary 'Search index deleted; WSearch Running; rebuild started (15-60 min)'
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Outlook search state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
