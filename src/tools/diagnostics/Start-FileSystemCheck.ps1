function Start-FileSystemCheck {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'file-system-check'

        # v8: non-admin path used Get-Volume to show DriveLetter, FileSystem, HealthStatus.
        # Admin path only printed "File system check requires system restart" - no check was
        # scheduled or executed. Port preserves the read-only volume-health report.
        $volumes = @(Get-Volume | Where-Object { $_.DriveLetter })

        if ($volumes.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No drive-letter volumes found'
            return
        }

        Write-ToolOutput ('Drive-letter volumes: {0}' -f $volumes.Count)
        # Each volume is a scan row; Unhealthy volumes surface at Warning level
        $unhealthy = @()
        foreach ($vol in $volumes) {
            $line = '{0}:  {1,-12}  [{2}]' -f $vol.DriveLetter, $vol.FileSystem, $vol.HealthStatus
            if ($vol.HealthStatus -ne 'Healthy') {
                Write-ToolOutput $line -Level Warning
                $unhealthy += ('{0}:' -f $vol.DriveLetter)
            } else {
                Write-ToolOutput $line -Level Detail
            }
        }

        Write-ToolOutput 'Note: a full file system scan requires a scheduled restart (chkdsk).'

        if ($unhealthy.Count -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary (
                '{0} unhealthy volume(s): {1}' -f $unhealthy.Count, ($unhealthy -join ' '))
        } else {
            Complete-ToolRun $run -Status Success -Summary (
                '{0} volume(s) checked - all Healthy' -f $volumes.Count)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
