function Repair-TimeSync {
    [CmdletBinding()]
    param([switch]$Silent)

    # Return the "Last Successful Sync Time" line from w32tm status, or $null.
    function Get-LastSyncLine {
        $st = w32tm /query /status 2>$null
        $line = $st | Select-String 'Last Successful Sync Time'
        if ($line) { return ([string]$line).Trim() }
        return $null
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'time-sync-repair'

        # --- Report ---
        Write-ToolOutput ('System time: {0}' -f (Get-Date)) -Level Info
        $status = w32tm /query /status 2>$null
        if ($LASTEXITCODE -eq 0 -and $status) {
            foreach ($l in ($status | Select-String 'Source|Stratum|Last Successful Sync Time')) {
                Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail
            }
        } else {
            Write-ToolOutput 'w32tm /query /status did not respond (W32Time may be stopped).' -Level Warning
        }
        $peers = w32tm /query /peers 2>$null
        $peer = $peers | Select-String 'Peer:' | Select-Object -First 1
        if ($peer) { Write-ToolOutput ('NTP peer: {0}' -f ([string]$peer).Trim()) -Level Detail }
        else { Write-ToolOutput 'No NTP peers configured/reachable.' -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Time sync action' -Choices @('None','Resync','FullRepair') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success -Summary 'Time sync state reported; no action taken'
            return
        }

        $w32 = Get-Service -Name 'W32Time' -ErrorAction SilentlyContinue
        if ($w32 -and $w32.Status -ne 'Running') { Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue }

        if ($action -eq 'FullRepair') {
            w32tm /unregister 2>$null | Out-Null
            w32tm /register 2>$null | Out-Null
            Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue
            $dom = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Domain
            if ($dom -and $dom -ne 'WORKGROUP') {
                w32tm /config /syncfromflags:domhier /update 2>$null | Out-Null
                Write-ToolOutput ('Configured to sync from domain hierarchy ({0}).' -f $dom) -Level Detail
            } else {
                w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update 2>$null | Out-Null
                Write-ToolOutput 'Configured to sync from time.windows.com.' -Level Detail
            }
        }

        w32tm /resync /force 2>$null | Out-Null
        $resyncOk = ($LASTEXITCODE -eq 0)
        Start-Sleep -Seconds 2

        $last = Get-LastSyncLine
        if ($last) { Write-ToolOutput ('After resync: {0}' -f $last) -Level Detail }
        Write-ToolOutput 'NOTE: Kerberos auth fails when clock drift exceeds 5 minutes.' -Level Detail

        if ($resyncOk) {
            Complete-ToolRun $run -Status Success -Summary ('{0} complete; time resynced' -f $action)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('{0} ran but w32tm /resync did not confirm sync (source may be unreachable)' -f $action)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
