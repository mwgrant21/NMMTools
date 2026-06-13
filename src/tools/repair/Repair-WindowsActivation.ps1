function Repair-WindowsActivation {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-activation'

        $lic = Get-CimInstance -ClassName SoftwareLicensingProduct `
            -Filter "Name LIKE 'Windows%' AND PartialProductKey IS NOT NULL" `
            -ErrorAction Stop | Select-Object -First 1

        if (-not $lic) {
            Complete-ToolRun $run -Status Warning -Summary 'No Windows licensing product with a partial key found; activation state unknown'
            return
        }

        $statusMap = @{
            0 = 'Unlicensed'
            1 = 'Licensed'
            2 = 'Out-Of-Box Grace Period'
            3 = 'Out-Of-Tolerance Grace Period'
            4 = 'Non-Genuine Grace Period'
            5 = 'Notification'
            6 = 'Extended Grace Period'
        }
        $licStatus = [int]$lic.LicenseStatus
        $statusText = if ($statusMap.ContainsKey($licStatus)) { $statusMap[$licStatus] } else { ('Unknown ({0})' -f $licStatus) }

        # Info headline: product name and license status before detail rows
        Write-ToolOutput ('{0}  Status: {1}' -f $lic.Name, $statusText)

        # License detail rows: partial key, grace period, KMS info
        Write-ToolOutput ('  Partial Key   : {0}' -f $lic.PartialProductKey) -Level Detail
        if ($lic.GracePeriodRemaining -gt 0) {
            $days = [math]::Round($lic.GracePeriodRemaining / 1440, 1)
            Write-ToolOutput ('  Grace Period  : {0} day(s) remaining' -f $days) -Level Detail
        }
        if ($lic.KeyManagementServiceMachine) {
            Write-ToolOutput ('  KMS Server    : {0}:{1}' -f $lic.KeyManagementServiceMachine, $lic.KeyManagementServicePort) -Level Detail
            Write-ToolOutput ('  KMS Count     : {0}' -f $lic.KeyManagementServiceCurrentCount) -Level Detail
        }

        if ($licStatus -eq 1) {
            # Already licensed - do NOT run /ato
            Complete-ToolRun $run -Status Success -Summary ('Windows is activated ({0})' -f $statusText)
            return
        }

        # Not licensed - attempt online activation via slmgr /ato
        Write-ToolOutput ('Windows is NOT activated ({0}); attempting slmgr /ato...' -f $statusText) -Level Warning
        $slmgrVbs = Join-Path $env:SystemRoot 'System32\slmgr.vbs'
        $atoLines  = @(& cscript.exe //nologo $slmgrVbs /ato 2>&1)
        foreach ($line in $atoLines) {
            $text = [string]$line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                Write-ToolOutput ('  {0}' -f $text) -Level Detail
            }
        }

        # Re-query to confirm new status
        $lic2 = Get-CimInstance -ClassName SoftwareLicensingProduct `
            -Filter "Name LIKE 'Windows%' AND PartialProductKey IS NOT NULL" `
            -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($lic2 -and [int]$lic2.LicenseStatus -eq 1) {
            Complete-ToolRun $run -Status Success -Summary 'Activated via slmgr /ato'
        } else {
            $postStatus = if ($lic2) { $statusMap[[int]$lic2.LicenseStatus] } else { 'Unknown' }
            Complete-ToolRun $run -Status Warning -Summary (
                'Not activated after slmgr /ato ({0}); verify KMS connectivity or product key' -f $postStatus)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
