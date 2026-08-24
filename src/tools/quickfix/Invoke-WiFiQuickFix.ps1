function Invoke-WiFiQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'wifi-quick-fix'

        Write-ToolOutput 'Wi-Fi quick fix will: restart the Wi-Fi adapter, release/renew the IP address, and flush DNS. Connectivity drops briefly.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the Wi-Fi quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Wi-Fi quick fix declined'
            return
        }

        $wifi = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*Wi-Fi*' -or $_.Name -like '*Wireless*' } | Select-Object -First 1
        $adapterReset = $false
        if ($wifi) {
            Restart-NetAdapter -Name $wifi.Name -Confirm:$false -ErrorAction SilentlyContinue
            $adapterReset = $true
            Start-Sleep -Seconds 3
        } else {
            Write-ToolOutput 'No Wi-Fi/Wireless adapter found; skipping adapter reset.' -Level Warning
        }

        ipconfig /release 2>$null | Out-Null
        ipconfig /renew 2>$null | Out-Null
        ipconfig /flushdns 2>$null | Out-Null

        if ($adapterReset) {
            Complete-ToolRun $run -Status Success -Summary 'Wi-Fi adapter reset; IP renewed; DNS flushed'
        } else {
            Complete-ToolRun $run -Status Warning -Summary 'No Wi-Fi adapter found; IP renewed and DNS flushed only'
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
