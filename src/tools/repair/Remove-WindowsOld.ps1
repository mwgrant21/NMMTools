function Remove-WindowsOld {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-old-removal'

        # Hardcoded literal - no empty-variable risk
        $oldPath = 'C:\Windows.old'

        if (-not (Test-Path $oldPath)) {
            Complete-ToolRun $run -Status Success -Summary 'No Windows.old present - nothing to remove'
            return
        }

        # Report approximate size
        $sizeMB = 0
        try {
            $sizeSum = (Get-ChildItem $oldPath -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($sizeSum) { $sizeMB = [math]::Round($sizeSum / 1MB, 0) }
        } catch { $sizeMB = 0 }

        Write-ToolOutput ("Windows.old detected - approximate size: {0} MB" -f $sizeMB)
        Write-ToolOutput 'DISM /StartComponentCleanup /ResetBase will remove Windows.old and superseded components.'
        Write-ToolOutput 'WARNING: This operation is IRREVERSIBLE. The previous Windows version cannot be restored.' `
            -Level Warning

        # Strong confirm gate - default Cancel (safe)
        $gate = Read-ToolChoice `
            -Prompt 'Permanently remove Windows.old? This ENDS the ability to roll back the previous Windows. Type CONFIRM' `
            -Choices @('CONFIRM', 'Cancel') `
            -Default 'Cancel' `
            -Silent:$Silent

        if ($gate -ne 'CONFIRM') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined Windows.old removal'
            return
        }

        Write-ToolOutput 'Running DISM /StartComponentCleanup /ResetBase (may take several minutes)...' -Level Info

        $dism = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup /ResetBase' `
            -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue

        $exitCode = if ($null -ne $dism) { $dism.ExitCode } else { -1 }
        Write-ToolOutput ("DISM exited with code: {0}" -f $exitCode) -Level Detail

        if ($exitCode -eq 0) {
            Complete-ToolRun $run -Status Success `
                -Summary ("Windows.old removed via DISM ResetBase (approx {0} MB freed)" -f $sizeMB)
        } else {
            Complete-ToolRun $run -Status Warning `
                -Summary ("DISM exited {0} - Windows.old removal may be incomplete; check CBS.log" -f $exitCode)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
