# Console UI. Landing screen lists EVERY tool grouped under category headers with
# full (wrapped) descriptions; everything is driven by the registry, so new tools
# appear automatically. Run a tool by typing its number/Q#/Id, or type text to search.

function Get-NmmLegacyIdSortKey {
    # Sortable key for a LegacyId: numeric ids first (as integers), then Q# ids in
    # Q1..Q9 order, then anything unexpected. Never throws on a non-numeric id.
    param([Parameter(Mandatory)][string]$LegacyId)
    if ($LegacyId -match '^\d+$') { return [int]$LegacyId }
    if ($LegacyId -match '^Q(\d+)$') { return 1000 + [int]$Matches[1] }
    return 100000
}

function Get-WrappedLines {
    # Greedily word-wrap $Text to lines no wider than $Width. Returns a string[]
    # (possibly empty); blank/whitespace input yields an empty array.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$Width
    )
    if ($Width -lt 1) { $Width = 1 }
    $words = @($Text -split '\s+' | Where-Object { $_ -ne '' })
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($w in $words) {
        if ($current -eq '') {
            $current = $w
        } elseif (($current.Length + 1 + $w.Length) -le $Width) {
            $current = $current + ' ' + $w
        } else {
            $lines.Add($current)
            $current = $w
        }
    }
    if ($current -ne '') { $lines.Add($current) }
    return $lines.ToArray()
}

function Show-LandingMenu {
    # Clear only in a real interactive console - never during tests (Silent sink) or headless runs.
    if ($script:OutputSink -ne 'Silent' -and [Environment]::UserInteractive) {
        try { Clear-Host } catch { }
    }
    $tools = Get-NmmTools
    $categories = @($tools | ForEach-Object { $_.Category } | Sort-Object -Unique)

    Write-Host ''
    Write-Host ('=' * 66) -ForegroundColor Cyan
    Write-Host (' NMM System Toolkit v9      {0}\{1}' -f $env:COMPUTERNAME, $env:USERNAME) -ForegroundColor Cyan
    Write-Host ('=' * 66) -ForegroundColor Cyan
    if ($script:ToolRuns.Count -gt 0) {
        $recent = @($script:ToolRuns | Select-Object -Last 3 | ForEach-Object { $_.Name })
        Write-Host (' Recent: {0}' -f ($recent -join ' | ')) -ForegroundColor DarkGray
    }

    # Width for description wrapping; falls back to 80 in a redirected/headless host.
    $width = 80
    try { $cw = [Console]::WindowWidth; if ($cw -and $cw -gt 0) { $width = [int]$cw } } catch { $width = 80 }
    $descIndent = '       '   # 7 spaces: aligns the wrapped description under the tool name
    $descWidth = $width - $descIndent.Length - 1
    if ($descWidth -lt 30) { $descWidth = 30 }

    foreach ($c in $categories) {
        $catTools = @($tools | Where-Object { $_.Category -eq $c } | Sort-Object { Get-NmmLegacyIdSortKey $_.LegacyId })
        Write-Host ''
        Write-Host (' -- {0} ({1} tools) --' -f $c, $catTools.Count) -ForegroundColor Cyan
        foreach ($t in $catTools) {
            $admin = ''
            if ($t.RequiresAdmin) { $admin = ' [admin]' }
            Write-Host (' {0,4}. {1}{2}' -f $t.LegacyId, $t.Name, $admin)
            foreach ($line in (Get-WrappedLines -Text $t.Description -Width $descWidth)) {
                Write-Host ($descIndent + $line) -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ''
    Write-Host ' Enter: tool number (e.g. 54 or Q3) | search text' -ForegroundColor Gray
    Write-Host '        T = save session summary (for tickets)   X = exit' -ForegroundColor Gray
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
        Show-LandingMenu
        $selection = Read-Host ' Select tool number/Q#, search text, or X to exit'
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
        Invoke-MenuSelection -Selection $selection
    }
}
