function Repair-TeamsDeep {
    [CmdletBinding()]
    param([switch]$Silent)

    # Timeout-bounded TCP probe (reused pattern) - avoids hangs on blocked endpoints.
    function Test-TcpEndpoint {
        param([string]$HostName, [int]$Port, [int]$TimeoutMs = 3000)
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $null
        try {
            $iar = $client.BeginConnect($HostName, $Port, $null, $null)
            $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok) {
                try { $client.EndConnect($iar) } catch { }
                return $client.Connected
            }
            return $false
        } catch {
            return $false
        } finally {
            if ($iar -and $iar.AsyncWaitHandle) { $iar.AsyncWaitHandle.Dispose() }
            $client.Close()
        }
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-deep-diagnostic'
        $report = @()
        $issues = @()
        # Several checks below are SESSION-bound rather than path-bound: the
        # credential vault and the Azure AD PRT belong to the logon session, not
        # to a directory that can be redirected. Answering them from the
        # technician's session would be worse than not answering them, so they
        # report SKIP instead.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx
        if ($ctx.IsRedirected) {
            Write-ToolOutput ('Session-bound checks (credentials, Azure AD PRT) cannot be read for {0} from this session; they report SKIP.' -f $ctx.DisplayName) -Level Warning
        }

        $msixPath = $null
        if ($ctx.Resolved) { $msixPath = Join-Path $ctx.LocalAppData 'Packages\MSTeams_8wekyb3d8bbwe' }

        # Check 1: MSTeams AppX registration (per-user; -User needs elevation)
        $pkg      = $null
        $pkgKnown = $true
        if ($ctx.IsRedirected) {
            try { $pkg = Get-AppxPackage -Name 'MSTeams' -User $ctx.Sid -ErrorAction Stop } catch { $pkgKnown = $false }
        } else {
            $pkg = Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue
        }
        if (-not $pkgKnown) {
            Write-ToolOutput ('[SKIP] MSTeams registration for {0} not readable (needs elevation)' -f $ctx.DisplayName) -Level Warning
            $report += 'MSTeams: not readable'
        } elseif ($pkg) {
            Write-ToolOutput ('[PASS] MSTeams registered: v{0}' -f $pkg.Version) -Level Success
            $report += ('MSTeams: v{0}' -f $pkg.Version)
        } else {
            Write-ToolOutput ('[FAIL] MSTeams NOT registered for {0}' -f $ctx.DisplayName) -Level Error
            $report += 'MSTeams: not registered'; $issues += 'teams_not_registered'
        }

        # Check 2: MSIX package folder
        if ($msixPath -and (Test-Path -LiteralPath $msixPath)) {
            $sz = (Get-ChildItem -LiteralPath $msixPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $mb = [math]::Round(($sz / 1MB), 1)
            Write-ToolOutput ('[PASS] MSIX folder present ({0} MB)' -f $mb) -Level Success
            $report += ('MSIX folder: {0} MB' -f $mb)
        } else {
            Write-ToolOutput '[WARN] MSIX package folder missing' -Level Warning
            $report += 'MSIX folder: missing'; $issues += 'msix_folder_missing'
        }

        # Check 3: dsregcmd AAD / WAM / PRT
        # dsregcmd reports the CALLING session. AzureAdJoined is device-wide and
        # stays valid, but WamDefaultSet and AzureAdPrt are per-user: under a
        # redirected session they describe the technician's token state, which
        # would send the whole diagnosis down the wrong path.
        $dsreg = (dsregcmd /status 2>&1) -join "`n"
        if ($ctx.IsRedirected) {
            if ($dsreg -match 'AzureAdJoined\s*:\s*YES') {
                Write-ToolOutput '[PASS] Azure AD Joined: YES (device-wide)' -Level Success; $report += 'AAD Joined: YES'
            } else {
                Write-ToolOutput '[WARN] Azure AD Joined: NO (device-wide)' -Level Warning; $report += 'AAD Joined: NO'; $issues += 'not_aad_joined'
            }
            Write-ToolOutput ('[SKIP] WAM Default / Azure AD PRT are per-user and cannot be read for {0} from this session' -f $ctx.DisplayName) -Level Warning
            $report += 'WAM Default: not readable'
            $report += 'AAD PRT: not readable'
        } else {
        if ($dsreg -match 'AzureAdJoined\s*:\s*YES') {
            Write-ToolOutput '[PASS] Azure AD Joined: YES' -Level Success; $report += 'AAD Joined: YES'
        } else {
            Write-ToolOutput '[WARN] Azure AD Joined: NO' -Level Warning; $report += 'AAD Joined: NO'; $issues += 'not_aad_joined'
        }
        if ($dsreg -match 'WamDefaultSet\s*:\s*YES') {
            Write-ToolOutput '[PASS] WAM Default Set: YES' -Level Success; $report += 'WAM Default: YES'
        } else {
            Write-ToolOutput '[WARN] WAM Default Set: NO' -Level Warning; $report += 'WAM Default: NO'; $issues += 'wam_not_configured'
        }
        $prt = 'Unknown'
        if ($dsreg -match 'AzureAdPrt\s*:\s*(\w+)') { $prt = $Matches[1] }
        Write-ToolOutput ('[INFO] Azure AD PRT: {0}' -f $prt) -Level Detail
        $report += ('AAD PRT: {0}' -f $prt)
        if ($prt -ne 'YES') { $issues += 'prt_missing' }
        }

        # Check 4: AAD/WAM event log (needs elevation; degrade gracefully)
        try {
            $aadErr = @(Get-WinEvent -LogName 'Microsoft-Windows-AAD/Operational' -MaxEvents 50 -ErrorAction Stop |
                Where-Object { $_.Level -le 3 } | Select-Object -First 5)
            if ($aadErr.Count -gt 0) {
                Write-ToolOutput ('[WARN] {0} recent AAD/WAM error(s) in event log' -f $aadErr.Count) -Level Warning
                $report += ('AAD event log: {0} errors' -f $aadErr.Count); $issues += 'wam_event_errors'
            } else {
                Write-ToolOutput '[PASS] No recent AAD/WAM errors' -Level Success; $report += 'AAD event log: clean'
            }
        } catch {
            Write-ToolOutput '[INFO] Could not read AAD event log (needs elevation)' -Level Detail
            $report += 'AAD event log: not read'
        }

        # Check 5: Credential Manager Teams/M365 entries
        # The credential vault belongs to the logon session. cmdkey has no way to
        # target another user, so under redirection this would enumerate the
        # technician's credentials and report them as the user's.
        if ($ctx.IsRedirected) {
            Write-ToolOutput ('[SKIP] Credential Manager is session-bound and cannot be read for {0}' -f $ctx.DisplayName) -Level Warning
            $report += 'Cred Manager: not readable'
        } else {
        $credOut = (cmdkey /list 2>&1) | Out-String
        $teamsCreds = @(($credOut -split "`n") | Where-Object { $_ -match 'MicrosoftOffice|\bTeams\b|microsoftteams|aadg\.windows\.net|login\.microsoft' })
        if ($teamsCreds.Count -gt 0) {
            Write-ToolOutput ('[WARN] {0} Teams/M365 credential entr(ies) (may be stale)' -f $teamsCreds.Count) -Level Warning
            $report += ('Cred Manager: {0} entries' -f $teamsCreds.Count); $issues += 'stale_credentials'
        } else {
            Write-ToolOutput '[PASS] No stale Teams/M365 credentials' -Level Success; $report += 'Cred Manager: clean'
        }
        }

        # Check 6: Network reachability (timeout-bounded)
        $endpoints = @(
            @{ Name = 'Teams';       HostName = 'teams.microsoft.com';       Port = 443 },
            @{ Name = 'Azure AD';    HostName = 'login.microsoftonline.com'; Port = 443 },
            @{ Name = 'MS Graph';    HostName = 'graph.microsoft.com';       Port = 443 },
            @{ Name = 'Teams media'; HostName = 'teams.microsoft.com';       Port = 3478 }
        )
        foreach ($ep in $endpoints) {
            if (Test-TcpEndpoint -HostName $ep.HostName -Port $ep.Port -TimeoutMs 3000) {
                Write-ToolOutput ('[PASS] {0} ({1}:{2})' -f $ep.Name, $ep.HostName, $ep.Port) -Level Success
                $report += ('Net {0}: PASS' -f $ep.Name)
            } else {
                Write-ToolOutput ('[FAIL] {0} ({1}:{2}) unreachable' -f $ep.Name, $ep.HostName, $ep.Port) -Level Error
                $report += ('Net {0}: FAIL' -f $ep.Name); $issues += 'network_blocked'
            }
        }

        # Check 7: TLS issuer (proxy-intercept hint). Gate on a timeout-bounded probe first so a
        # black-holed host cannot hang the blocking TcpClient.Connect below.
        if (-not (Test-TcpEndpoint -HostName 'login.microsoftonline.com' -Port 443 -TimeoutMs 3000)) {
            Write-ToolOutput '[INFO] TLS check skipped (login.microsoftonline.com:443 unreachable)' -Level Detail
            $report += 'TLS: skipped (unreachable)'
        } else {
            $tcp = $null
            $ssl = $null
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $tcp.SendTimeout = 5000
                $tcp.ReceiveTimeout = 5000
                $tcp.Connect('login.microsoftonline.com', 443)
                $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
                $ssl.AuthenticateAsClient('login.microsoftonline.com')
                $issuer = $ssl.RemoteCertificate.Issuer
                if ($issuer -match 'Microsoft|DigiCert|GlobalSign|Comodo|Sectigo|Baltimore|Entrust') {
                    Write-ToolOutput ('[PASS] TLS issuer legitimate: {0}' -f $issuer) -Level Success
                    $report += 'TLS: ok'
                } else {
                    Write-ToolOutput ('[WARN] Unexpected TLS issuer (proxy intercept?): {0}' -f $issuer) -Level Warning
                    $report += ('TLS: suspect - {0}' -f $issuer); $issues += 'tls_inspection'
                }
            } catch {
                Write-ToolOutput '[INFO] TLS check could not complete' -Level Detail
                $report += 'TLS: check failed'
            } finally {
                if ($ssl) { $ssl.Dispose() }
                if ($tcp) { $tcp.Dispose() }
            }
        }

        # Check 8: Proxy configuration
        $winHttp = (netsh winhttp show proxy 2>&1) | Out-String
        $ieSettings = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $ieProp = $null
        if ($ctx.Resolved) { $ieProp = Get-ItemProperty -LiteralPath $ieSettings -ErrorAction SilentlyContinue }
        if ($ieProp.ProxyEnable -eq 1 -and $ieProp.ProxyServer) {
            Write-ToolOutput ('[WARN] User proxy enabled: {0}' -f $ieProp.ProxyServer) -Level Warning
            $report += ('Proxy: {0}' -f $ieProp.ProxyServer); $issues += 'proxy_configured'
        } elseif ($winHttp -match 'Proxy Server') {
            Write-ToolOutput '[WARN] WinHTTP proxy configured' -Level Warning
            $report += 'Proxy: WinHTTP'; $issues += 'proxy_configured'
        } else {
            Write-ToolOutput '[PASS] No proxy configured' -Level Success; $report += 'Proxy: none'
        }

        # Check 9: Teams firewall BLOCK rules
        $fw = @(Get-NetFirewallRule -DisplayName '*Teams*' -ErrorAction SilentlyContinue)
        $blocked = @($fw | Where-Object { $_.Action -eq 'Block' -and $_.Enabled -eq 'True' })
        if ($blocked.Count -gt 0) {
            Write-ToolOutput ('[WARN] {0} active Teams BLOCK firewall rule(s)' -f $blocked.Count) -Level Warning
            $report += ('Firewall: {0} block rules' -f $blocked.Count); $issues += 'firewall_blocking'
        } else {
            Write-ToolOutput '[PASS] No active Teams BLOCK firewall rules' -Level Success; $report += 'Firewall: ok'
        }

        # Check 10: Teams scheduled tasks
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'Teams' -or $_.TaskPath -match 'Teams' })
        Write-ToolOutput ('[INFO] Teams scheduled tasks: {0}' -f $tasks.Count) -Level Detail
        $report += ('Sched tasks: {0}' -f $tasks.Count)

        # Check 11: newest Teams log tail for auth errors
        $logBase = $null
        if ($msixPath) { $logBase = Join-Path $msixPath 'LocalCache\Microsoft\MSTeams\Logs' }
        if ($logBase -and (Test-Path -LiteralPath $logBase)) {
            $latest = Get-ChildItem -LiteralPath $logBase -Filter '*.log' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                $authErr = @(Get-Content -LiteralPath $latest.FullName -Tail 200 -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match '\berror\b|\bfailed\b|\bunauthorized\b|\b401\b|\b403\b|\btoken\b|\bauth\b' } | Select-Object -Last 5)
                if ($authErr.Count -gt 0) {
                    Write-ToolOutput ('[WARN] auth-related entries in {0}' -f $latest.Name) -Level Warning
                    $report += 'Teams logs: auth errors'; $issues += 'teams_log_auth_errors'
                } else {
                    Write-ToolOutput '[PASS] No recent auth errors in Teams log' -Level Success; $report += 'Teams logs: clean'
                }
            } else {
                Write-ToolOutput '[INFO] No Teams .log files' -Level Detail; $report += 'Teams logs: none'
            }
        } else {
            Write-ToolOutput '[INFO] Teams log dir not found' -Level Detail; $report += 'Teams logs: dir missing'
        }

        # Summary + report file
        $reportPath = Join-Path $env:TEMP ('TeamsDeepDiag_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        try { $report | Out-File -LiteralPath $reportPath -Encoding UTF8 -ErrorAction Stop; Write-ToolOutput ('Report saved: {0}' -f $reportPath) -Level Info } catch { }
        Write-ToolOutput ('Diagnostic complete: 11 checks, {0} issue(s) found.' -f $issues.Count) -Level Info
        if ($issues.Count -gt 0) { Write-ToolOutput ('Issue codes: {0}' -f ($issues -join ', ')) -Level Detail }

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Teams deep-repair action' -Choices @('None','ApplyRepairs') -Default 'None' -Silent:$Silent

        switch ($action) {

            'ApplyRepairs' {
                # Hard refusal, before the confirm prompt. Every repair below is
                # session-bound: cmdkey /delete removes credentials from the
                # CALLING account's vault, and Add-AppxPackage -Register
                # registers Teams for the CALLING account. Run from an elevated
                # session on someone else's laptop, this would wipe the
                # technician's own M365 credentials and leave the reported fault
                # untouched - a worse outcome than doing nothing.
                if ($ctx.IsRedirected) {
                    Write-ToolOutput ('Deep repair cannot run from this session: it would clear credentials and re-register Teams for {0}, not {1}.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Error
                    Write-ToolOutput ('Sign in as {0} (or have them run the toolkit) and re-run this repair there.' -f $ctx.DisplayName) -Level Info
                    Complete-ToolRun $run -Status Failed `
                        -Summary ('Diagnostic complete ({0} issue(s)); deep repair refused - session-bound operations would target {1}, not {2}. Nothing was changed.' -f $issues.Count, $ctx.ProcessName, $ctx.DisplayName)
                    return
                }
                if (-not $ctx.Resolved) {
                    Complete-ToolRun $run -Status Failed `
                        -Summary ('Diagnostic complete ({0} issue(s)); deep repair refused - {1}. Nothing was changed.' -f $issues.Count, $ctx.Reason)
                    return
                }
                Write-ToolOutput 'WARNING: this CLOSES Teams and CLEARS its credentials/WAM tokens/cache - you will be signed out and must sign in again.' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Apply deep repairs (sign-out required)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary ('Diagnostic complete ({0} issues); repair cancelled' -f $issues.Count)
                } else {
                    foreach ($p in @('ms-teams','MSTeams','Teams','TeamsMeetingAddin')) {
                        Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Seconds 3
                    $removed = 0
                    $credLines = (cmdkey /list 2>&1) | Out-String
                    $targets = @(($credLines -split "`n") | Where-Object { $_ -match 'Target:' -and $_ -match 'MicrosoftOffice|microsoftteams|\bTeams\b|aadg\.windows\.net|login\.microsoft' })
                    foreach ($line in $targets) {
                        $t = ($line -replace '.*Target:\s*', '').Trim()
                        if ($t) {
                            # Quoted and $LASTEXITCODE-gated to match Clear-SavedCredentials.ps1's
                            # reference pattern - an unquoted target with a space (some legacy
                            # TERMSRV/ or generic targets) mis-parses in cmdkey and silently fails
                            # to delete, but $removed was previously incremented unconditionally.
                            cmdkey "/delete:$t" *>$null
                            if ($LASTEXITCODE -eq 0) { $removed++ }
                        }
                    }
                    Write-ToolOutput ('Cleared {0} credential entr(ies).' -f $removed) -Level Detail
                    # Containment-gated. The MSIX package tree lives under the
                    # user's LocalAppData\Packages and is fully writable by them,
                    # so a junction planted here would otherwise be followed out
                    # of the profile by this elevated process.
                    foreach ($wp in @((Join-Path $msixPath 'Settings'), (Join-Path $msixPath 'AC\TokenBroker'))) {
                        if (Test-Path -LiteralPath $wp) {
                            [void](Remove-UserPathContent -Context $ctx -Path $wp)
                        }
                    }
                    $lc = Join-Path $msixPath 'LocalCache'
                    if (Test-Path -LiteralPath $lc) {
                        [void](Remove-UserPathContent -Context $ctx -Path $lc)
                    }
                    $appxOk = $false
                    $manifest = Join-Path $msixPath 'AppxManifest.xml'
                    if (Test-Path -LiteralPath $manifest) {
                        try {
                            Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
                            Write-ToolOutput 'MSTeams AppX re-registered.' -Level Detail
                            $appxOk = $true
                        } catch {
                            Write-ToolOutput ('AppX re-register failed: {0} (reinstall Teams)' -f $_.Exception.Message) -Level Warning
                        }
                    } else {
                        Write-ToolOutput 'AppxManifest not found; Teams must be reinstalled.' -Level Warning
                    }
                    $tokenBrokerOk = $false
                    try {
                        Restart-Service -Name 'TokenBroker' -Force -ErrorAction Stop
                        Write-ToolOutput 'TokenBroker restarted.' -Level Detail
                        $tokenBrokerOk = $true
                    } catch {
                        Write-ToolOutput 'Could not restart TokenBroker (needs elevation; reboot recommended).' -Level Warning
                    }
                    # Relaunching Teams is a convenience, not part of the repair, so it
                    # must never be able to change the outcome. Two defects here:
                    #
                    # -ErrorAction only suppresses NON-terminating errors, and Start-Process
                    # raises a TERMINATING one when it cannot resolve the target as an
                    # application. The flag did nothing; the throw skipped every
                    # Complete-ToolRun below and landed in the outer catch, so a fully
                    # successful repair reported Failed. -ErrorAction Stop inside a try
                    # catches both kinds.
                    #
                    # It also ignored $ctx. Everything above repairs the LOGGED-ON user's
                    # Teams; this launched Teams as whatever account the process runs as,
                    # so under over-the-shoulder elevation it started in the technician's
                    # profile - the mix-up $ctx exists to prevent. Test IsCurrentUser, never
                    # '-not IsRedirected', which is also false when nothing was resolved.
                    if ($ctx.IsCurrentUser) {
                        try {
                            Start-Process 'ms-teams:' -ErrorAction Stop
                            Start-Sleep -Seconds 2
                        } catch {
                            Write-ToolOutput 'Could not relaunch Teams automatically - start it from the Start menu. The repair itself is unaffected.' -Level Detail
                        }
                    } else {
                        Write-ToolOutput ('Not relaunching Teams: this session is {0}, not {1}. Have the user start Teams and sign in.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Detail
                    }
                    # Final status previously depended only on $appxOk - a run that cleared
                    # all WAM/MSAL caches and credentials but never got TokenBroker to
                    # reinitialize (so the sign-in loop this tool exists to fix may not
                    # actually be resolved without a reboot) could still report Success.
                    if ($appxOk -and $tokenBrokerOk) {
                        Complete-ToolRun $run -Status Success -Summary ('Deep repair applied ({0} creds cleared; WAM/MSIX cache cleared; AppX re-registered; TokenBroker restarted)' -f $removed)
                    } elseif ($appxOk) {
                        Complete-ToolRun $run -Status Warning -Summary ('Deep repair applied ({0} creds cleared; WAM/MSIX cache cleared; AppX re-registered) but TokenBroker did not restart - reboot recommended' -f $removed)
                    } else {
                        Complete-ToolRun $run -Status Warning -Summary ('Deep repair applied ({0} creds cleared; WAM/MSIX cache cleared) but AppX re-register did not succeed - may need Teams reinstall' -f $removed)
                    }
                }
            }

            default {
                if ($issues.Count -gt 0) {
                    Complete-ToolRun $run -Status Warning -Summary ('Diagnostic complete: {0} issue(s) found; no repair applied' -f $issues.Count)
                } else {
                    Complete-ToolRun $run -Status Success -Summary 'Diagnostic complete: no issues found'
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
