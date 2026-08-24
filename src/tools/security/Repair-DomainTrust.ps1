function Repair-DomainTrust {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'domain-trust-repair'

        # --- Report ---
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        Write-ToolOutput ('Computer: {0}' -f $cs.Name) -Level Info
        Write-ToolOutput ('Domain: {0}  (PartOfDomain={1})' -f $cs.Domain, $cs.PartOfDomain) -Level Detail

        # Prefer USERDNSDOMAIN (interactive); fall back to the machine's domain (SYSTEM/PDQ context)
        $domain = $env:USERDNSDOMAIN
        if (-not $domain) { $domain = $cs.Domain }

        if (-not $cs.PartOfDomain) {
            Write-ToolOutput 'This computer is not joined to a domain; domain-trust repair does not apply.' -Level Warning
            Complete-ToolRun $run -Status Success -Summary 'Not domain-joined; no action'
            return
        }

        $sc = $false
        try { $sc = [bool](Test-ComputerSecureChannel -ErrorAction Stop) } catch { $sc = $false }
        if ($sc) { Write-ToolOutput 'Secure channel: OK' -Level Detail }
        else     { Write-ToolOutput 'Secure channel: BROKEN' -Level Warning }

        $dc = nltest ('/dclist:{0}' -f $domain) 2>$null
        if ($LASTEXITCODE -eq 0 -and $dc) {
            Write-ToolOutput 'Domain controllers:' -Level Detail
            foreach ($line in ($dc | Select-String '^\s+\w')) { Write-ToolOutput ('  {0}' -f ([string]$line).Trim()) -Level Detail }
        } else {
            Write-ToolOutput 'Domain controller list unavailable (nltest failed).' -Level Warning
        }

        $dns = $false
        try { $null = Resolve-DnsName -Name $domain -Type A -ErrorAction Stop; $dns = $true } catch { $dns = $false }
        if ($dns) { Write-ToolOutput ('DNS resolution of {0}: OK' -f $domain) -Level Detail }
        else      { Write-ToolOutput ('DNS resolution of {0}: FAILED' -f $domain) -Level Warning }

        $null = w32tm /query /status 2>$null
        if ($LASTEXITCODE -eq 0) { Write-ToolOutput 'Time service: responding' -Level Detail }
        else { Write-ToolOutput 'Time service: not responding (see time-sync-repair)' -Level Warning }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Domain trust action' `
            -Choices @('None','TestSecureChannel','RepairSecureChannel','ResetMachinePassword','ResyncTime','PurgeKerberos','RejoinDomain','ShowDetails') -Default 'None' -Silent:$Silent

        switch ($action) {

            'TestSecureChannel' {
                $ok = $false
                try { $ok = [bool](Test-ComputerSecureChannel -ErrorAction Stop) } catch { $ok = $false }
                if ($ok) { Complete-ToolRun $run -Status Success -Summary 'Secure channel OK' }
                else     { Complete-ToolRun $run -Status Warning -Summary 'Secure channel BROKEN - try RepairSecureChannel or ResetMachinePassword' }
            }

            'RepairSecureChannel' {
                $cred = Get-Credential -Message 'Enter domain admin credentials to repair the secure channel'
                if (-not $cred) { Complete-ToolRun $run -Status Skipped -Summary 'RepairSecureChannel cancelled (no credentials)'; return }
                try {
                    $ok = [bool](Test-ComputerSecureChannel -Repair -Credential $cred -ErrorAction Stop)
                    if ($ok) { Complete-ToolRun $run -Status Success -Summary 'Secure channel repaired' }
                    else     { Complete-ToolRun $run -Status Warning -Summary 'Secure channel repair returned false' }
                } catch { Complete-ToolRun $run -Status Failed -Summary ('Repair failed: {0}' -f $_.Exception.Message) }
            }

            'ResetMachinePassword' {
                $cred = Get-Credential -Message 'Enter domain admin credentials to reset the computer account password'
                if (-not $cred) { Complete-ToolRun $run -Status Skipped -Summary 'ResetMachinePassword cancelled (no credentials)'; return }
                try {
                    Reset-ComputerMachinePassword -Credential $cred -ErrorAction Stop
                    Complete-ToolRun $run -Status Success -Summary 'Computer account password reset; restart recommended'
                } catch { Complete-ToolRun $run -Status Failed -Summary ('Reset failed: {0}' -f $_.Exception.Message) }
            }

            'ResyncTime' {
                w32tm /resync /force 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Complete-ToolRun $run -Status Success -Summary 'Time resynced (see time-sync-repair for deep repair)' }
                else { Complete-ToolRun $run -Status Warning -Summary 'w32tm /resync failed; try time-sync-repair' }
            }

            'PurgeKerberos' {
                klist purge 2>$null | Out-Null
                Complete-ToolRun $run -Status Success -Summary 'Kerberos tickets purged; user may need to re-authenticate'
            }

            'RejoinDomain' {
                # Read-ToolChoice -ExactMatch: a bare Read-Host throws in the GUI's hostless
                # tool runspace (caught by the outer catch before any state change - fails
                # closed, but the feature silently can't be used from the default UI mode).
                # -ExactMatch also makes the comparison case-sensitive so 'rejoin' can't
                # satisfy an all-caps "type this exactly" gate the way plain -eq would.
                $typed = Read-ToolChoice -Prompt 'WARNING: this unjoins then rejoins the domain and needs a restart. Type REJOIN to proceed' `
                    -Choices @('REJOIN', 'Cancel') -Default 'Cancel' -Silent:$Silent -ExactMatch
                if ($typed -ne 'REJOIN') { Complete-ToolRun $run -Status Skipped -Summary 'RejoinDomain cancelled (confirmation not typed)'; return }
                $cred = Get-Credential -Message 'Enter domain admin credentials to rejoin the domain'
                if (-not $cred) { Complete-ToolRun $run -Status Skipped -Summary 'RejoinDomain cancelled (no credentials)'; return }
                $unjoined = $false
                try {
                    Remove-Computer -UnjoinDomainCredential $cred -WorkgroupName 'WORKGROUP' -Force -ErrorAction Stop
                    $unjoined = $true
                    Start-Sleep -Seconds 3
                    Add-Computer -DomainName $cs.Domain -Credential $cred -Force -ErrorAction Stop
                    Write-ToolOutput 'Domain rejoin complete; a restart is required to finish.' -Level Success
                    $restart = Read-ToolChoice -Prompt 'Restart now?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                    if ($restart -eq 'Yes') { shutdown /r /t 10 /c 'Restarting after domain rejoin' | Out-Null }
                    Complete-ToolRun $run -Status Success -Summary 'Domain rejoined; restart required'
                } catch {
                    if ($unjoined) {
                        # Worse-than-before state: the machine left the domain successfully but
                        # never made it back in. Domain auth/GPO are broken until someone
                        # manually rejoins it - this must not read like a simple no-op failure.
                        Complete-ToolRun $run -Status Failed -Summary ('CRITICAL: machine was removed from the domain but rejoin failed and it is now in WORKGROUP - needs immediate manual rejoin. Error: {0}' -f $_.Exception.Message)
                    } else {
                        Complete-ToolRun $run -Status Failed -Summary ('Rejoin failed: {0}' -f $_.Exception.Message)
                    }
                }
            }

            'ShowDetails' {
                Write-ToolOutput 'Device join status (dsregcmd):' -Level Detail
                foreach ($l in (dsregcmd /status 2>$null | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined')) { Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail }
                Write-ToolOutput 'Domain controller (nltest /dsgetdc):' -Level Detail
                foreach ($l in (nltest ('/dsgetdc:{0}' -f $domain) 2>$null)) { Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail }
                Complete-ToolRun $run -Status Success -Summary 'Domain details displayed'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Domain trust state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
