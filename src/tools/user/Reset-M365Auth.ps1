function Reset-M365Auth {
    [CmdletBinding()]
    param([switch]$Silent)

    # Parse cmdkey /list for Office/M365 credential targets (anchored Target: line).
    function Get-OfficeCredTarget {
        $targets = New-Object System.Collections.Generic.List[string]
        foreach ($line in (cmdkey /list 2>$null)) {
            if ($line -match '^\s*Target:\s*(.+?)\s*$') {
                $t = $Matches[1]
                if ($t -match 'MicrosoftOffice|office|microsoftonline|sharepoint|outlook') {
                    $targets.Add($t)
                }
            }
        }
        return $targets
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'm365-auth-reset'
        # Mixed tool: the MSAL/WAM caches and the Outlook key are path-bound and
        # redirect cleanly, but cmdkey reads and DELETES from the CALLING
        # account's credential vault and has no way to target another user.
        # Under redirection this would wipe the technician's own M365 sign-ins,
        # so the credential half refuses rather than acting on the wrong vault.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot reset M365 auth - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $local      = $ctx.LocalAppData
        $msalPaths  = @((Join-Path $local 'Microsoft\OneAuth'), (Join-Path $local 'Microsoft\IdentityCache'))
        $wamCache   = Join-Path $local 'Microsoft\TokenBroker\Cache'
        $adGlob     = Join-Path $local 'Microsoft\Outlook\*autodiscover*'
        $secModeKey = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Office\16.0\Outlook'

        # --- Report ---
        $creds = @()
        if ($ctx.IsRedirected) {
            Write-ToolOutput ('Credential Manager is session-bound and cannot be read for {0}' -f $ctx.DisplayName) -Level Warning
        } else {
            $creds = @(Get-OfficeCredTarget)
            Write-ToolOutput ('Office/M365 saved credentials: {0}' -f $creds.Count) -Level Info
            foreach ($c in $creds) { Write-ToolOutput ('  {0}' -f $c) -Level Detail }
        }
        foreach ($p in $msalPaths) {
            Write-ToolOutput ('MSAL cache {0} present: {1}' -f (Split-Path -Leaf $p), (Test-Path -LiteralPath $p)) -Level Detail
        }
        Write-ToolOutput ('WAM TokenBroker cache present: {0}' -f (Test-Path -LiteralPath $wamCache)) -Level Detail
        $adFiles = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        Write-ToolOutput ('AutoDiscover cache files: {0}' -f $adFiles.Count) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'M365 auth reset (closes Office apps; user must sign in again)' `
            -Choices @('None','ClearTokens','ClearTokensAndSharedMailbox') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success -Summary ('{0} Office credential(s) reported; no action taken' -f $creds.Count)
            return
        }

        $confirm = Read-ToolChoice -Prompt 'Close all Office apps and clear cached sign-in tokens?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($confirm -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary ('{0} cancelled' -f $action)
            return
        }

        foreach ($name in @('OUTLOOK','TEAMS','ms-teams','MSTeams','WINWORD','EXCEL','ONENOTE')) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2

        # cmdkey deletes from the CALLING vault. Under redirection that is the
        # technician's, so the deletion is skipped entirely - clearing the wrong
        # person's M365 sign-ins is worse than clearing none.
        $cleared = 0
        $credSkipped = $false
        if ($ctx.IsRedirected) {
            $credSkipped = $true
            Write-ToolOutput ('Credential clearing skipped: cmdkey would delete {0} sign-ins, not {1}. The user must clear Credential Manager from their own session.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Warning
        } else {
            foreach ($t in @(Get-OfficeCredTarget)) {
                cmdkey /delete:$t 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { $cleared++ }
            }
        }

        foreach ($p in ($msalPaths + $wamCache)) {
            if (Test-Path -LiteralPath $p) {
                # Containment-gated: see Remove-UserPathContent. These are token
                # caches inside a tree the standard user fully controls.
                [void](Remove-UserPathContent -Context $ctx -Path $p)
            }
        }

        $extra = ''
        if ($action -eq 'ClearTokensAndSharedMailbox') {
            $adRemoved = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
            $adRemoved | Remove-Item -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $secModeKey -Name 'OutlookSecurityMode' -ErrorAction SilentlyContinue
            $extra = ('; {0} AutoDiscover cache file(s) removed, OutlookSecurityMode cleared' -f $adRemoved.Count)
        }

        if ($credSkipped) {
            Complete-ToolRun $run -Status Warning -Summary ('MSAL/WAM caches reset for {0}{1}; saved credentials NOT cleared (session-bound) - the user must clear Credential Manager themselves' -f $ctx.DisplayName, $extra)
        } else {
            Complete-ToolRun $run -Status Success -Summary ('{0} credential(s) cleared, MSAL/WAM caches reset{1}; user must sign in again' -f $cleared, $extra)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
