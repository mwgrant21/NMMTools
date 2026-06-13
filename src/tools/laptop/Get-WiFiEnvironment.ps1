function Get-WiFiEnvironment {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'wifi-environment'

        # Passive scan via netsh - no association or traffic changes
        $raw = netsh wlan show networks mode=bssid 2>&1

        $rawText = $raw -join "`n"

        if ($rawText -match 'There is no wireless interface' -or
            $rawText -match 'is not running' -or
            $rawText -match 'not found' -or
            $rawText -match 'hosted network') {
            # No adapter or adapter disabled
        }

        # Check for no-adapter / WLAN service not running
        if ($rawText -match 'There is no wireless interface' -or
            ($rawText -match 'The Wireless LAN') -or
            ($rawText -notmatch 'SSID')) {
            # Distinguish: is it "no adapter" or "no networks visible"?
            if ($rawText -match 'There is no wireless interface' -or
                $rawText -match 'not running' -or
                $rawText -match 'WLAN AutoConfig') {
                Complete-ToolRun $run -Status Warning -Summary 'No Wi-Fi adapter or WLAN service not running'
                return
            }
        }

        # Parse SSID blocks
        $lines        = $rawText -split "`n"
        $networkCount = 0
        $currentSSID  = ''
        $parsed       = @()
        $currentNet   = $null

        foreach ($line in $lines) {
            $line = $line.TrimEnd()
            if ($line -match '^SSID\s+\d+\s*:\s*(.+)') {
                if ($currentNet) { $parsed += $currentNet }
                $currentSSID = $Matches[1].Trim()
                $networkCount++
                $currentNet = [PSCustomObject]@{
                    SSID      = $currentSSID
                    Signal    = $null
                    RadioType = $null
                    Channel   = $null
                }
            } elseif ($line -match 'Signal\s*:\s*(\d+)%') {
                if ($currentNet) { $currentNet.Signal = [int]$Matches[1] }
            } elseif ($line -match 'Radio type\s*:\s*(.+)') {
                if ($currentNet) { $currentNet.RadioType = $Matches[1].Trim() }
            } elseif ($line -match 'Channel\s*:\s*(\d+)') {
                if ($currentNet) { $currentNet.Channel = [int]$Matches[1] }
            }
        }
        if ($currentNet) { $parsed += $currentNet }
        $networkCount = $parsed.Count

        if ($networkCount -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No Wi-Fi adapter or no networks visible'
            return
        }

        # Network list headline; detail rows follow
        Write-ToolOutput ('{0} Wi-Fi network(s) found' -f $networkCount)

        # Each network row at Detail level
        foreach ($net in $parsed) {
            $sigStr  = if ($null -ne $net.Signal) { '{0}%' -f $net.Signal } else { 'N/A' }
            $chanStr = if ($null -ne $net.Channel) { 'ch{0}' -f $net.Channel } else { '' }
            $radioStr = if ($net.RadioType) { $net.RadioType } else { '' }
            $detail  = '  {0}  Signal:{1}  {2}  {3}' -f $net.SSID, $sigStr, $chanStr, $radioStr
            Write-ToolOutput $detail.TrimEnd() -Level Detail
        }

        # Congestion flag
        $congested = $networkCount -gt 10
        if ($congested) {
            Write-ToolOutput ('High network density ({0} networks) - possible channel congestion' -f $networkCount) -Level Warning
        }

        if ($congested) {
            Complete-ToolRun $run -Status Warning -Summary ('{0} networks found; channel congestion possible' -f $networkCount)
        } else {
            Complete-ToolRun $run -Status Success -Summary ('{0} network(s) found' -f $networkCount)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
