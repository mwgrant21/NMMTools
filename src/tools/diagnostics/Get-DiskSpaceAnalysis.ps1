function Get-DiskSpaceAnalysis {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'disk-space'

        $disks = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
            Where-Object { $_.Size -gt 0 } |
            ForEach-Object {
                [PSCustomObject]@{
                    Drive        = $_.DeviceID
                    Label        = $_.VolumeName
                    TotalSize_GB = [math]::Round($_.Size / 1GB, 2)
                    FreeSpace_GB = [math]::Round($_.FreeSpace / 1GB, 2)
                    PercentFree  = [math]::Round(($_.FreeSpace / $_.Size) * 100, 2)
                }
            })

        foreach ($d in $disks) {
            $line = '{0} [{1}]  {2} GB total  {3} GB free  ({4}% free)' -f
                $d.Drive, $d.Label, $d.TotalSize_GB, $d.FreeSpace_GB, $d.PercentFree
            if ($d.PercentFree -lt 10) {
                Write-ToolOutput $line -Level Warning
            } else {
                Write-ToolOutput $line -Level Detail
            }
        }

        $lowCount = @($disks | Where-Object { $_.PercentFree -lt 10 }).Count
        if ($lowCount -gt 0) {
            Write-ToolOutput ('{0} volume(s) below 10% free space.' -f $lowCount) -Level Warning
        }

        $summaryParts = $disks | ForEach-Object {
            $pctFull = [math]::Round(100 - $_.PercentFree, 1)
            '{0}: {1}% full, {2} GB free' -f $_.Drive, $pctFull, $_.FreeSpace_GB
        }

        if ($lowCount -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary (
                '{0}; {1} volume(s) below 10% free' -f ($summaryParts -join '; '), $lowCount)
        } else {
            Complete-ToolRun $run -Status Success -Summary ($summaryParts -join '; ')
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
