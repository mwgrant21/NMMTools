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
        $local      = $env:LOCALAPPDATA
        $msalPaths  = @("$local\Microsoft\OneAuth", "$local\Microsoft\IdentityCache")
        $wamCache   = "$local\Microsoft\TokenBroker\Cache"
        $adGlob     = "$local\Microsoft\Outlook\*autodiscover*"
        $secModeKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook'

        # --- Report ---
        $creds = @(Get-OfficeCredTarget)
        Write-ToolOutput ('Office/M365 saved credentials: {0}' -f $creds.Count) -Level Info
        foreach ($c in $creds) { Write-ToolOutput ('  {0}' -f $c) -Level Detail }
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

        $cleared = 0
        foreach ($t in @(Get-OfficeCredTarget)) {
            cmdkey /delete:$t 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $cleared++ }
        }

        foreach ($p in ($msalPaths + $wamCache)) {
            if (Test-Path -LiteralPath $p) {
                Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $extra = ''
        if ($action -eq 'ClearTokensAndSharedMailbox') {
            $adRemoved = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
            $adRemoved | Remove-Item -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $secModeKey -Name 'OutlookSecurityMode' -ErrorAction SilentlyContinue
            $extra = ('; {0} AutoDiscover cache file(s) removed, OutlookSecurityMode cleared' -f $adRemoved.Count)
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} credential(s) cleared, MSAL/WAM caches reset{1}; user must sign in again' -f $cleared, $extra)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
