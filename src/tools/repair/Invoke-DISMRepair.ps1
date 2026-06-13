function Invoke-DISMRepair {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'dism-repair'

        # Phase 1: CheckHealth (fast read-only probe)
        Write-ToolOutput 'DISM CheckHealth: probing component store (may take 1-2 minutes)...'
        $checkLines = @(& dism.exe /Online /Cleanup-Image /CheckHealth 2>&1)
        $checkExit = $LASTEXITCODE

        foreach ($line in $checkLines) {
            $text = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                Write-ToolOutput ('  {0}' -f $text) -Level Detail
            }
        }

        if ($checkExit -ne 0) {
            Write-ToolOutput ('CheckHealth exited {0}' -f $checkExit) -Level Warning
        }

        # Phase 2: ScanHealth (slower read-only scan)
        Write-ToolOutput 'DISM ScanHealth: scanning for corruption (may take 5-10 minutes)...'
        $scanLines = @(& dism.exe /Online /Cleanup-Image /ScanHealth 2>&1)
        $scanExit = $LASTEXITCODE

        foreach ($line in $scanLines) {
            $text = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                Write-ToolOutput ('  {0}' -f $text) -Level Detail
            }
        }

        if ($scanExit -ne 0) {
            Write-ToolOutput ('ScanHealth exited {0}' -f $scanExit) -Level Warning
        }

        # Report probe summary as an Info headline before moving to the repair gate
        $noCorruption = ($checkExit -eq 0 -and $scanExit -eq 0)
        if ($noCorruption) {
            Write-ToolOutput 'Probes complete: no component store corruption detected'
        } else {
            Write-ToolOutput ('Probe results: CheckHealth exit {0}, ScanHealth exit {1}' -f $checkExit, $scanExit) -Level Warning
        }

        # Phase 3: RestoreHealth (optional - long-running, may download from Windows Update)
        $repairChoice = Read-ToolChoice `
            -Prompt 'Run full RestoreHealth repair? (10-20 min, may download from Windows Update)' `
            -Choices @('Yes', 'No') -Default 'No' -Silent:$Silent

        if ($repairChoice -ne 'Yes') {
            if ($noCorruption) {
                Complete-ToolRun $run -Status Success `
                    -Summary 'DISM CheckHealth and ScanHealth passed (exit 0); RestoreHealth not run'
            } else {
                Complete-ToolRun $run -Status Warning `
                    -Summary ('DISM scan found issues (CheckHealth exit {0}, ScanHealth exit {1}); RestoreHealth declined' -f $checkExit, $scanExit)
            }
            return
        }

        Write-ToolOutput 'DISM RestoreHealth: repairing component store (10-20 min, may contact Windows Update)...'
        $repairLines = @(& dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1)
        $repairExit = $LASTEXITCODE

        foreach ($line in $repairLines) {
            $text = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                Write-ToolOutput ('  {0}' -f $text) -Level Detail
            }
        }

        if ($repairExit -eq 0) {
            Complete-ToolRun $run -Status Success -Summary 'DISM RestoreHealth completed successfully (exit 0)'
        } else {
            Complete-ToolRun $run -Status Failed `
                -Summary ('DISM RestoreHealth exited {0}; component store repair may be incomplete' -f $repairExit)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
