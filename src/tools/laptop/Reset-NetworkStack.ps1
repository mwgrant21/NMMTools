function Reset-NetworkStack {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'network-stack-reset'

        Write-ToolOutput 'Operations: flush DNS cache + winsock reset + TCP/IP stack reset + cycle all active adapters.' -Level Detail
        Write-ToolOutput 'Active connections will drop. A reboot is required to complete the reset.'

        $gate = Read-ToolChoice `
            -Prompt 'This resets winsock/TCP-IP and cycles all network adapters (drops connections; reboot to finish). Type RESET to proceed' `
            -Choices @('RESET', 'Cancel') `
            -Default 'Cancel' `
            -Silent:$Silent

        if ($gate -ne 'RESET') {
            Complete-ToolRun $run -Status Skipped -Summary 'Network stack reset cancelled'
            return
        }

        Write-ToolOutput 'Step 1: Flushing DNS cache...' -Level Info
        ipconfig /flushdns 2>&1 | Out-Null
        Write-ToolOutput '  DNS cache flushed' -Level Detail

        Write-ToolOutput 'Step 2: Resetting Winsock...' -Level Info
        netsh winsock reset 2>&1 | Out-Null
        Write-ToolOutput '  Winsock reset' -Level Detail

        Write-ToolOutput 'Step 3: Resetting TCP/IP stack...' -Level Info
        netsh int ip reset 2>&1 | Out-Null
        Write-ToolOutput '  TCP/IP stack reset' -Level Detail

        Write-ToolOutput 'Step 4: Cycling active network adapters...' -Level Info
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
        foreach ($adapter in $adapters) {
            Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Write-ToolOutput ('  Cycled: {0}' -f $adapter.Name) -Level Detail
        }

        Write-ToolOutput 'Network stack reset complete. REBOOT REQUIRED to finish.' -Level Success
        Complete-ToolRun $run -Status Success `
            -Summary ('Network stack reset: DNS flushed, winsock reset, TCP/IP reset, {0} adapter(s) cycled; REBOOT required' -f $adapters.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
