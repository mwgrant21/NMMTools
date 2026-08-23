function Repair-ProxySettings {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'proxy-reset'

        Write-ToolOutput 'Resets WinHTTP and WinINET proxy to direct, clears PAC/WPAD auto-config, flushes DNS, and resets Winsock.' -Level Info
        Write-ToolOutput 'Warning: connectivity drops until reboot. In a PAC/WPAD-managed environment, proxy is cleared until GPO re-applies.' -Level Warning

        $choice = Read-ToolChoice `
            -Prompt 'Reset WinHTTP + WinINET proxy, flush DNS, and reset Winsock? (reboot required to finish Winsock reset)' `
            -Choices @('Yes', 'No') `
            -Default 'No' `
            -Silent:$Silent

        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined proxy settings reset'
            return
        }

        # Step 1: WinHTTP proxy reset
        Write-ToolOutput 'Resetting WinHTTP proxy to DIRECT...' -Level Info
        $httpLines = @(& netsh winhttp reset proxy 2>&1)
        foreach ($line in $httpLines) {
            $text = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                Write-ToolOutput ('  {0}' -f $text) -Level Detail
            }
        }

        # Step 2: WinINET proxy registry (per-user - HKCU interactively, or the logged-on
        # user's hive when running as SYSTEM/PDQ, where HKCU: would otherwise silently target
        # the SYSTEM profile and leave this half of the fix un-applied while still reporting
        # Success).
        $winInetApplied = $false
        $hive = Resolve-NmmUserRegistryHive
        if (-not $hive.Root) {
            Write-ToolOutput ('WinINET proxy keys not cleared: {0}' -f $hive.Reason) -Level Warning
        } else {
            Write-ToolOutput ('Clearing WinINET proxy registry keys ({0})...' -f $hive.Root) -Level Info
            $regPath = '{0}\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -f $hive.Root
            Set-ItemProperty    -Path $regPath -Name ProxyEnable   -Value 0 -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $regPath -Name ProxyServer    -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $regPath -Name ProxyOverride  -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $regPath -Name AutoConfigURL  -ErrorAction SilentlyContinue
            Write-ToolOutput 'WinINET: ProxyEnable=0; ProxyServer/ProxyOverride/AutoConfigURL removed.' -Level Info
            $winInetApplied = $true
        }

        # Step 3: Flush DNS
        Write-ToolOutput 'Flushing DNS cache...' -Level Info
        & ipconfig /flushdns 2>&1 | Out-Null
        Write-ToolOutput 'DNS cache flushed.' -Level Info

        # Step 4: Winsock reset (requires reboot to take full effect)
        Write-ToolOutput 'Resetting Winsock catalog (REBOOT required to take effect)...' -Level Info
        & netsh winsock reset 2>&1 | Out-Null
        Write-ToolOutput 'Winsock reset queued.' -Level Info

        if ($winInetApplied) {
            Complete-ToolRun $run -Status Success `
                -Summary 'WinHTTP + WinINET proxy reset; DNS flushed; Winsock reset - REBOOT required to finish'
        } else {
            Complete-ToolRun $run -Status Warning `
                -Summary ('WinHTTP proxy reset; DNS flushed; Winsock reset (REBOOT required); WinINET NOT reset - {0}' -f $hive.Reason)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
