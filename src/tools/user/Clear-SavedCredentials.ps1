function Clear-SavedCredentials {
    [CmdletBinding()]
    param([switch]$Silent)

    # Returns the current list of cmdkey credential Targets (re-queried each call).
    function Get-CredTargets {
        $l = (cmdkey /list 2>&1) | Out-String
        @(($l -split "`r?`n") |
            Where-Object { $_ -match 'Target:' } |
            ForEach-Object { ($_ -replace '^\s*Target:\s*', '').Trim() } |
            Where-Object { $_ })
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'credential-manager'

        # --- Report ---
        $targets = @(Get-CredTargets)
        Write-ToolOutput ('Saved credentials: {0}' -f $targets.Count) -Level Info
        foreach ($t in ($targets | Select-Object -First 20)) { Write-ToolOutput ('  {0}' -f $t) -Level Detail }
        if ($targets.Count -gt 20) { Write-ToolOutput ('  ... and {0} more' -f ($targets.Count - 20)) -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Credential action' `
            -Choices @('None','ClearNetwork','ClearWeb','ClearOffice365','ClearAll','OpenCredManager') -Default 'None' -Silent:$Silent

        switch ($action) {

            'ClearNetwork' {
                $removed = 0
                foreach ($t in (Get-CredTargets)) {
                    if ($t -like '*\\*' -or $t -like 'Domain:*' -or $t -like '*smb*' -or $t -like '*cifs*') {
                        cmdkey "/delete:$t" *>$null
                        if ($LASTEXITCODE -eq 0) { $removed++ }
                    }
                }
                Complete-ToolRun $run -Status Success -Summary ('Cleared {0} network/share credential(s)' -f $removed)
            }

            'ClearWeb' {
                $removed = 0
                foreach ($t in (Get-CredTargets)) {
                    if ($t -like '*http*' -or $t -like '*.com' -or $t -like '*.net' -or $t -like '*.org' -or $t -like 'WindowsLive:*') {
                        cmdkey "/delete:$t" *>$null
                        if ($LASTEXITCODE -eq 0) { $removed++ }
                    }
                }
                Complete-ToolRun $run -Status Success -Summary ('Cleared {0} web credential(s)' -f $removed)
            }

            'ClearOffice365' {
                $removed = 0
                foreach ($t in (Get-CredTargets)) {
                    if ($t -match 'MicrosoftOffice') {
                        cmdkey "/delete:$t" *>$null
                        if ($LASTEXITCODE -eq 0) { $removed++ }
                    }
                }
                Complete-ToolRun $run -Status Success -Summary ('Cleared {0} Office 365 credential(s) (stops the Office sign-in loop)' -f $removed)
            }

            'ClearAll' {
                Write-ToolOutput 'WARNING: removes ALL saved credentials (shares, RDP, web, services). You will re-enter passwords everywhere.' -Level Warning
                $gate = Read-ToolChoice -Prompt 'Type CLEAR to remove ALL saved credentials' `
                    -Choices @('CLEAR','Cancel') -Default 'Cancel' -Silent:$Silent
                if ($gate -ne 'CLEAR') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ClearAll cancelled (no CLEAR)'
                } else {
                    $removed = 0
                    foreach ($t in (Get-CredTargets)) {
                        cmdkey "/delete:$t" *>$null
                        if ($LASTEXITCODE -eq 0) { $removed++ }
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Cleared ALL {0} saved credential(s); resources will prompt for passwords' -f $removed)
                }
            }

            'OpenCredManager' {
                Start-Process 'control.exe' -ArgumentList '/name Microsoft.CredentialManager' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Credential Manager opened.' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened Credential Manager'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('{0} credential(s) reported; no action taken' -f $targets.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
