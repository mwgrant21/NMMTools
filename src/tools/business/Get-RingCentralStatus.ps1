function Get-RingCentralStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    # Resolves the AppData\Local base path to inspect. Interactively this is just
    # $env:LOCALAPPDATA. Under SYSTEM (PDQ Deploy default) $env:LOCALAPPDATA points at the
    # SYSTEM profile, which never has RingCentral installed -> false fleet-wide "not
    # installed". Detect SYSTEM via the well-known S-1-5-18 SID, then resolve the
    # logged-on user's profile path instead. Returns @{ Base = <path-or-null>; Reason =
    # <null-or-explanation> } so the caller can tell "no user to check" apart from
    # "checked the right user, RingCentral just isn't there".
    function Resolve-RingCentralAppDataBase {
        $isSystem = $false
        try {
            $isSystem = ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
        } catch { $isSystem = $false }

        if (-not $isSystem) {
            return @{ Base = $env:LOCALAPPDATA; Reason = $null }
        }

        $loggedOnUser = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        # UserName is 'DOMAIN\user' or '' if no one is logged on
        if ([string]::IsNullOrWhiteSpace($loggedOnUser)) {
            return @{ Base = $null; Reason = 'no interactive user is logged on (running as SYSTEM)' }
        }

        $sid = $null
        try {
            $sid = (New-Object System.Security.Principal.NTAccount($loggedOnUser)).
                Translate([System.Security.Principal.SecurityIdentifier]).Value
        } catch {
            return @{ Base = $null; Reason = ('could not resolve SID for logged-on user {0}' -f $loggedOnUser) }
        }

        $profileObj = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
            Where-Object { $_.SID -eq $sid } | Select-Object -First 1
        if (-not $profileObj -or -not $profileObj.LocalPath) {
            return @{ Base = $null; Reason = ('could not resolve profile path for logged-on user {0}' -f $loggedOnUser) }
        }

        return @{ Base = (Join-Path $profileObj.LocalPath 'AppData\Local'); Reason = $null }
    }

    # Masks PII/secrets in a raw RingCentral log line before it is echoed into the session
    # log (which under SYSTEM is a central sink read by more than the affected user).
    # Keeps everything except emails, long digit runs (phone numbers/meeting IDs), and
    # token/bearer/password/auth style key=value pairs, which are replaced with
    # [redacted]. A leading timestamp/log-level token is left intact since it is not a
    # date/time long enough to match the digit-run pattern.
    function Get-RingCentralRedactedLine {
        param([Parameter(Mandatory)][string]$Line)
        $scrubbed = $Line
        $scrubbed = $scrubbed -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[redacted]'
        $scrubbed = $scrubbed -replace '(?i)(token|bearer|password|auth)[=:]\S+', '$1=[redacted]'
        $scrubbed = $scrubbed -replace '\+?\d{7,}', '[redacted]'
        return $scrubbed
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'ringcentral-status'

        # --- Resolve the correct AppData\Local base (handles SYSTEM context) ---
        $appDataBase = Resolve-RingCentralAppDataBase
        if (-not $appDataBase.Base) {
            Write-ToolOutput ('Cannot check RingCentral: {0}' -f $appDataBase.Reason) -Level Warning
            Complete-ToolRun $run -Status Warning -Summary ('Skipped: {0}' -f $appDataBase.Reason)
            return
        }
        $localAppData = $appDataBase.Base

        # --- Install detection ---
        $installCandidates = @(
            @{ Path = (Join-Path $localAppData 'Programs\RingCentral'); ProcessName = 'RingCentral' },
            @{ Path = (Join-Path $localAppData 'Glip');                 ProcessName = 'Glip' }
        )
        $installDir  = $null
        $processName = $null
        foreach ($c in $installCandidates) {
            if (Test-Path -LiteralPath $c.Path) {
                $installDir  = $c.Path
                $processName = $c.ProcessName
                break
            }
        }
        if (-not $installDir) {
            Write-ToolOutput 'RingCentral is not installed (no matching install directory found under AppData\Local)' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'RingCentral not installed'
            return
        }
        Write-ToolOutput ('Installed: {0}' -f $installDir) -Level Info

        # --- Version (from install manifest if present) ---
        $version = 'Unknown'
        $verDir = Get-ChildItem -LiteralPath $installDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^app-\d' } |
            Sort-Object { try { [System.Version]($_.Name -replace '^app-', '') } catch { [System.Version]'0.0' } } -Descending |
            Select-Object -First 1
        if ($verDir -and $verDir.Name -match '^app-(.+)$') {
            $version = $Matches[1]
        }
        Write-ToolOutput ('Version: {0}' -f $version) -Level Info

        # --- Process check ---
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -First 1
        $processLevel = if ($process) { 'Info' } else { 'Warning' }
        $processText  = if ($process) { 'Running' } else { 'Not running' }
        Write-ToolOutput ('Process ({0}): {1}' -f $processName, $processText) -Level $processLevel

        # --- Default audio device ---
        $audioDevice = Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
        $audioLevel = if ($audioDevice) { 'Info' } else { 'Warning' }
        $audioText  = if ($audioDevice) { $audioDevice.Name } else { 'No working audio device found' }
        Write-ToolOutput ('Audio device: {0}' -f $audioText) -Level $audioLevel

        # --- Log scan ---
        $logErrors     = New-Object System.Collections.Generic.List[string]
        $logChecked    = ($processName -eq 'RingCentral')
        $logUnreadable = $false
        if ($logChecked) {
            $logDir = Join-Path $localAppData 'RingCentral\RingCentralLogs'
            if (Test-Path -LiteralPath $logDir) {
                $latestLog = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latestLog) {
                    try {
                        $tail = @(Get-Content -LiteralPath $latestLog.FullName -Tail 300 -ErrorAction Stop)
                        $hits = @($tail | Where-Object { $_ -match 'error|fail|disconnect|timeout' })
                        foreach ($h in ($hits | Select-Object -Last 5)) {
                            $logErrors.Add((Get-RingCentralRedactedLine -Line $h.Trim()))
                        }
                    } catch {
                        $logUnreadable = $true
                        Write-ToolOutput ('Log present but unreadable ({0}); likely locked by running app; scan incomplete' -f $_.Exception.Message) -Level Warning
                    }
                }
            }
            if ($logErrors.Count -gt 0) {
                Write-ToolOutput ('Recent log errors ({0}):' -f $logErrors.Count) -Level Warning
                foreach ($e in $logErrors) { Write-ToolOutput ('  {0}' -f $e) -Level Detail }
            } elseif (-not $logUnreadable) {
                Write-ToolOutput 'No recent log errors found' -Level Detail
            }
        } else {
            Write-ToolOutput 'Log location not confirmed for legacy Glip-branded install; skipping log scan' -Level Detail
        }

        # --- Reachability ---
        $target  = 'app.ringcentral.com'
        $dnsFail = $false
        try {
            [System.Net.Dns]::GetHostAddresses($target) | Out-Null
        } catch { $dnsFail = $true }
        $pingOk = $false
        if (-not $dnsFail) {
            $ping = Test-Connection -ComputerName $target -Count 2 -ErrorAction SilentlyContinue
            $pingOk = ($null -ne $ping) -and (@($ping).Count -gt 0)
        }
        $reachLevel = if (-not $dnsFail) { 'Info' } else { 'Warning' }
        $reachText  = if ($dnsFail) {
            'DNS resolution failed for {0}' -f $target
        } elseif ($pingOk) {
            'Reachable'
        } else {
            'DNS resolved, no ping reply (may be ICMP-blocked)'
        }
        Write-ToolOutput ('Service reachability ({0}): {1}' -f $target, $reachText) -Level $reachLevel

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if (-not $process)           { $issues.Add('app not running') }
        if (-not $audioDevice)       { $issues.Add('no working audio device') }
        if ($logErrors.Count -gt 0)  { $issues.Add('{0} recent log error(s)' -f $logErrors.Count) }
        if ($logUnreadable)          { $issues.Add('log present but unreadable - scan incomplete') }
        if (-not $logChecked)        { $issues.Add('log location not confirmed for legacy Glip-branded install') }
        if ($dnsFail)                { $issues.Add('service unreachable (DNS failure)') }

        $verdict = if ($issues.Count -eq 0) {
            'Installed and running, audio device present, no recent errors'
        } else {
            'Issues: ' + ($issues -join '; ')
        }
        Write-ToolOutput ('Verdict: {0}' -f $verdict) -Level Info

        $status = if ($issues.Count -eq 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status -Summary $verdict
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
