function Get-SystemHealthCheck {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'system-health'

        $issues = @()

        # --- Disk check -------------------------------------------------------
        $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
            Where-Object { $_.Size -gt 0 })

        Write-ToolOutput ('Disk: {0} fixed volume(s)' -f $disks.Count)
        # Disk rows use Detail; volumes below 10% free surface as Warning
        foreach ($disk in $disks) {
            $pctFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            $freeGB  = [math]::Round($disk.FreeSpace / 1GB, 2)
            $line    = '{0}  {1}% free  ({2} GB free)' -f $disk.DeviceID, $pctFree, $freeGB
            if ($pctFree -lt 10) {
                Write-ToolOutput $line -Level Warning
                $issues += ('Low disk space on {0}' -f $disk.DeviceID)
            } else {
                Write-ToolOutput $line -Level Detail
            }
        }

        # --- Memory check -----------------------------------------------------
        # Win32_OperatingSystem is a singleton; Select-Object -First 1 guards against unexpected multi-instance results
        $os         = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
        $memPercent = [math]::Round(
            (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 2)

        Write-ToolOutput ('Memory: {0}% used' -f $memPercent)
        if ($memPercent -gt 90) {
            Write-ToolOutput ('High memory usage: {0}%' -f $memPercent) -Level Warning
            $issues += ('High memory usage: {0}%' -f $memPercent)
        }

        # --- Verdict ----------------------------------------------------------
        if ($issues.Count -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary (
                'Needs Attention — {0} issue(s): {1}' -f $issues.Count, ($issues -join '; '))
        } else {
            Complete-ToolRun $run -Status Success -Summary (
                'Healthy — disk and memory within thresholds')
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
