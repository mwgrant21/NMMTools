function Invoke-ChkDskRepair {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'chkdsk-repair'

        # Scan is the safe default; Fix schedules a long boot-time repair on the system drive
        $modeChoice = Read-ToolChoice `
            -Prompt 'ChkDsk mode: Scan (read-only) or Fix (/F /R schedules boot-time check on system drive)' `
            -Choices @('Scan', 'Fix') -Default 'Scan' -Silent:$Silent

        if ($modeChoice -eq 'Fix') {
            # Pipe Y to auto-confirm the scheduling prompt when C: is in use by Windows
            Write-ToolOutput 'Running chkdsk C: /F /R - on the system drive this schedules a boot-time check...'
            $chkLines = @('Y' | & chkdsk.exe C: /F /R 2>&1)
            $chkExit = $LASTEXITCODE

            foreach ($line in $chkLines) {
                $text = [string]$line
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    Write-ToolOutput ('  {0}' -f $text) -Level Detail
                }
            }

            $allText = ($chkLines | ForEach-Object { [string]$_ }) -join ' '
            $scheduled = $allText -match 'scheduled' -or $allText -match 'next restart' -or $allText -match 'next time the system restarts'

            if ($scheduled) {
                Complete-ToolRun $run -Status Success `
                    -Summary 'ChkDsk /F /R scheduled at next reboot on C: - reboot to run the check'
            } elseif ($chkExit -eq 0 -or $chkExit -eq 2) {
                Complete-ToolRun $run -Status Success `
                    -Summary ('ChkDsk /F /R completed: no errors found on C: (exit {0})' -f $chkExit)
            } elseif ($chkExit -eq 1) {
                Complete-ToolRun $run -Status Success `
                    -Summary 'ChkDsk /F /R: errors found and corrected on C: (exit 1)'
            } else {
                Complete-ToolRun $run -Status Warning `
                    -Summary ('ChkDsk /F /R on C: exited {0} - review output for details' -f $chkExit)
            }
        } else {
            Write-ToolOutput 'Running chkdsk C: (read-only scan, no changes)...'
            $chkLines = @(& chkdsk.exe C: 2>&1)
            $chkExit = $LASTEXITCODE

            foreach ($line in $chkLines) {
                $text = [string]$line
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    Write-ToolOutput ('  {0}' -f $text) -Level Detail
                }
            }

            if ($chkExit -eq 0 -or $chkExit -eq 2) {
                Complete-ToolRun $run -Status Success -Summary ('ChkDsk scan: no errors found on C: (exit {0})' -f $chkExit)
            } elseif ($chkExit -eq 1) {
                Complete-ToolRun $run -Status Warning `
                    -Summary 'ChkDsk scan: errors found on C: (exit 1) - run Fix mode to repair'
            } else {
                Complete-ToolRun $run -Status Warning `
                    -Summary ('ChkDsk scan on C: exited {0} - review output for details' -f $chkExit)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
