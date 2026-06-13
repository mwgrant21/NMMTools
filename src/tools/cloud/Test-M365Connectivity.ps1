function Test-M365Connectivity {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    # Reusable timeout-bounded TCP probe pattern for network tools.
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
        $run = New-ToolRun -Id 'm365-connectivity'

        # v8 endpoint list preserved exactly
        $endpoints = @(
            [PSCustomObject]@{ Name = 'Azure AD';   Host = 'login.microsoftonline.com'; Port = 443 }
            [PSCustomObject]@{ Name = 'Office 365'; Host = 'outlook.office365.com';    Port = 443 }
            [PSCustomObject]@{ Name = 'OneDrive';   Host = 'onedrive.live.com';         Port = 443 }
            [PSCustomObject]@{ Name = 'Teams';      Host = 'teams.microsoft.com';       Port = 443 }
        )

        Write-ToolOutput ('Testing {0} M365 endpoints (3s timeout each)...' -f $endpoints.Count)

        $reachableCount   = 0
        $unreachableNames = @()

        foreach ($ep in $endpoints) {
            # Detail = reachable; Warning = unreachable (per playbook level-intent convention)
            $connected = Test-TcpEndpoint -HostName $ep.Host -Port $ep.Port -TimeoutMs 3000
            if ($connected) {
                Write-ToolOutput ('{0,-14} ({1}) : Reachable'   -f $ep.Name, $ep.Host) -Level Detail
                $reachableCount++
            } else {
                Write-ToolOutput ('{0,-14} ({1}) : Unreachable' -f $ep.Name, $ep.Host) -Level Warning
                $unreachableNames += $ep.Name
            }
        }

        if ($unreachableNames.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary ('{0}/{1} endpoints reachable' -f $reachableCount, $endpoints.Count)
        } else {
            Complete-ToolRun $run -Status Warning -Summary (
                '{0}/{1} reachable; unreachable: {2}' -f $reachableCount, $endpoints.Count, ($unreachableNames -join ', '))
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
