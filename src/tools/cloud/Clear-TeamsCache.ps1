function Clear-TeamsCache {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-cache'

        $choice = Read-ToolChoice `
            -Prompt 'Close Teams and clear its cache now? (drops active calls)' `
            -Choices @('Yes', 'No') `
            -Default 'No' `
            -Silent:$Silent

        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined'
            return
        }

        # Teams caches are per-user. Resolve the owner before detecting anything:
        # otherwise a redirected session detects the technician's Teams install
        # and then clears the technician's cache.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot clear the Teams cache - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        # Detect which Teams variants are present
        $classicDir    = Join-Path $ctx.AppData      'Microsoft\Teams'
        $newTeamsPkg   = Join-Path $ctx.LocalAppData 'Packages\MSTeams_8wekyb3d8bbwe'
        $classicFound  = Test-Path $classicDir
        $newTeamsFound = Test-Path $newTeamsPkg

        if (-not $classicFound -and -not $newTeamsFound) {
            Complete-ToolRun $run -Status Warning -Summary 'No Teams installation detected (classic or New Teams)'
            return
        }

        # Stop both classic and New Teams before clearing
        Stop-Process -Name Teams    -Force -ErrorAction SilentlyContinue
        Stop-Process -Name ms-teams -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Measure a directory tree in bytes before clearing
        $measureSize = {
            param([string]$Path)
            if (-not (Test-Path $Path)) { return [int64]0 }
            $s = (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                  Measure-Object Length -Sum).Sum
            if ($s) { [int64]$s } else { [int64]0 }
        }

        $freedBytes      = [int64]0
        $variantsCleared = @()

        # Classic Teams: cache, blob_storage, databases, GPUcache
        if ($classicFound) {
            $classicCaches = @(
                (Join-Path $classicDir 'Cache'),
                (Join-Path $classicDir 'blob_storage'),
                (Join-Path $classicDir 'databases'),
                (Join-Path $classicDir 'GPUcache')
            )
            $classicCacheFound = $false
            foreach ($p in $classicCaches) {
                if (Test-Path $p) {
                    # Gate BEFORE measuring: $measureSize recurses, and recursing
                    # a junction to System32 is both slow and pointless. The gate
                    # rejects reparse points and anything outside the profile.
                    if (-not (Test-UserPathContained -Context $ctx -Path $p)) { continue }
                    $classicCacheFound = $true
                    $freedBytes += & $measureSize $p
                    # Clear contents through the helper, then drop the now-empty
                    # directory non-recursively. Remove-Item -Recurse on a junction
                    # deletes the TARGET's contents in PS 5.1.
                    [void](Remove-UserPathContent -Context $ctx -Path $p)
                    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                }
            }
            if ($classicCacheFound) { $variantsCleared += 'classic' }
        }

        # New Teams: clear LocalCache contents only
        # NEVER touch LocalState, Settings, or RoamingState
        if ($newTeamsFound) {
            $ntCache = Join-Path $newTeamsPkg 'LocalCache'
            if (Test-Path $ntCache) {
                # Gate before measuring, for the same reason as the classic branch.
                if (Test-UserPathContained -Context $ctx -Path $ntCache) {
                    $freedBytes += & $measureSize $ntCache
                    [void](Remove-UserPathContent -Context $ctx -Path $ntCache)
                    $variantsCleared += 'New Teams'
                }
            }
        }

        # Restart classic Teams only; New Teams is a Store app and will relaunch itself
        if ($classicFound) {
            $updater = Join-Path $ctx.LocalAppData 'Microsoft\Teams\Update.exe'
            # Launching the updater from a redirected session would start Teams
            # as the technician, in the wrong session and against the wrong
            # profile, so the relaunch is left to the user.
            if ($ctx.IsRedirected) {
                Write-ToolOutput 'Teams was closed. Ask the user to reopen it - it cannot be relaunched as them from an elevated session.' -Level Warning
            } elseif (Test-Path $updater) {
                Start-Process $updater -ArgumentList '--processStart Teams.exe'
                Write-ToolOutput 'Classic Teams relaunch initiated.' -Level Detail
            }
        }

        $freedMB  = [math]::Round($freedBytes / 1MB, 1)
        $varLabel = 'none'
        if ($variantsCleared.Count -gt 0) { $varLabel = $variantsCleared -join ' + ' }

        Complete-ToolRun $run -Status Success -Summary (
            'Teams cache cleared; variants: {0}; approx {1} MB freed' -f $varLabel, $freedMB)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
