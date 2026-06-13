function Test-NetworkConnectivity {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'network-connectivity'

        $targets = @(
            [PSCustomObject]@{ Name = 'Google DNS';     Address = '8.8.8.8'       }
            [PSCustomObject]@{ Name = 'Cloudflare DNS'; Address = '1.1.1.1'       }
            [PSCustomObject]@{ Name = 'Microsoft';      Address = 'microsoft.com'  }
        )

        Write-ToolOutput ('Testing {0} targets...' -f $targets.Count)

        # PS 5.1 uses ResponseTime; PS 6+ uses Latency — keep v8 version check for forward compat
        $responseTimeProp = if ($PSVersionTable.PSVersion.Major -ge 6) { 'Latency' } else { 'ResponseTime' }

        $reachableCount = 0
        $failedNames    = @()

        # Ping results use Detail for reachable targets, Warning for unreachable
        foreach ($target in $targets) {
            $ping = Test-Connection -ComputerName $target.Address -Count 2 -ErrorAction SilentlyContinue
            if ($ping) {
                $avgMs = [math]::Round(
                    ($ping | Select-Object -ExpandProperty $responseTimeProp |
                        Measure-Object -Average).Average, 2)
                Write-ToolOutput ('{0,-20}  OK — {1}ms' -f $target.Name, $avgMs) -Level Detail
                $reachableCount++
            } else {
                Write-ToolOutput ('{0,-20}  FAILED' -f $target.Name) -Level Warning
                $failedNames += $target.Name
            }
        }

        if ($failedNames.Count -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary (
                '{0}/{1} reachable; failed: {2}' -f
                $reachableCount, $targets.Count, ($failedNames -join ', '))
        } else {
            Complete-ToolRun $run -Status Success -Summary (
                '{0}/{1} targets reachable' -f $reachableCount, $targets.Count)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
