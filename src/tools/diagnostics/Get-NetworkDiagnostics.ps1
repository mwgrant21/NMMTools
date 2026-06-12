function Get-NetworkDiagnostics {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'network-diagnostics'

        $adapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            $config = Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex `
                -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $ipStr = if ($config -and $config.IPAddress) { $config.IPAddress -join ', ' } else { '(none)' }
            [PSCustomObject]@{
                Name      = $_.Name
                Status    = $_.Status
                LinkSpeed = $_.LinkSpeed
                IPAddress = $ipStr
            }
        })

        if ($adapters.Count -eq 0) {
            Write-ToolOutput 'No active (Up) network adapters found.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'No active adapters detected'
            return
        }

        foreach ($a in $adapters) {
            Write-ToolOutput ('{0}  [{1}]  {2}  IP: {3}' -f
                $a.Name, $a.Status, $a.LinkSpeed, $a.IPAddress) -Level Detail
        }

        $names = ($adapters | ForEach-Object { $_.Name }) -join ', '
        Complete-ToolRun $run -Status Success -Summary (
            '{0} active adapter(s): {1}' -f $adapters.Count, $names)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
