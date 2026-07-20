function Get-CertificateExpiry {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'cert-expiry'

        $thresholdDays = 60
        $now = Get-Date
        $certs = @(Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction Stop)

        Write-ToolOutput ('Scanning {0} certificate(s) in LocalMachine\My for expiry within {1} days...' -f $certs.Count, $thresholdDays) -Level Info

        $flagged = New-Object System.Collections.Generic.List[object]
        foreach ($c in $certs) {
            $daysRemaining = [math]::Round(($c.NotAfter - $now).TotalDays, 1)
            if ($daysRemaining -le $thresholdDays) {
                $flagged.Add([PSCustomObject]@{
                    Subject       = $c.Subject
                    Thumbprint    = $c.Thumbprint
                    NotAfter      = $c.NotAfter
                    DaysRemaining = $daysRemaining
                })
            }
        }

        if ($flagged.Count -eq 0) {
            Write-ToolOutput ('No certificates in LocalMachine\My expire within {0} days.' -f $thresholdDays) -Level Detail
            Complete-ToolRun $run -Status Success -Summary ('{0} certificate(s) checked; none expiring within {1} days' -f $certs.Count, $thresholdDays)
            return
        }

        $sorted = @($flagged | Sort-Object DaysRemaining)
        foreach ($f in $sorted) {
            $status = 'expires in {0} day(s)' -f $f.DaysRemaining
            if ($f.DaysRemaining -lt 0) { $status = 'EXPIRED {0} day(s) ago' -f ([math]::Abs($f.DaysRemaining)) }
            Write-ToolOutput ('  {0}  thumbprint={1}  NotAfter={2}  ({3})' -f $f.Subject, $f.Thumbprint, $f.NotAfter.ToString('yyyy-MM-dd HH:mm'), $status) -Level Warning
        }

        Complete-ToolRun $run -Status Warning -Summary ('{0} of {1} certificate(s) expiring within {2} days or already expired' -f $flagged.Count, $certs.Count, $thresholdDays)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
