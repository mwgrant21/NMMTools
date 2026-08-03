function Get-CrashDumpInventory {
    [CmdletBinding()]
    param(
        [switch]$Silent,   # required by dispatcher even when unused
        [int]$HoursBack = 24
    )

    $run = $null
    try {
        $run = New-ToolRun -Id 'wer-crash-inventory'

        $cutoff = (Get-Date).AddHours(-$HoursBack)

        $paths = @(
            (Join-Path $env:LOCALAPPDATA 'CrashDumps'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive')
        )

        $found = @()
        foreach ($p in $paths) {
            if (Test-Path -LiteralPath $p) {
                $found += Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -ge $cutoff }
            }
        }

        if ($found.Count -eq 0) {
            Write-ToolOutput ('No crash dump or WER report files in the last {0}h.' -f $HoursBack)
            Complete-ToolRun $run -Status Success -Summary ('0 crash items in last {0}h' -f $HoursBack)
            return
        }

        Write-ToolOutput ('Crash dump / WER items in last {0}h: {1}' -f $HoursBack, $found.Count)
        foreach ($f in ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 15)) {
            $sizeKB = [math]::Round($f.Length / 1KB, 1)
            Write-ToolOutput ('{0:g}  {1}  ({2} KB)' -f $f.LastWriteTime, $f.Name, $sizeKB) -Level Detail
        }

        Complete-ToolRun $run -Status Warning -Summary ('{0} crash dump/WER item(s) in last {1}h' -f $found.Count, $HoursBack)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
