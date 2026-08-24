function Invoke-VpnQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'vpn-quick-fix'

        Write-ToolOutput 'VPN quick fix will: disconnect active VPNs, flush DNS, and clear the ARP cache. Your VPN profiles are NOT deleted.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the VPN quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'VPN quick fix declined'
            return
        }

        $vpns = @(Get-VpnConnection -ErrorAction SilentlyContinue)
        $disconnected = 0
        foreach ($v in $vpns) {
            rasdial $v.Name /disconnect 2>$null | Out-Null
            $disconnected++
        }
        ipconfig /flushdns 2>$null | Out-Null
        netsh interface ip delete arpcache 2>$null | Out-Null

        Complete-ToolRun $run -Status Success -Summary ('{0} VPN connection(s) disconnected; DNS flushed; ARP cache cleared' -f $disconnected)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
