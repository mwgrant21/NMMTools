function Get-WindowsUpdates {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-updates'

        $hotfixes = @(Get-HotFix | Sort-Object InstalledOn -Descending)

        if ($hotfixes.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No hotfixes found via Get-HotFix'
            return
        }

        $last = $hotfixes | Select-Object -First 1

        # Primary data rows use Info (default level)
        Write-ToolOutput ('HotFix ID    : {0}' -f $last.HotFixID)
        Write-ToolOutput ('Description  : {0}' -f $last.Description)
        $dateStr = if ($last.InstalledOn) { '{0:d}' -f $last.InstalledOn } else { 'unknown' }
        Write-ToolOutput ('Installed On : {0}' -f $dateStr)

        Complete-ToolRun $run -Status Success -Summary ('Last: {0} installed {1}' -f $last.HotFixID, $dateStr)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
