function Set-RemoteDesktop {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'rdp-config'
        $tsKey  = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
        $rdpKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

        # --- Report ---
        $deny = (Get-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
        if ($deny -eq 0) { Write-ToolOutput 'Remote Desktop: ENABLED (fDenyTSConnections=0)' -Level Info }
        else { Write-ToolOutput 'Remote Desktop: disabled (fDenyTSConnections=1)' -Level Info }
        $nla = (Get-ItemProperty -LiteralPath $rdpKey -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
        Write-ToolOutput ('NLA (UserAuthentication): {0}' -f $nla) -Level Detail
        $fw = @(Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue)
        $fwEnabled = @($fw | Where-Object { $_.Enabled -eq 'True' }).Count
        Write-ToolOutput ('Remote Desktop firewall rules enabled: {0} of {1}' -f $fwEnabled, $fw.Count) -Level Detail
        $svc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
        if ($svc) { Write-ToolOutput ('TermService: {0} (StartType {1})' -f $svc.Status, $svc.StartType) -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Remote Desktop action' -Choices @('None','Enable','Disable') -Default 'None' -Silent:$Silent

        switch ($action) {

            'Enable' {
                # Read-ToolChoice -ExactMatch: a bare Read-Host throws in the GUI's hostless
                # tool runspace (caught by the outer catch before any state change - fails
                # closed, but the feature silently can't be used from the default UI mode).
                # -ExactMatch also makes the comparison case-sensitive so 'enable' can't
                # satisfy an all-caps "type this exactly" gate the way plain -eq would.
                $typed = Read-ToolChoice -Prompt "Enabling RDP increases this machine's attack surface. Type ENABLE to proceed" `
                    -Choices @('ENABLE', 'Cancel') -Default 'Cancel' -Silent:$Silent -ExactMatch
                if ($typed -ne 'ENABLE') { Complete-ToolRun $run -Status Skipped -Summary 'Enable cancelled (confirmation not typed)'; return }
                Set-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -Value 0 -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $rdpKey -Name 'UserAuthentication' -Value 1 -Force -ErrorAction SilentlyContinue
                Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
                Set-Service -Name 'TermService' -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name 'TermService' -ErrorAction SilentlyContinue
                $now = (Get-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
                $nlaNow = (Get-ItemProperty -LiteralPath $rdpKey -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
                if ($now -eq 0 -and $nlaNow -eq 1) { Complete-ToolRun $run -Status Success -Summary 'Remote Desktop enabled (NLA on, firewall opened)' }
                elseif ($now -eq 0) { Complete-ToolRun $run -Status Warning -Summary 'Remote Desktop enabled but NLA (UserAuthentication) did not verify as on' }
                else { Complete-ToolRun $run -Status Warning -Summary 'fDenyTSConnections did not update to 0' }
            }

            'Disable' {
                Set-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -Value 1 -Force -ErrorAction SilentlyContinue
                Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
                $now = (Get-ItemProperty -LiteralPath $tsKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
                if ($now -eq 1) { Complete-ToolRun $run -Status Success -Summary 'Remote Desktop disabled (firewall group disabled)' }
                else { Complete-ToolRun $run -Status Warning -Summary 'fDenyTSConnections did not update to 1' }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Remote Desktop state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
