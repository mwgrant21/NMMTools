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

        # Detect which Teams variants are present
        $classicDir    = Join-Path $env:APPDATA    'Microsoft\Teams'
        $newTeamsPkg   = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'
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
            foreach ($p in $classicCaches) {
                if (Test-Path $p) {
                    $freedBytes += & $measureSize $p
                    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $variantsCleared += 'classic'
        }

        # New Teams: clear LocalCache contents only
        # NEVER touch LocalState, Settings, or RoamingState
        if ($newTeamsFound) {
            $ntCache = Join-Path $newTeamsPkg 'LocalCache'
            if (Test-Path $ntCache) {
                $freedBytes += & $measureSize $ntCache
                Get-ChildItem $ntCache -Force -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                $variantsCleared += 'New Teams'
            }
        }

        # Restart classic Teams only; New Teams is a Store app and will relaunch itself
        if ($classicFound) {
            $updater = Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\Update.exe'
            if (Test-Path $updater) {
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
