function Invoke-LoginQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'login-quick-fix'

        Write-ToolOutput 'Login quick fix will: clear Office/M365 sign-in credentials and report the device join state. The user must sign in again afterward.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the login quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Login quick fix declined'
            return
        }

        $cleared = 0
        foreach ($line in (cmdkey /list 2>$null)) {
            if ($line -match '^\s*Target:\s*(.+?)\s*$') {
                $t = $Matches[1]
                if ($t -match 'MicrosoftOffice|Office') {
                    cmdkey /delete:$t 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { $cleared++ }
                }
            }
        }

        Write-ToolOutput 'Device join state:' -Level Detail
        foreach ($l in (dsregcmd /status 2>$null | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined')) {
            Write-ToolOutput ('  {0}' -f ([string]$l).Trim()) -Level Detail
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} Office credential(s) cleared; user should sign in again' -f $cleared)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
