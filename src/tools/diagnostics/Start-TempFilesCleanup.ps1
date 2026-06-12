function Start-TempFilesCleanup {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'temp-cleanup'
        $targets = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) |
            Sort-Object -Unique | Where-Object { Test-Path $_ }

        $measure = {
            param($paths)
            $total = [int64]0
            foreach ($p in $paths) {
                $sum = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Measure-Object Length -Sum).Sum
                if ($sum) { $total += $sum }
            }
            $total
        }

        $before = & $measure $targets
        Write-ToolOutput ('Temp folders hold {0:N1} MB across {1} locations' -f
            ($before / 1MB), $targets.Count)

        $choice = Read-ToolChoice -Prompt 'Delete temp files now?' -Default 'Yes' -Silent:$Silent
        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined cleanup'
            return
        }

        $locked = 0
        foreach ($t in $targets) {
            $items = Get-ChildItem $t -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                try {
                    Remove-Item $item.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop
                } catch {
                    $locked++   # in-use files are expected; count and move on
                }
            }
        }

        $after = & $measure $targets
        $freedMB = [math]::Max(0, ($before - $after) / 1MB)
        Complete-ToolRun $run -Status Success -Summary ('Freed {0:N1} MB ({1} top-level paths in use, skipped)' -f
            $freedMB, $locked)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
