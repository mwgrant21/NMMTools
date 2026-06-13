function Invoke-SFCRepair {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'sfc-repair'

        # sfc /scannow is synchronous - tech must see it is working
        Write-ToolOutput 'Running sfc /scannow - this may take 10-15 minutes...'
        $savedEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
            $sfcLines = @(& sfc.exe /scannow 2>&1)
            $sfcExit = $LASTEXITCODE
        } finally {
            [Console]::OutputEncoding = $savedEnc
        }

        # sfc output may be UTF-16-encoded in console; stringify each element best-effort
        foreach ($line in $sfcLines) {
            $text = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                Write-ToolOutput ('  {0}' -f $text) -Level Detail
            }
        }

        # Parse the result statement from sfc output (best-effort; fall back to exit code)
        $allText = ($sfcLines | ForEach-Object { [string]$_ }) -join ' '

        if ($allText -match 'did not find any integrity violations') {
            Complete-ToolRun $run -Status Success `
                -Summary ('SFC: no integrity violations found (exit {0})' -f $sfcExit)
            return
        }

        if ($allText -match 'found corrupt files and successfully repaired') {
            Complete-ToolRun $run -Status Success `
                -Summary ('SFC: corrupt files found and repaired successfully (exit {0})' -f $sfcExit)
            return
        }

        if ($allText -match 'found corrupt files but was unable') {
            Complete-ToolRun $run -Status Warning `
                -Summary ('SFC: corrupt files found but repair failed (exit {0}); run DISM RestoreHealth then retry SFC' -f $sfcExit)
            return
        }

        # Fallback: key off exit code when output text could not be parsed
        if ($sfcExit -eq 0) {
            Complete-ToolRun $run -Status Success `
                -Summary 'SFC scan completed (exit 0; output text could not be parsed - check CBS.log for details)'
        } else {
            Complete-ToolRun $run -Status Warning `
                -Summary ('SFC exited {0}; review output or CBS.log for details' -f $sfcExit)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
