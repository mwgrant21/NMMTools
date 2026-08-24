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

        # Resolve before closing anything: clearing the technician's Teams cache
        # and leaving the user's intact is the exact failure this guards against.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot run the Teams quick fix - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        foreach ($name in @('Teams','ms-teams','MSTeams')) {
            Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2

        $cacheDirs = @(
            (Join-Path $ctx.AppData      'Microsoft\Teams\Cache'),
            (Join-Path $ctx.AppData      'Microsoft\Teams\blob_storage'),
            (Join-Path $ctx.LocalAppData 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache')
        )
        $cleared = 0
        foreach ($dir in $cacheDirs) {
            if (Test-Path -LiteralPath $dir) {
                # Containment-gated: a bare Get-ChildItem | Remove-Item follows a
                # junction planted by the (standard-user) profile owner and deletes
                # the target from THIS elevated process.
                if (-not (Remove-UserPathContent -Context $ctx -Path $dir)) { continue }
                $cleared++
            }
        }

        # Both relaunch routes start Teams in the CALLING account's session, so
        # they are only correct when that account is the target user.
        $relaunch = 'ask the user to reopen Teams'
        if (-not $ctx.IsRedirected) {
            $classic = Join-Path $ctx.LocalAppData 'Microsoft\Teams\Update.exe'
            if (Test-Path -LiteralPath $classic) {
                Start-Process -FilePath $classic -ArgumentList '--processStart Teams.exe' -ErrorAction SilentlyContinue
            } else {
                Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams' -ErrorAction SilentlyContinue
            }
            $relaunch = 'Teams restarted'
        } else {
            Write-ToolOutput 'Teams was closed. Ask the user to reopen it - it cannot be relaunched as them from an elevated session.' -Level Warning
        }

        Complete-ToolRun $run -Status Success -Summary ('Teams closed for {0}; {1} cache location(s) cleared; {2}' -f $ctx.DisplayName, $cleared, $relaunch)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
