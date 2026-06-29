function Get-TeamsMeetingQuality {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-meeting-quality'

        # --- Active NIC detection ---
        $allUp = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
        $activeAdapter  = $null
        $adapterWarning = $false
        $adapterNote    = ''

        foreach ($a in $allUp) {
            if ($a.InterfaceDescription -match 'DisplayLink|USB.*Network|USB.*Ethernet') {
                $activeAdapter  = $a
                $adapterWarning = $true
                $adapterNote    = '[WARNING - shared USB bus]'
                break
            }
        }
        if (-not $activeAdapter) {
            # Prefer wired over WiFi
            $activeAdapter = $allUp | Where-Object {
                $_.InterfaceDescription -notmatch 'Wi-Fi|Wireless|802\.11|WiFi'
            } | Select-Object -First 1
        }
        if (-not $activeAdapter) {
            $activeAdapter = $allUp | Select-Object -First 1
        }

        $adapterLabel = if ($activeAdapter) {
            '{0} ({1})' -f $activeAdapter.Name, $activeAdapter.InterfaceDescription
        } else { 'None found' }
        $adapterLevel = if ($adapterWarning) { 'Warning' } else { 'Info' }
        Write-ToolOutput ('Network adapter: {0} {1}' -f $adapterLabel, $adapterNote) -Level $adapterLevel

        # --- Latency, jitter, packet loss to M365 ---
        $pingTargets = @('teams.microsoft.com', 'worldaz.tr.teams.microsoft.com')
        $allSamples  = New-Object System.Collections.Generic.List[double]
        $totalSent   = 0
        $totalLost   = 0

        foreach ($target in $pingTargets) {
            try {
                $results = @(Test-Connection -ComputerName $target -Count 5 -ErrorAction SilentlyContinue)
                $totalSent += 5
                foreach ($r in $results) {
                    # Win32_PingStatus (PS5.1): StatusCode=0 means success; ResponseTime holds ms
                    # PSPingStatus (PS7): Status='Success'; Latency holds ms
                    $isSuccess = $false
                    $ms        = $null
                    if ($r.PSObject.Properties.Name -contains 'StatusCode') {
                        $isSuccess = ($r.StatusCode -eq 0)
                        if ($isSuccess -and $r.PSObject.Properties.Name -contains 'ResponseTime') {
                            $ms = $r.ResponseTime
                        }
                    } elseif ($r.PSObject.Properties.Name -contains 'Status') {
                        $isSuccess = ($r.Status -eq 'Success')
                        if ($isSuccess -and $r.PSObject.Properties.Name -contains 'Latency') {
                            $ms = $r.Latency
                        }
                    }
                    if (-not $isSuccess) {
                        $totalLost++
                    } elseif ($null -ne $ms -and $ms -gt 0) {
                        $allSamples.Add([double]$ms)
                    }
                }
            } catch {
                $totalSent += 5
                $totalLost += 5
            }
        }

        $avgMs  = 0; $minMs = 0; $maxMs = 0; $jitter = 0
        if ($allSamples.Count -gt 0) {
            $measured = $allSamples | Measure-Object -Average -Minimum -Maximum
            $avgMs    = [math]::Round($measured.Average, 1)
            $minMs    = [math]::Round($measured.Minimum, 1)
            $maxMs    = [math]::Round($measured.Maximum, 1)
            if ($allSamples.Count -gt 1) {
                $variance = ($allSamples | ForEach-Object { [math]::Pow($_ - $avgMs, 2) } |
                             Measure-Object -Average).Average
                $jitter   = [math]::Round([math]::Sqrt($variance), 1)
            }
        }
        $lossRate = if ($totalSent -gt 0) { [math]::Round(($totalLost / $totalSent) * 100, 1) } else { 0 }

        $latLevel  = if ($avgMs -gt 80) { 'Warning' } else { 'Info' }
        $jitLevel  = if ($jitter -gt 30)  { 'Warning' } else { 'Info' }
        $lossLevel = if ($lossRate -gt 1) { 'Warning' } else { 'Info' }
        Write-ToolOutput ('Latency to M365: {0}ms avg (min {1} / max {2})' -f $avgMs, $minMs, $maxMs) -Level $latLevel
        Write-ToolOutput ('Jitter: {0}ms' -f $jitter) -Level $jitLevel
        Write-ToolOutput ('Packet loss: {0}%' -f $lossRate) -Level $lossLevel

        # --- DNS resolution time ---
        $dnsMs   = $null
        $dnsFail = $false
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            [System.Net.Dns]::GetHostAddresses('teams.microsoft.com') | Out-Null
            $sw.Stop()
            $dnsMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        } catch { $dnsFail = $true }
        $dnsText  = if ($dnsFail) { 'FAILED' } else { '{0}ms' -f $dnsMs }
        $dnsLevel = if ($dnsFail -or ($null -ne $dnsMs -and $dnsMs -gt 200)) { 'Warning' } else { 'Info' }
        Write-ToolOutput ('DNS (teams.microsoft.com): {0}' -f $dnsText) -Level $dnsLevel

        # --- VPN detection ---
        $vpnAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.InterfaceDescription -match 'VPN|Cisco|Palo|Juniper|GlobalProtect|Pulse|AnyConnect|WireGuard|OpenVPN' `
                -or $_.Name -match 'VPN'
        })
        $vpnActive = @($vpnAdapters | Where-Object { $_.Status -eq 'Up' })
        $vpnLevel  = if ($vpnActive.Count -gt 0) { 'Warning' } else { 'Info' }
        $vpnText   = if ($vpnActive.Count -gt 0) {
            'Active: {0} - check if Teams traffic is in full tunnel (full tunnel = latency contributor)' -f $vpnActive[0].Name
        } else { 'Not detected' }
        Write-ToolOutput ('VPN: {0}' -f $vpnText) -Level $vpnLevel

        # --- QoS/DSCP ---
        $qosKey        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS'
        $qosConfigured = $false
        if (Test-Path -LiteralPath $qosKey) {
            $teamsQos = @(Get-ChildItem -LiteralPath $qosKey -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match 'Teams|Lync|Skype' })
            $qosConfigured = $teamsQos.Count -gt 0
        }
        $qosLevel = if ($qosConfigured) { 'Info' } else { 'Warning' }
        Write-ToolOutput ('QoS/DSCP marking: {0}' -f (if ($qosConfigured) { 'Configured' } else { 'Not configured' })) `
            -Level $qosLevel

        # --- Hardware video encoder ---
        $gpus      = @(Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue)
        $hwEncoder = 'None (CPU fallback)'
        $hwLevel   = 'Warning'
        foreach ($gpu in $gpus) {
            if ($gpu.Name -match 'Intel')          { $hwEncoder = 'Intel Quick Sync available'; $hwLevel = 'Info'; break }
            if ($gpu.Name -match 'NVIDIA')         { $hwEncoder = 'NVIDIA NVENC available';    $hwLevel = 'Info'; break }
            if ($gpu.Name -match 'AMD|Radeon|ATI') { $hwEncoder = 'AMD VCE available';         $hwLevel = 'Info'; break }
        }
        Write-ToolOutput ('Hardware video encoder: {0}' -f $hwEncoder) -Level $hwLevel

        # --- CPU / RAM snapshot ---
        $cpuLoad   = ([math]::Round((Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue |
                       Measure-Object LoadPercentage -Average).Average, 0))
        $os        = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
        $freeRamGB = if ($os) { [math]::Round($os.FreePhysicalMemory / 1MB, 1) } else { $null }
        $cpuLevel  = if ($cpuLoad -gt 80) { 'Warning' } else { 'Info' }
        Write-ToolOutput ('CPU: {0}%' -f $cpuLoad) -Level $cpuLevel
        if ($null -ne $freeRamGB) {
            $ramLevel = if ($freeRamGB -lt 2) { 'Warning' } else { 'Info' }
            Write-ToolOutput ('Free RAM: {0}GB' -f $freeRamGB) -Level $ramLevel
        }

        # --- Teams log sampling ---
        $teamsLogPaths = @(
            (Join-Path $env:APPDATA 'Microsoft\Teams\logs.txt'),
            (Join-Path $env:LOCALAPPDATA `
                'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\logs.txt')
        )
        $qualityEvents = New-Object System.Collections.Generic.List[string]
        foreach ($logPath in $teamsLogPaths) {
            if (Test-Path -LiteralPath $logPath) {
                try {
                    $tail = Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue |
                            Select-Object -Last 500
                    $hits = @($tail | Where-Object {
                        $_ -match 'packet.loss|codec.switch|bandwidth.drop|video.fail|call.quality'
                    })
                    foreach ($h in ($hits | Select-Object -Last 5)) {
                        $qualityEvents.Add($h.Trim())
                    }
                } catch { }
                break
            }
        }
        if ($qualityEvents.Count -gt 0) {
            Write-ToolOutput ('Teams log quality events (last {0}):' -f $qualityEvents.Count) -Level Warning
            foreach ($e in $qualityEvents) { Write-ToolOutput ('  {0}' -f $e) -Level Detail }
        } else {
            Write-ToolOutput 'Teams log: no recent quality events found' -Level Detail
        }

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if ($adapterWarning)          { $issues.Add('DisplayLink USB NIC') }
        if ($jitter -gt 30)           { $issues.Add('high jitter ({0}ms)' -f $jitter) }
        if ($avgMs -gt 80)            { $issues.Add('high latency ({0}ms avg)' -f $avgMs) }
        if ($lossRate -gt 1)          { $issues.Add('packet loss ({0}%)' -f $lossRate) }
        if ($dnsFail)                 { $issues.Add('DNS resolution failed') }
        if ($vpnActive.Count -gt 0)   { $issues.Add('VPN active (full tunnel risk)') }
        if (-not $qosConfigured)      { $issues.Add('QoS not configured') }
        if ($hwEncoder -match 'None') { $issues.Add('no hardware video encoder') }

        $verdict = if ($issues.Count -eq 0) {
            'No significant issues detected'
        } else {
            'Top issues: ' + ($issues -join '; ')
        }
        Write-ToolOutput ('Verdict: {0}' -f $verdict) -Level Info

        Complete-ToolRun $run -Status Success -Summary $verdict
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
