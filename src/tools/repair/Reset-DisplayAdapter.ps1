function Reset-DisplayAdapter {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'display-adapter-reset'

        $choice = Read-ToolChoice `
            -Prompt 'Reset display adapter? (screen will flicker/black out briefly)' `
            -Choices @('Yes', 'No') `
            -Default 'No' `
            -Silent:$Silent

        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined display adapter reset'
            return
        }

        Write-ToolOutput 'Querying display adapters (Status OK)...' -Level Info
        $adapters = @(Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue)

        if (-not $adapters -or $adapters.Count -eq 0) {
            Complete-ToolRun $run -Status Warning `
                -Summary 'No OK-status display adapters found; nothing to reset'
            return
        }

        foreach ($a in $adapters) {
            Write-ToolOutput ('  Found: {0}' -f $a.FriendlyName) -Level Info
        }

        # Disable each adapter (screen will flicker/black out briefly)
        Write-ToolOutput 'Disabling display adapter(s)...' -Level Info
        foreach ($a in $adapters) {
            Disable-PnpDevice -InstanceId $a.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Write-ToolOutput ('  Disabled: {0}' -f $a.FriendlyName) -Level Detail
        }

        Start-Sleep -Seconds 2

        # Re-enable each adapter
        Write-ToolOutput 'Re-enabling display adapter(s)...' -Level Info
        foreach ($a in $adapters) {
            Enable-PnpDevice -InstanceId $a.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            Write-ToolOutput ('  Enabled: {0}' -f $a.FriendlyName) -Level Detail
        }

        $names = ($adapters | ForEach-Object { $_.FriendlyName }) -join '; '
        Complete-ToolRun $run -Status Success `
            -Summary ('Display adapter reset (driver store unchanged): {0}' -f $names)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
