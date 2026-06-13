# Shared repair helpers for Invoke-SystemRepairSuite.
# These are plain functions, not tool functions - no registry entries needed.
# Called in sequence by the suite; each returns @{ Status; Summary } (Temp adds MbFreed).

function Invoke-DismRestoreHealth {
    Write-ToolOutput 'DISM RestoreHealth: repairing component store (10-20 min, may contact Windows Update)...' -Level Info
    $lines = @(& dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1)
    $exit = $LASTEXITCODE
    foreach ($line in $lines) {
        $text = [string]$line
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-ToolOutput ('  {0}' -f $text) -Level Detail
        }
    }
    if ($exit -eq 0) {
        return @{ Status = 'Success'; Summary = 'DISM RestoreHealth completed (exit 0)' }
    } else {
        return @{ Status = 'Failed'; Summary = ('DISM RestoreHealth exited {0}' -f $exit) }
    }
}

function Invoke-SfcScan {
    Write-ToolOutput 'SFC: running sfc /scannow (10-15 min)...' -Level Info
    $savedEnc = [Console]::OutputEncoding
    $lines = @()
    $sfcExit = 0
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $lines = @(& sfc.exe /scannow 2>&1)
        $sfcExit = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $savedEnc
    }
    foreach ($line in $lines) {
        $text = [string]$line
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-ToolOutput ('  {0}' -f $text) -Level Detail
        }
    }
    $allText = ($lines | ForEach-Object { [string]$_ }) -join ' '
    if ($allText -match 'did not find any integrity violations') {
        return @{ Status = 'Success'; Summary = ('SFC: no integrity violations (exit {0})' -f $sfcExit) }
    }
    if ($allText -match 'found corrupt files and successfully repaired') {
        return @{ Status = 'Success'; Summary = ('SFC: corrupt files repaired (exit {0})' -f $sfcExit) }
    }
    if ($allText -match 'found corrupt files but was unable') {
        return @{ Status = 'Warning'; Summary = ('SFC: corrupt files found but repair failed (exit {0}); run DISM then retry' -f $sfcExit) }
    }
    if ($sfcExit -eq 0) {
        return @{ Status = 'Success'; Summary = 'SFC completed (exit 0; check CBS.log for details)' }
    } else {
        return @{ Status = 'Warning'; Summary = ('SFC exited {0}; review CBS.log' -f $sfcExit) }
    }
}

function Invoke-ConservativeTempCleanup {
    Write-ToolOutput 'Temp cleanup: clearing user TEMP and C:\Windows\Temp...' -Level Info
    $tempPaths = @($env:TEMP, 'C:\Windows\Temp')
    $totalFreed = [int64]0
    foreach ($path in $tempPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-ToolOutput '  (skipped empty temp path)' -Level Detail
            continue
        }
        if (-not (Test-Path $path)) {
            Write-ToolOutput ('  {0}: not present, skipped' -f $path) -Level Detail
            continue
        }
        $before = [int64]0
        try {
            $sz = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($sz) { $before = [int64]$sz }
        } catch {}
        Get-ChildItem $path -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        $after = [int64]0
        try {
            $sz = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($sz) { $after = [int64]$sz }
        } catch {}
        $freed = [math]::Max([int64]0, $before - $after)
        $totalFreed += $freed
        Write-ToolOutput ('  {0}: freed {1:N1} MB' -f $path, ($freed / 1MB)) -Level Info
    }
    $mbFreed = [math]::Round($totalFreed / 1MB, 1)
    return @{ Status = 'Success'; Summary = ('Temp cleanup freed {0:N1} MB' -f $mbFreed); MbFreed = $mbFreed }
}
