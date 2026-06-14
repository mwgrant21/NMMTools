function Reset-WindowsSearch {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-search-rebuild'

        # --- Report ---
        $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-ToolOutput 'Windows Search service (WSearch) not found on this machine.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'WSearch service not present'
            return
        }
        Write-ToolOutput ('Windows Search service: Status={0}  StartType={1}' -f $svc.Status, $svc.StartType) -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Windows Search action' `
            -Choices @('None','RestartService','RebuildIndex','OpenIndexingOptions') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartService' {
                Write-ToolOutput 'Restarting WSearch...' -Level Info
                Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                $now = (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).Status
                Write-ToolOutput ('WSearch status: {0}' -f $now) -Level Detail
                if ($now -eq 'Running') {
                    Complete-ToolRun $run -Status Success -Summary 'WSearch restarted (Running)'
                } else {
                    Complete-ToolRun $run -Status Warning -Summary ('WSearch restart left status {0}' -f $now)
                }
            }

            'RebuildIndex' {
                Write-ToolOutput 'WARNING: this clears the search index; Windows rebuilds it in the background (can take 1-2 hours).' -Level Warning
                $gate = Read-ToolChoice -Prompt 'Type CONFIRM to clear and rebuild the search index' `
                    -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
                if ($gate -ne 'CONFIRM') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RebuildIndex cancelled (no CONFIRM)'
                } else {
                    Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    $dataDir = Join-Path $env:ProgramData 'Microsoft\Search\Data'
                    if (Test-Path -LiteralPath $dataDir) {
                        Get-ChildItem -LiteralPath $dataDir -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
                    Write-ToolOutput 'Search index cleared; rebuild runs in the background.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'Search index cleared; background rebuild started'
                }
            }

            'OpenIndexingOptions' {
                Start-Process 'control.exe' -ArgumentList 'srchadmin.dll' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Indexing Options opened. Use Advanced -> Rebuild to rebuild the index.' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened Indexing Options (manual rebuild)'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('WSearch reported ({0}); no action taken' -f $svc.Status)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}