# Console UI. Landing screen = categories + search; everything is driven by
# the registry, so new tools appear automatically.

function Show-LandingMenu {
    $tools = Get-NmmTools
    $categories = $tools | ForEach-Object { $_.Category } | Sort-Object -Unique
    Write-Host ''
    Write-Host ('=' * 66) -ForegroundColor Cyan
    Write-Host (' NMM System Toolkit v9      {0}\{1}' -f $env:COMPUTERNAME, $env:USERNAME) -ForegroundColor Cyan
    Write-Host ('=' * 66) -ForegroundColor Cyan
    if ($script:ToolRuns.Count -gt 0) {
        $recent = @($script:ToolRuns | Select-Object -Last 3 | ForEach-Object { $_.Name })
        Write-Host (' Recent: {0}' -f ($recent -join ' | ')) -ForegroundColor DarkGray
    }
    $index = 1
    $map = @{}
    foreach ($c in $categories) {
        $count = @($tools | Where-Object { $_.Category -eq $c }).Count
        Write-Host (' {0}. {1} ({2} tools)' -f $index, $c, $count)
        $map["$index"] = $c
        $index++
    }
    Write-Host ''
    Write-Host ' Enter: category number | tool number | search text' -ForegroundColor Gray
    Write-Host '        T = ticket summary   X = exit' -ForegroundColor Gray
    return $map
}

function Show-CategoryTools {
    param([Parameter(Mandatory)][string]$Category)
    $tools = Get-NmmTools | Where-Object { $_.Category -eq $Category } | Sort-Object Name
    Write-Host ''
    Write-Host (' --- {0} ---' -f $Category) -ForegroundColor Cyan
    foreach ($t in $tools) {
        $admin = ''
        if ($t.RequiresAdmin) { $admin = ' [admin]' }
        Write-Host (' {0,4}. {1}{2}' -f $t.LegacyId, $t.Name, $admin)
        Write-Host ('       {0}' -f $t.Description) -ForegroundColor Gray
    }
    Write-Host ''
    $selection = Read-Host ' Tool number to run (Enter to go back)'
    if (-not [string]::IsNullOrWhiteSpace($selection)) {
        Invoke-MenuSelection -Selection $selection.Trim()
    }
}

function Invoke-MenuSelection {
    param([Parameter(Mandatory)][string]$Selection)
    $tool = Resolve-NmmTool -Query $Selection
    if ($tool) {
        Invoke-NmmTool -Tool $tool | Out-Null
        Read-Host 'Press Enter to continue' | Out-Null
        return
    }
    $found = @(Search-NmmTools -Term $Selection)
    if ($found.Count -eq 0) {
        Write-Host (" Nothing matches '{0}'." -f $Selection) -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host (' Matches for "{0}":' -f $Selection) -ForegroundColor Cyan
    foreach ($t in $found) {
        Write-Host (' {0,4}. {1}  ({2})' -f $t.LegacyId, $t.Name, $t.Category)
    }
    $pick = Read-Host ' Tool number to run (Enter to cancel)'
    if (-not [string]::IsNullOrWhiteSpace($pick)) {
        $tool = Resolve-NmmTool -Query $pick.Trim()
        if ($tool) {
            Invoke-NmmTool -Tool $tool | Out-Null
            Read-Host 'Press Enter to continue' | Out-Null
        } else {
            Write-Host (" '{0}' did not match any tool number. Enter the number shown in the list." -f $pick.Trim()) -ForegroundColor Yellow
            Read-Host ' Press Enter to go back' | Out-Null
        }
    }
}

function Start-ConsoleMenu {
    if (-not [Environment]::UserInteractive) {
        Write-Host 'ERROR: the menu requires an interactive console. Use -Tool <id> [-Silent] for unattended use.' -ForegroundColor Red
        return
    }
    while ($true) {
        $map = Show-LandingMenu
        $selection = Read-Host ' Select'
        if ([string]::IsNullOrWhiteSpace($selection)) { continue }
        $selection = $selection.Trim()
        if ($selection -match '^[Xx]$') { return }
        if ($selection -match '^[Tt]$') {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $desktop = [Environment]::GetFolderPath('Desktop')   # KFM/OneDrive-redirect aware
            $path = Join-Path $desktop ('NMM-TicketSummary-{0}.txt' -f $stamp)
            $text = Export-TicketSummary
            Write-Host $text
            try {
                Set-Content -Path $path -Value $text -Encoding UTF8 -ErrorAction Stop
                Write-Host (' Saved to {0}' -f $path) -ForegroundColor Green
            } catch {
                Write-Host (' Warning: could not save to {0} - {1}' -f $path, $_) -ForegroundColor Yellow
            }
            Read-Host ' Press Enter to continue' | Out-Null
            continue
        }
        if ($map.ContainsKey($selection)) {
            Show-CategoryTools -Category $map[$selection]
            continue
        }
        Invoke-MenuSelection -Selection $selection
    }
}
