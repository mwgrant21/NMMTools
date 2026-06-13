function Invoke-SystemRepairSuite {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'repair-suite'

        $choice = Read-ToolChoice `
            -Prompt 'Run full repair suite: DISM RestoreHealth + SFC + temp cleanup (20-30 min)?' `
            -Choices @('Yes', 'No') `
            -Default 'No' `
            -Silent:$Silent

        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined full repair suite'
            return
        }

        # Step 1: DISM RestoreHealth
        Write-ToolOutput '=== Step 1/3: DISM RestoreHealth ===' -Level Info
        $dismResult = Invoke-DismRestoreHealth

        # Step 2: SFC scan
        Write-ToolOutput '=== Step 2/3: System File Checker ===' -Level Info
        $sfcResult = Invoke-SfcScan

        # Step 3: Conservative temp cleanup
        Write-ToolOutput '=== Step 3/3: Conservative Temp Cleanup ===' -Level Info
        $cleanResult = Invoke-ConservativeTempCleanup

        # Per-step summary
        Write-ToolOutput ('DISM  : {0} - {1}' -f $dismResult.Status,  $dismResult.Summary)  -Level Info
        Write-ToolOutput ('SFC   : {0} - {1}' -f $sfcResult.Status,   $sfcResult.Summary)   -Level Info
        Write-ToolOutput ('Temp  : {0} - {1}' -f $cleanResult.Status, $cleanResult.Summary) -Level Info

        # Overall verdict: Failed > Warning > Success
        $allStatuses = @($dismResult.Status, $sfcResult.Status, $cleanResult.Status)
        $overallStatus = if ($allStatuses -contains 'Failed') {
            'Failed'
        } elseif ($allStatuses -contains 'Warning') {
            'Warning'
        } else {
            'Success'
        }

        Complete-ToolRun $run -Status $overallStatus `
            -Summary ('Repair suite: DISM={0}, SFC={1}, Temp={2} ({3} MB freed)' -f
                $dismResult.Status, $sfcResult.Status, $cleanResult.Status, $cleanResult.MbFreed)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
