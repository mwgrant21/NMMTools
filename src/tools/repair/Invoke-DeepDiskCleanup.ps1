function Invoke-DeepDiskCleanup {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'deep-disk-cleanup'

        # --- Nested helpers (scriptblocks for guaranteed scope visibility) ---

        # Measure a folder tree in bytes
        $getFolderBytes = {
            param([string]$Path)
            if (-not (Test-Path $Path)) { return [int64]0 }
            try {
                $s = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                if ($s) { [int64]$s } else { [int64]0 }
            } catch { [int64]0 }
        }

        # Safe scoped Remove-Item: guards empty, too-short, and drive-root paths
        $removeScopedPath = {
            param([string]$Path)
            if ([string]::IsNullOrWhiteSpace($Path)) { return }
            if ($Path -match '^[A-Za-z]:\\?$' -or $Path.Length -lt 8) { return }
            if (Test-Path $Path) {
                Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Clear contents of a folder (not the folder itself); returns bytes freed
        $clearFolderContents = {
            param([string]$Label, [string]$Path, [bool]$StopWU = $false)
            if ([string]::IsNullOrWhiteSpace($Path)) {
                Write-ToolOutput ("  {0} : path is empty, skipped" -f $Label) -Level Warning
                return [int64]0
            }
            if (-not (Test-Path $Path)) {
                Write-ToolOutput ("  {0} : not present, skipped" -f $Label) -Level Detail
                return [int64]0
            }
            $before = & $getFolderBytes $Path
            if ($StopWU) {
                Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
            }
            Get-ChildItem $Path -Force -ErrorAction SilentlyContinue |
                ForEach-Object { & $removeScopedPath $_.FullName }
            if ($StopWU) {
                Start-Service bits, wuauserv -ErrorAction SilentlyContinue
            }
            $after = & $getFolderBytes $Path
            $freed = [math]::Max([int64]0, $before - $after)
            Write-ToolOutput ("  {0} : freed {1:N1} MB" -f $Label, ($freed / 1MB)) -Level Info
            return $freed
        }

        # --- Scan phase: report sizes of all cleanup candidates ---
        $allTargets = [ordered]@{
            'User Temp'             = $env:TEMP
            'Windows Temp'          = 'C:\Windows\Temp'
            'Windows Prefetch'      = 'C:\Windows\Prefetch'
            'WU Download Cache'     = 'C:\Windows\SoftwareDistribution\Download'
            'CBS Logs'              = 'C:\Windows\Logs\CBS'
            'WER ReportQueue'       = 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'
            'WER ReportArchive'     = 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
            'Delivery Optimization' = 'C:\Windows\SoftwareDistribution\DeliveryOptimization'
            'Windows.old'           = 'C:\Windows.old'
        }
        Write-ToolOutput 'Scanning cleanup candidates...'
        $totalEstimateBytes = [int64]0
        foreach ($scanLabel in $allTargets.Keys) {
            $scanPath = $allTargets[$scanLabel]
            $scanBytes = & $getFolderBytes $scanPath
            $totalEstimateBytes += $scanBytes
            $sizeStr = if (Test-Path $scanPath) { ('{0:N1} MB' -f ($scanBytes / 1MB)) } else { 'not present' }
            Write-ToolOutput ('  {0,-40} {1,10}' -f $scanLabel, $sizeStr) -Level Detail
        }
        Write-ToolOutput ('Estimated reclaimable: {0:N1} MB' -f ($totalEstimateBytes / 1MB))

        # --- Tier selection ---
        Write-ToolOutput 'Conservative: temp/WU cache/CBS logs/WER (safe, no user data)'
        Write-ToolOutput 'Full: Conservative + Delivery Optimization + Windows.old (ends OS rollback)'
        $tier = Read-ToolChoice `
            -Prompt 'Select cleanup tier' `
            -Choices @('Conservative', 'Full') `
            -Default 'Conservative' `
            -Silent:$Silent

        # --- Second gate for Full tier (Windows.old removal is irreversible) ---
        if ($tier -eq 'Full') {
            $fullGate = Read-ToolChoice `
                -Prompt 'Full tier removes Windows.old (ends OS rollback). Type CONFIRM to proceed' `
                -Choices @('CONFIRM', 'Cancel') `
                -Default 'Cancel' `
                -Silent:$Silent
            if ($fullGate -ne 'CONFIRM') {
                Complete-ToolRun $run -Status Skipped `
                    -Summary 'User cancelled Full tier Windows.old confirmation'
                return
            }
        }

        # --- Clean phase ---
        $freeBefore = (Get-PSDrive -Name C -ErrorAction SilentlyContinue).Free
        $totalFreedBytes = [int64]0

        # Conservative set (always runs)
        $totalFreedBytes += & $clearFolderContents 'User Temp'         $env:TEMP                                             $false
        $totalFreedBytes += & $clearFolderContents 'Windows Temp'      'C:\Windows\Temp'                                    $false
        $totalFreedBytes += & $clearFolderContents 'Windows Prefetch'  'C:\Windows\Prefetch'                                $false
        $totalFreedBytes += & $clearFolderContents 'WU Download Cache' 'C:\Windows\SoftwareDistribution\Download'           $true
        $totalFreedBytes += & $clearFolderContents 'CBS Logs'          'C:\Windows\Logs\CBS'                                $false
        $totalFreedBytes += & $clearFolderContents 'WER ReportQueue'   'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'   $false
        $totalFreedBytes += & $clearFolderContents 'WER ReportArchive' 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive' $false

        # Full tier extras (only after the typed confirm gate above)
        if ($tier -eq 'Full') {
            $totalFreedBytes += & $clearFolderContents 'Delivery Optimization' `
                'C:\Windows\SoftwareDistribution\DeliveryOptimization' $false

            if (Test-Path 'C:\Windows.old') {
                Write-ToolOutput 'Removing Windows.old (may take several minutes)...' -Level Info
                $winOldBytes = & $getFolderBytes 'C:\Windows.old'
                & cmd.exe /c 'rmdir /s /q C:\Windows.old' 2>$null
                if (-not (Test-Path 'C:\Windows.old')) {
                    Write-ToolOutput ('  Windows.old : freed {0:N1} MB (rmdir)' -f ($winOldBytes / 1MB)) -Level Info
                    $totalFreedBytes += $winOldBytes
                } else {
                    Write-ToolOutput 'rmdir incomplete - trying DISM /SPSuperseded...' -Level Warning
                    & dism.exe /Online /Cleanup-Image /SPSuperseded /Quiet 2>$null
                    $winOldRemaining = & $getFolderBytes 'C:\Windows.old'
                    $winOldFreed = [math]::Max([int64]0, $winOldBytes - $winOldRemaining)
                    $totalFreedBytes += $winOldFreed
                    Write-ToolOutput ('  Windows.old (DISM) : freed {0:N1} MB' -f ($winOldFreed / 1MB)) -Level Info
                }
            } else {
                Write-ToolOutput '  Windows.old : not present, skipped' -Level Detail
            }
        }

        $freeAfter = (Get-PSDrive -Name C -ErrorAction SilentlyContinue).Free
        $freedMB = [math]::Round($totalFreedBytes / 1MB, 1)
        if ($null -ne $freeBefore -and $null -ne $freeAfter) {
            $measuredMB = [math]::Round([math]::Max(0, ($freeAfter - $freeBefore) / 1MB), 1)
            if ($measuredMB -gt $freedMB) { $freedMB = $measuredMB }
        }

        Complete-ToolRun $run -Status Success `
            -Summary ("Freed {0:N1} MB ({1} tier)" -f $freedMB, $tier)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
