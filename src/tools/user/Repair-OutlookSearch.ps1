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

        # --- Report ---
        $ws = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if ($ws) {
            Write-ToolOutput ('Windows Search (WSearch): {0} (StartType {1})' -f $ws.Status, $ws.StartType) -Level Info
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

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook search repair' `
            -Choices @('None','RestartService','RebuildIndex') -Default 'None' -Silent:$Silent

        switch ($action) {

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
