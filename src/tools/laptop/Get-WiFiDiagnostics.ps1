function Get-WiFiDiagnostics {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'wifi-diagnostics'

        # --- Adapter discovery ---
        $wifiAdapter = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless' -or $_.Name -match 'Wi-Fi|Wireless' } |
            Select-Object -First 1

        if (-not $wifiAdapter) {
            Write-ToolOutput 'No Wi-Fi adapter found' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'No Wi-Fi adapter found'
            return
        }

        Write-ToolOutput ('Adapter : {0}' -f $wifiAdapter.InterfaceDescription)
        Write-ToolOutput ('Status  : {0}  Speed: {1}' -f $wifiAdapter.Status, $wifiAdapter.LinkSpeed)

        # --- Current connection details ---
        $ifaceLines = @(netsh wlan show interfaces 2>&1 | ForEach-Object { $_.ToString() })
        $ssid    = ''
        $signal  = ''
        $radio   = ''
        $channel = ''
        foreach ($ln in $ifaceLines) {
            if ($ln -match '^\s+SSID\s*:\s*(.+)$')       { $ssid    = $Matches[1].Trim() }
            if ($ln -match '^\s+Signal\s*:\s*(.+)$')     { $signal  = $Matches[1].Trim() }
            if ($ln -match '^\s+Radio type\s*:\s*(.+)$') { $radio   = $Matches[1].Trim() }
            if ($ln -match '^\s+Channel\s*:\s*(.+)$')    { $channel = $Matches[1].Trim() }
        }

        if ($ssid) {
            Write-ToolOutput ('Connected : {0}' -f $ssid)
            Write-ToolOutput ('Signal: {0}  Radio: {1}  Channel: {2}' -f $signal, $radio, $channel) -Level Detail
        } else {
            Write-ToolOutput 'Not currently connected to a Wi-Fi network' -Level Warning
        }

        # --- Saved profiles ---
        $profileLines = @(netsh wlan show profiles 2>&1 | ForEach-Object { $_.ToString() })
        $savedProfiles = @()
        foreach ($ln in $profileLines) {
            if ($ln -match 'All User Profile\s*:\s*(.+)') {
                $savedProfiles += $Matches[1].Trim()
            }
        }
        Write-ToolOutput ('{0} saved Wi-Fi profile(s)' -f $savedProfiles.Count)
        foreach ($p in $savedProfiles) {
            Write-ToolOutput ('  - {0}' -f $p) -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice `
            -Prompt 'Wi-Fi action' `
            -Choices @('None', 'RestartAdapter', 'ForgetCurrent', 'ForgetAll', 'Report') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'RestartAdapter' {
                Write-ToolOutput ('Restarting adapter: {0}' -f $wifiAdapter.Name) -Level Info
                Restart-NetAdapter -Name $wifiAdapter.Name -Confirm:$false
                Write-ToolOutput 'Adapter restart complete' -Level Success
                Complete-ToolRun $run -Status Success -Summary ('Adapter {0} restarted' -f $wifiAdapter.Name)
            }
            'ForgetCurrent' {
                if (-not $ssid) {
                    Write-ToolOutput 'No current SSID to forget - not connected' -Level Warning
                    Complete-ToolRun $run -Status Warning -Summary 'ForgetCurrent: not connected to any network'
                } else {
                    Write-ToolOutput ('Forgetting network: {0}' -f $ssid) -Level Info
                    netsh wlan delete profile name="$ssid" 2>&1 | Out-Null
                    Write-ToolOutput 'Profile deleted. Reconnect manually.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary ('Forgot Wi-Fi profile: {0}' -f $ssid)
                }
            }
            'ForgetAll' {
                $gate = Read-ToolChoice `
                    -Prompt 'Delete ALL saved Wi-Fi profiles? This removes all Wi-Fi credentials. Type CONFIRM to proceed' `
                    -Choices @('CONFIRM', 'Cancel') `
                    -Default 'Cancel' `
                    -Silent:$Silent
                if ($gate -eq 'CONFIRM') {
                    Write-ToolOutput 'Deleting all saved Wi-Fi profiles...' -Level Info
                    netsh wlan delete profile name=* i=* 2>&1 | Out-Null
                    Write-ToolOutput 'All profiles deleted. You must reconnect and re-enter passwords.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'All Wi-Fi profiles deleted'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'ForgetAll cancelled by user'
                }
            }
            'Report' {
                Write-ToolOutput 'Generating WLAN report...' -Level Info
                netsh wlan show wlanreport 2>&1 | Out-Null
                Write-ToolOutput 'Report: C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html' -Level Success
                Complete-ToolRun $run -Status Success -Summary 'WLAN report generated'
            }
            default {
                if ($ssid) {
                    Complete-ToolRun $run -Status Success `
                        -Summary ('Adapter Up; Connected to {0} ({1}); {2} profile(s) saved' -f $ssid, $signal, $savedProfiles.Count)
                } else {
                    Complete-ToolRun $run -Status Warning `
                        -Summary ('Adapter {0}; Not connected; {1} profile(s) saved' -f $wifiAdapter.Status, $savedProfiles.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
