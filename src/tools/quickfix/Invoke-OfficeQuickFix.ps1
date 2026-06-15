function Invoke-OfficeQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'office-quick-fix'

        Write-ToolOutput 'Office quick fix will: close Office apps, clear Office sign-in credentials, and launch a Click-to-Run update.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the Office quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Office quick fix declined'
            return
        }

        foreach ($name in @('OUTLOOK','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS')) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }

        $cleared = 0
        foreach ($line in (cmdkey /list 2>$null)) {
            if ($line -match '^\s*Target:\s*(.+?)\s*$') {
                $t = $Matches[1]
                if ($t -match 'MicrosoftOffice') {
                    cmdkey /delete:$t 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { $cleared++ }
                }
            }
        }

        $c2r = 'C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'
        $updateLaunched = $false
        if (Test-Path -LiteralPath $c2r) {
            Start-Process -FilePath $c2r -ArgumentList '/update user' -ErrorAction SilentlyContinue
            $updateLaunched = $true
        }

        Complete-ToolRun $run -Status Success -Summary ('Office apps closed, {0} credential(s) cleared, C2R update launched={1}' -f $cleared, $updateLaunched)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
