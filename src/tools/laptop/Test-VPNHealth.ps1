function Test-VPNHealth {
    [CmdletBinding()]
    param([switch]$Silent)

    # Timeout-bounded TCP probe - avoids hangs when VPN is up but internet is blocked.
    function Test-TcpEndpoint {
        param([string]$HostName, [int]$Port, [int]$TimeoutMs = 3000)
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $null
        try {
            $iar = $client.BeginConnect($HostName, $Port, $null, $null)
            $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok) {
                try { $client.EndConnect($iar) } catch { }
                return $client.Connected
            }
            return $false
        } catch {
            return $false
        } finally {
            if ($iar -and $iar.AsyncWaitHandle) { $iar.AsyncWaitHandle.Dispose() }
            $client.Close()
        }
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'vpn-health'

        # Gate the WHOLE tool, not just the phonebook action. Get-VpnConnection
        # without -AllUserConnection returns the CALLING account's profiles, and
        # rasdial connects/disconnects in the calling session - so under
        # redirection every line of this tool describes and acts on the
        # technician's VPN. The "no profiles configured" early return below would
        # otherwise skip a guard placed further down.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx
        if ($ctx.IsRedirected) {
            Write-ToolOutput ('VPN profiles and rasdial are per-session: this would report and act on {0}, not {1}.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Error
            Complete-ToolRun $run -Status Failed `
                -Summary ('VPN health refused - profiles belong to {0}, not {1}. Nothing was changed.' -f $ctx.ProcessName, $ctx.DisplayName)
            return
        }
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot read VPN health - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $vpnConnections = @(Get-VpnConnection -ErrorAction SilentlyContinue)

        if ($vpnConnections.Count -eq 0) {
            Write-ToolOutput 'No Windows VPN profiles configured' -Level Warning
            Write-ToolOutput 'Note: third-party VPN clients (Cisco AnyConnect, GlobalProtect, etc.) must be managed through their own applications.' -Level Detail
            Complete-ToolRun $run -Status Warning -Summary 'No Windows VPN profiles configured'
            return
        }

        # --- Report all profiles ---
        Write-ToolOutput ('{0} VPN profile(s) found' -f $vpnConnections.Count)
        $connectedVPN = $null
        foreach ($vpn in $vpnConnections) {
            Write-ToolOutput ('  Name: {0}  Status: {1}  Server: {2}' -f $vpn.Name, $vpn.ConnectionStatus, $vpn.ServerAddress) -Level Detail
            if ($vpn.ConnectionStatus -eq 'Connected') { $connectedVPN = $vpn }
        }

        # --- Reachability tests (only when a VPN is active) ---
        $endpoints = @(
            [PSCustomObject]@{ Label = '8.8.8.8:53 (Google DNS)';     Host = '8.8.8.8'; Port = 53 }
            [PSCustomObject]@{ Label = '1.1.1.1:53 (Cloudflare DNS)'; Host = '1.1.1.1'; Port = 53 }
        )
        $reachableCount = 0

        if ($connectedVPN) {
            Write-ToolOutput ('Connected via: {0}' -f $connectedVPN.Name)
            Write-ToolOutput 'Testing internet reachability (3s timeout each)...'
            foreach ($ep in $endpoints) {
                $ok = Test-TcpEndpoint -HostName $ep.Host -Port $ep.Port -TimeoutMs 3000
                if ($ok) {
                    Write-ToolOutput ('{0} : Reachable' -f $ep.Label) -Level Detail
                    $reachableCount++
                } else {
                    Write-ToolOutput ('{0} : Unreachable' -f $ep.Label) -Level Warning
                }
            }
        } else {
            Write-ToolOutput 'No active VPN connection - reachability test skipped' -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice `
            -Prompt 'VPN action' `
            -Choices @('None', 'Reconnect', 'Disconnect', 'ClearPhonebook') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'Reconnect' {
                $vpnName = $vpnConnections[0].Name
                if ($connectedVPN) { $vpnName = $connectedVPN.Name }
                if ($connectedVPN) {
                    Write-ToolOutput ('Disconnecting {0}...' -f $vpnName) -Level Info
                    rasdial $vpnName /disconnect 2>&1 | Out-Null
                    Start-Sleep -Seconds 2
                }
                Write-ToolOutput ('Connecting {0}...' -f $vpnName) -Level Info
                rasdial $vpnName 2>&1 | Out-Null
                Write-ToolOutput 'Reconnect initiated' -Level Success
                Complete-ToolRun $run -Status Success -Summary ('VPN reconnect initiated: {0}' -f $vpnName)
            }
            'Disconnect' {
                if ($connectedVPN) {
                    Write-ToolOutput ('Disconnecting {0}...' -f $connectedVPN.Name) -Level Info
                    rasdial $connectedVPN.Name /disconnect 2>&1 | Out-Null
                    Write-ToolOutput 'VPN disconnected' -Level Success
                    Complete-ToolRun $run -Status Success -Summary ('VPN disconnected: {0}' -f $connectedVPN.Name)
                } else {
                    Write-ToolOutput 'No active VPN connection to disconnect' -Level Warning
                    Complete-ToolRun $run -Status Skipped -Summary 'Disconnect: no active VPN connection'
                }
            }
            'ClearPhonebook' {
                # The RAS phonebook is per-user; the DNS flush below is not.
                $ctx = Get-TargetUserContext
                Write-UserContextNotice -Context $ctx
                if (-not $ctx.Resolved) {
                    Complete-ToolRun $run -Status Failed `
                        -Summary ('Cannot clear the VPN phonebook - {0}. Nothing was changed.' -f $ctx.Reason)
                    return
                }
                $pbkPath = Join-Path $ctx.AppData 'Microsoft\Network\Connections\Pbk'
                $gate = Read-ToolChoice `
                    -Prompt 'Clear VPN phonebook? Deletes saved VPN connection files and flushes DNS. Type CONFIRM to proceed' `
                    -Choices @('CONFIRM', 'Cancel') `
                    -Default 'Cancel' `
                    -Silent:$Silent
                if ($gate -eq 'CONFIRM') {
                    Write-ToolOutput ('Clearing VPN phonebook: {0}' -f $pbkPath) -Level Info
                    if (Test-Path $pbkPath) {
                        # Containment-gated: the phonebook directory lives under
                        # the target user's AppData and is fully writable by them.
                        [void](Remove-UserPathContent -Context $ctx -Path $pbkPath)
                    }
                    ipconfig /flushdns 2>&1 | Out-Null
                    Write-ToolOutput 'Phonebook cleared and DNS flushed' -Level Success
                    Complete-ToolRun $run -Status Success -Summary 'VPN phonebook cleared and DNS flushed'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearPhonebook cancelled by user'
                }
            }
            default {
                if ($connectedVPN) {
                    $reachStr = '{0}/{1} reachable' -f $reachableCount, $endpoints.Count
                    if ($reachableCount -lt $endpoints.Count) {
                        Complete-ToolRun $run -Status Warning `
                            -Summary ('{0} VPN profile(s); connected: {1}; internet {2}' -f $vpnConnections.Count, $connectedVPN.Name, $reachStr)
                    } else {
                        Complete-ToolRun $run -Status Success `
                            -Summary ('{0} VPN profile(s); connected: {1}; internet {2}' -f $vpnConnections.Count, $connectedVPN.Name, $reachStr)
                    }
                } else {
                    Complete-ToolRun $run -Status Warning `
                        -Summary ('{0} VPN profile(s) found; none connected' -f $vpnConnections.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
