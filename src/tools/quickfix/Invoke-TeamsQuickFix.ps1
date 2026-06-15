function Invoke-TeamsQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-quick-fix'

        Write-ToolOutput 'Teams quick fix will: close Teams (classic and new), clear the Teams cache, and restart Teams.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the Teams quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Teams quick fix declined'
            return
        }

        foreach ($name in @('Teams','ms-teams','MSTeams')) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2

        $cacheDirs = @(
            "$env:APPDATA\Microsoft\Teams\Cache",
            "$env:APPDATA\Microsoft\Teams\blob_storage",
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
        )
        $cleared = 0
        foreach ($dir in $cacheDirs) {
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $cleared++
            }
        }

        $classic = "$env:LOCALAPPDATA\Microsoft\Teams\Update.exe"
        if (Test-Path -LiteralPath $classic) {
            Start-Process -FilePath $classic -ArgumentList '--processStart Teams.exe' -ErrorAction SilentlyContinue
        } else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams' -ErrorAction SilentlyContinue
        }

        Complete-ToolRun $run -Status Success -Summary ('Teams closed; {0} cache location(s) cleared; Teams restarted' -f $cleared)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
