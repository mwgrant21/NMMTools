function Get-PendingRebootStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'pending-reboot'

        $reasons = @()

        # [PENDING] rows use Warning so techs see them immediately; [OK] rows default to Info;
        # SCCM not-present is Detail (informational - not a problem on non-SCCM machines)

        # 1. Windows Update
        $wuKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        if (Test-Path $wuKey) {
            $reasons += 'Windows Update requires reboot'
            Write-ToolOutput '[PENDING] Windows Update - RebootRequired key present' -Level Warning
        } else {
            Write-ToolOutput '[OK] Windows Update - no pending reboot'
        }

        # 2. Component Based Servicing (CBS)
        $cbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        if (Test-Path $cbsKey) {
            $reasons += 'Component Based Servicing (CBS) requires reboot'
            Write-ToolOutput '[PENDING] CBS - RebootPending key present' -Level Warning
        } else {
            Write-ToolOutput '[OK] Component Based Servicing - no pending reboot'
        }

        # 3. Pending File Rename Operations (value under Session Manager, not a key)
        $pfroVal = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($pfroVal) {
            $count    = @($pfroVal).Count
            $reasons += "Pending file rename operations ($count entries)"
            Write-ToolOutput "[PENDING] PendingFileRenameOperations - $count entr(ies)" -Level Warning
        } else {
            Write-ToolOutput '[OK] Pending File Rename Operations - none'
        }

        # 4. Computer rename pending (active name differs from pending target name)
        $active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' `
            -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' `
            -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
        if ($active -and $pending -and $active -ne $pending) {
            $reasons += "Computer rename pending ($active -> $pending)"
            Write-ToolOutput "[PENDING] Computer rename: $active -> $pending" -Level Warning
        } else {
            Write-ToolOutput '[OK] Computer name - no rename pending'
        }

        # 5. SCCM / ConfigMgr (optional; silently skipped when agent not installed)
        try {
            $sccm       = [wmiclass]'\\.\root\ccm\clientsdk:CCM_ClientUtilities'
            $sccmResult = $sccm.DetermineIfRebootPending()
            if ($sccmResult.RebootPending -or $sccmResult.IsHardRebootPending) {
                $reasons += 'SCCM/ConfigMgr reboot pending'
                Write-ToolOutput '[PENDING] SCCM/ConfigMgr - reboot pending' -Level Warning
            } else {
                Write-ToolOutput '[OK] SCCM/ConfigMgr - no pending reboot'
            }
        } catch {
            Write-ToolOutput '[--] SCCM/ConfigMgr - not present or not queried' -Level Detail
        }

        if ($reasons.Count -gt 0) {
            Write-ToolOutput ('Reboot required - {0} reason(s): {1}' -f $reasons.Count, ($reasons -join '; ')) -Level Warning
            Write-ToolOutput 'Recommendation: reboot this machine before running repair tools.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary ('Reboot pending: {0}' -f ($reasons -join '; '))
        } else {
            Write-ToolOutput 'No pending reboot detected across all checked sources.'
            Complete-ToolRun $run -Status Success -Summary 'No pending reboot'
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}