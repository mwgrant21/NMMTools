function Repair-PrinterIssues {
    [CmdletBinding()]
    param([switch]$Silent)

    # v8 tool-98 deep reset: stop Spooler -> clear spool\PRINTERS contents -> start Spooler.
    function Invoke-SpoolerFolderReset {
        Stop-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $stopped = (Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue).Status -eq 'Stopped'
        if (-not $stopped) {
            return @{ Status = 'Warning'; Text = 'Spooler did not stop; spool folder not cleared (try again or check the service)' }
        }
        $spoolDir = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
        $files = 0
        if (Test-Path -LiteralPath $spoolDir) {
            $items = @(Get-ChildItem -LiteralPath $spoolDir -Force -ErrorAction SilentlyContinue)
            $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            $files = $items.Count
        }
        Start-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $now = (Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue).Status
        if (-not $now) { $now = 'Unknown' }
        if ($now -eq 'Running') {
            return @{ Status = 'Success'; Text = ('spool folder cleared ({0} file(s)); Spooler Running' -f $files) }
        } else {
            return @{ Status = 'Warning'; Text = ('spool folder cleared ({0} file(s)) but Spooler status is {1}' -f $files, $now) }
        }
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'printer-repair'

        # --- Report ---
        $printers = @(Get-Printer -ErrorAction SilentlyContinue)
        if ($printers.Count -gt 0) {
            Write-ToolOutput ('Installed printers: {0}' -f $printers.Count) -Level Info
            foreach ($pr in $printers) {
                Write-ToolOutput ('  {0}  [{1}]  port={2}' -f $pr.Name, $pr.PrinterStatus, $pr.PortName) -Level Detail
            }
        } else {
            Write-ToolOutput 'No printers found on this system.' -Level Warning
        }
        $spooler = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
        if ($spooler) {
            Write-ToolOutput ('Print Spooler: {0} (StartType {1})' -f $spooler.Status, $spooler.StartType) -Level Info
        }
        $jobs = @(Get-PrintJob -PrinterName * -ErrorAction SilentlyContinue)
        Write-ToolOutput ('Queued print jobs: {0}' -f $jobs.Count) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Printer action' `
            -Choices @('None','RestartSpooler','ClearJobs','ClearSpoolFolder','RemoveGhostPrinters','FullReset') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RestartSpooler' {
                Restart-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                $now = (Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue).Status
                if (-not $now) { $now = 'Unknown' }
                if ($now -eq 'Running') {
                    Complete-ToolRun $run -Status Success -Summary 'Print Spooler restarted (Running)'
                } else {
                    Complete-ToolRun $run -Status Warning -Summary ('Spooler restart left status {0}' -f $now)
                }
            }

            'ClearJobs' {
                $confirm = Read-ToolChoice -Prompt 'Cancel all queued print jobs?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearJobs cancelled'
                } else {
                    $n = 0
                    foreach ($j in @(Get-PrintJob -PrinterName * -ErrorAction SilentlyContinue)) {
                        Remove-PrintJob -InputObject $j -ErrorAction SilentlyContinue
                        $n++
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Cancelled {0} print job(s)' -f $n)
                }
            }

            'ClearSpoolFolder' {
                $confirm = Read-ToolChoice -Prompt 'Stop the Spooler, clear the spool folder, and restart it?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearSpoolFolder cancelled'
                } else {
                    $res = Invoke-SpoolerFolderReset
                    Complete-ToolRun $run -Status $res.Status -Summary $res.Text
                }
            }

            'RemoveGhostPrinters' {
                $ghosts = @($printers | Where-Object { $_.PrinterStatus -eq 'Offline' -or $_.PrinterStatus -eq 'Error' })
                if ($ghosts.Count -eq 0) {
                    Complete-ToolRun $run -Status Success -Summary 'No offline/error printers to remove'
                } else {
                    Write-ToolOutput ('Will remove: {0}' -f (($ghosts | ForEach-Object { $_.Name }) -join ', ')) -Level Detail
                    $confirm = Read-ToolChoice -Prompt ('Remove {0} offline/error printer(s)?' -f $ghosts.Count) -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                    if ($confirm -ne 'Yes') {
                        Complete-ToolRun $run -Status Skipped -Summary 'RemoveGhostPrinters cancelled'
                    } else {
                        $n = 0
                        foreach ($g in $ghosts) {
                            Remove-Printer -Name $g.Name -ErrorAction SilentlyContinue
                            $n++
                        }
                        Complete-ToolRun $run -Status Success -Summary ('Removed {0} offline/error printer(s)' -f $n)
                    }
                }
            }

            'FullReset' {
                $confirm = Read-ToolChoice -Prompt 'Full reset: stop Spooler, clear the spool folder, restart Spooler?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'FullReset cancelled'
                } else {
                    $res = Invoke-SpoolerFolderReset
                    Complete-ToolRun $run -Status $res.Status -Summary ('Full printer reset: {0}' -f $res.Text)
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('{0} printer(s) reported; no action taken' -f $printers.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
