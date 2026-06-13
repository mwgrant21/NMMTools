function Get-StorageHealth {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'storage-health'

        # --- Physical disk report ---
        $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)

        if ($physicalDisks.Count -eq 0) {
            Write-ToolOutput 'No physical disks returned by Get-PhysicalDisk' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'No physical disks enumerated'
            return
        }

        Write-ToolOutput ('Physical disks ({0}):' -f $physicalDisks.Count)
        foreach ($disk in $physicalDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 1)
            $healthLabel = if ($disk.HealthStatus) { $disk.HealthStatus } else { 'Unknown' }
            Write-ToolOutput ('{0}  Type: {1}  Size: {2} GB  Health: {3}  Status: {4}' -f `
                $disk.FriendlyName, $disk.MediaType, $sizeGB, $healthLabel, $disk.OperationalStatus)

            # SMART / reliability counters - may be empty on some disks
            try {
                $smart = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
                if ($smart) {
                    if ($null -ne $smart.Temperature -and $smart.Temperature -gt 0) {
                        Write-ToolOutput ('  Temperature: {0} C' -f $smart.Temperature) -Level Detail
                    }
                    if ($null -ne $smart.Wear -and $smart.Wear -gt 0) {
                        Write-ToolOutput ('  Wear: {0}%' -f $smart.Wear) -Level Detail
                    }
                    if ($null -ne $smart.PowerOnHours -and $smart.PowerOnHours -gt 0) {
                        Write-ToolOutput ('  Power-On Hours: {0}' -f $smart.PowerOnHours) -Level Detail
                    }
                }
            } catch {
                Write-ToolOutput '  SMART/reliability data not available for this disk' -Level Detail
            }
        }

        # --- Volume report ---
        $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
        Write-ToolOutput ('Volumes ({0}):' -f $volumes.Count)
        foreach ($vol in $volumes) {
            $freeGB  = [math]::Round($vol.SizeRemaining / 1GB, 1)
            $totalGB = [math]::Round($vol.Size / 1GB, 1)
            Write-ToolOutput ('  {0}: {1}  Free: {2}/{3} GB  Health: {4}' -f `
                $vol.DriveLetter, $vol.FileSystemLabel, $freeGB, $totalGB, $vol.HealthStatus) -Level Detail
        }

        # Flag unhealthy disks
        $unhealthy = @($physicalDisks | Where-Object { $_.HealthStatus -ne 'Healthy' })
        if ($unhealthy.Count -gt 0) {
            Write-ToolOutput ('{0} disk(s) report non-Healthy status - review above' -f $unhealthy.Count) -Level Warning
        }

        # --- Action menu ---
        $action = Read-ToolChoice `
            -Prompt 'Storage action' `
            -Choices @('None','OptimizeC','ScanAllVolumes') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'OptimizeC' {
                $gate = Read-ToolChoice `
                    -Prompt 'Optimize C: drive (TRIM on SSD / defrag on HDD)? This can take several minutes.' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Optimizing C: drive (this may take several minutes)...' -Level Info
                    Optimize-Volume -DriveLetter C -ErrorAction Stop
                    Write-ToolOutput 'C: drive optimization complete' -Level Success
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} disk(s), {1} volume(s); C: drive optimized' -f $physicalDisks.Count, $volumes.Count)
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'OptimizeC cancelled by user'
                }
            }
            'ScanAllVolumes' {
                $gate = Read-ToolChoice `
                    -Prompt 'Run online read-only scan (Repair-Volume -Scan) on all lettered volumes? This can take several minutes per volume.' `
                    -Choices @('Yes','No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    $scanned = 0
                    foreach ($vol in $volumes) {
                        Write-ToolOutput ('Scanning {0}: ...' -f $vol.DriveLetter) -Level Info
                        try {
                            Repair-Volume -DriveLetter $vol.DriveLetter -Scan -ErrorAction SilentlyContinue
                            Write-ToolOutput ('  {0}: scan complete' -f $vol.DriveLetter) -Level Detail
                        } catch {
                            Write-ToolOutput ('  {0}: scan error - {1}' -f $vol.DriveLetter, $_.Exception.Message) -Level Warning
                        }
                        $scanned++
                    }
                    Write-ToolOutput ('Scanned {0} volume(s)' -f $scanned) -Level Success
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} disk(s), {1} volume(s) scanned' -f $physicalDisks.Count, $scanned)
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'ScanAllVolumes cancelled by user'
                }
            }
            default {
                if ($unhealthy.Count -gt 0) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary ('{0} disk(s) checked; {1} disk(s) non-Healthy' -f $physicalDisks.Count, $unhealthy.Count)
                } else {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('{0} disk(s) all Healthy; {1} volume(s) listed' -f $physicalDisks.Count, $volumes.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
