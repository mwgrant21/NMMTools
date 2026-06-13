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
        Write-ToolOutput 'C:\Windows.old will be removed via rmdir; DISM /StartComponentCleanup will then reclaim component-store space.'
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

        # Step 1: Remove Windows.old folder via rmdir (primary removal)
        if (Test-Path 'C:\Windows.old') {
            Write-ToolOutput 'Removing C:\Windows.old via rmdir (may take several minutes)...' -Level Info
            & cmd.exe /c 'rmdir /s /q C:\Windows.old' 2>$null
        }

        # Step 2: DISM /StartComponentCleanup to reclaim component-store space
        Write-ToolOutput 'Running DISM /StartComponentCleanup (component store cleanup)...' -Level Info
        $dism = Start-Process -FilePath 'dism.exe' `
            -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup' `
            -NoNewWindow -PassThru -Wait -ErrorAction SilentlyContinue
        $exitCode = if ($null -ne $dism) { $dism.ExitCode } else { -1 }
        Write-ToolOutput ("DISM exited with code: {0}" -f $exitCode) -Level Detail

        # Step 3: Outcome based on whether folder is gone
        if (-not (Test-Path 'C:\Windows.old')) {
            Complete-ToolRun $run -Status Success `
                -Summary ("Windows.old removed (rollback no longer available); approx {0} MB freed" -f $sizeMB)
        } else {
            Complete-ToolRun $run -Status Warning `
                -Summary ('Windows.old could not be fully removed - some files may be locked; a reboot + retry or Disk Cleanup ''Previous Windows installation(s)'' may be needed')
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
