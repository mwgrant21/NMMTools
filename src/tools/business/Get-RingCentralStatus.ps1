function Get-RingCentralStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'ringcentral-status'

        # --- Install detection ---
        $installCandidates = @(
            @{ Path = (Join-Path $env:LOCALAPPDATA 'Programs\RingCentral'); ProcessName = 'RingCentral' },
            @{ Path = (Join-Path $env:LOCALAPPDATA 'Glip');                 ProcessName = 'Glip' }
        )
        $installDir  = $null
        $processName = $null
        foreach ($c in $installCandidates) {
            if (Test-Path -LiteralPath $c.Path) {
                $installDir  = $c.Path
                $processName = $c.ProcessName
                break
            }
        }
        if (-not $installDir) {
            Write-ToolOutput 'RingCentral is not installed (no matching install directory found under AppData\Local)' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'RingCentral not installed'
            return
        }
        Write-ToolOutput ('Installed: {0}' -f $installDir) -Level Info

        # --- Version (from install manifest if present) ---
        $version = 'Unknown'
        $verDir = Get-ChildItem -LiteralPath $installDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^app-\d' } | Sort-Object Name -Descending | Select-Object -First 1
        if ($verDir -and $verDir.Name -match '^app-(.+)$') {
            $version = $Matches[1]
        }
        Write-ToolOutput ('Version: {0}' -f $version) -Level Info

        # --- Process check ---
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -First 1
        $processLevel = if ($process) { 'Info' } else { 'Warning' }
        $processText  = if ($process) { 'Running' } else { 'Not running' }
        Write-ToolOutput ('Process ({0}): {1}' -f $processName, $processText) -Level $processLevel

        # --- Default audio device ---
        $audioDevice = Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
        $audioLevel = if ($audioDevice) { 'Info' } else { 'Warning' }
        $audioText  = if ($audioDevice) { $audioDevice.Name } else { 'No working audio device found' }
        Write-ToolOutput ('Audio device: {0}' -f $audioText) -Level $audioLevel

        # --- Log scan ---
        $logErrors  = New-Object System.Collections.Generic.List[string]
        $logChecked = ($processName -eq 'RingCentral')
        if ($logChecked) {
            $logDir = Join-Path $env:LOCALAPPDATA 'RingCentral\RingCentralLogs'
            if (Test-Path -LiteralPath $logDir) {
                $latestLog = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latestLog) {
                    try {
                        $tail = Get-Content -LiteralPath $latestLog.FullName -ErrorAction SilentlyContinue | Select-Object -Last 300
                        $hits = @($tail | Where-Object { $_ -match 'error|fail|disconnect|timeout' })
                        foreach ($h in ($hits | Select-Object -Last 5)) {
                            $logErrors.Add($h.Trim())
                        }
                    } catch { }
                }
            }
            if ($logErrors.Count -gt 0) {
                Write-ToolOutput ('Recent log errors ({0}):' -f $logErrors.Count) -Level Warning
                foreach ($e in $logErrors) { Write-ToolOutput ('  {0}' -f $e) -Level Detail }
            } else {
                Write-ToolOutput 'No recent log errors found' -Level Detail
            }
        } else {
            Write-ToolOutput 'Log location not confirmed for legacy Glip-branded install; skipping log scan' -Level Detail
        }

        # --- Reachability ---
        $target  = 'app.ringcentral.com'
        $dnsFail = $false
        try {
            [System.Net.Dns]::GetHostAddresses($target) | Out-Null
        } catch { $dnsFail = $true }
        $pingOk = $false
        if (-not $dnsFail) {
            $ping = Test-Connection -ComputerName $target -Count 2 -ErrorAction SilentlyContinue
            $pingOk = ($null -ne $ping) -and (@($ping).Count -gt 0)
        }
        $reachLevel = if (-not $dnsFail) { 'Info' } else { 'Warning' }
        $reachText  = if ($dnsFail) {
            'DNS resolution failed for {0}' -f $target
        } elseif ($pingOk) {
            'Reachable'
        } else {
            'DNS resolved, no ping reply (may be ICMP-blocked)'
        }
        Write-ToolOutput ('Service reachability ({0}): {1}' -f $target, $reachText) -Level $reachLevel

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if (-not $process)           { $issues.Add('app not running') }
        if (-not $audioDevice)       { $issues.Add('no working audio device') }
        if ($logErrors.Count -gt 0)  { $issues.Add('{0} recent log error(s)' -f $logErrors.Count) }
        if (-not $logChecked)        { $issues.Add('log location not confirmed for legacy Glip-branded install') }
        if ($dnsFail)                { $issues.Add('service unreachable (DNS failure)') }

        $verdict = if ($issues.Count -eq 0) {
            'Installed and running, audio device present, no recent errors'
        } else {
            'Issues: ' + ($issues -join '; ')
        }
        Write-ToolOutput ('Verdict: {0}' -f $verdict) -Level Info

        $status = if ($issues.Count -eq 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status -Summary $verdict
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
