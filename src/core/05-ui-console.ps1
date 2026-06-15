# Console UI. Landing screen lists EVERY tool in two color-coded columns grouped under
# a v8-style banner per category; everything is driven by the registry, so new tools
# appear automatically. Run a tool by typing its number/Q#/Id, or type text to search.

function Get-NmmLegacyIdSortKey {
    # Sortable key for a LegacyId: numeric ids first (as integers), then Q# ids in
    # Q1..Q9 order, then anything unexpected. Never throws on a non-numeric id.
    param([Parameter(Mandatory)][string]$LegacyId)
    if ($LegacyId -match '^\d+$') { return [int]$LegacyId }
    if ($LegacyId -match '^Q(\d+)$') { return 1000 + [int]$Matches[1] }
    return 100000
}

function Get-CategoryColor {
    # Map a category to its v8 section colour (a valid [ConsoleColor] name). Gray for unknown.
    param([Parameter(Mandatory)][string]$Category)
    switch ($Category) {
        'Browser'     { 'White' }
        'Cloud'       { 'Yellow' }
        'Diagnostics' { 'Cyan' }
        'Laptop'      { 'Green' }
        'QuickFix'    { 'Magenta' }
        'Repair'      { 'Red' }
        'Security'    { 'DarkYellow' }
        'User'        { 'Blue' }
        default       { 'Gray' }
    }
}

function Format-MenuColumns {
    # Pack pre-formatted cell strings into $Columns column-major columns.
    # rows = ceil(N / Columns); row r, column c -> Cells[c*rows + r]. Non-last columns
    # are PadRight($ColumnWidth); each row is TrimEnd()'d. Returns string[] (empty when no cells).
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Cells,
        [Parameter(Mandatory)][int]$Columns,
        [Parameter(Mandatory)][int]$ColumnWidth
    )
    if ($Columns -lt 1) { $Columns = 1 }
    $out = New-Object System.Collections.Generic.List[string]
    $n = $Cells.Count
    if ($n -eq 0) { return $out.ToArray() }
    $rows = [int][math]::Ceiling($n / [double]$Columns)
    for ($r = 0; $r -lt $rows; $r++) {
        $line = ''
        for ($c = 0; $c -lt $Columns; $c++) {
            $idx = $c * $rows + $r
            if ($idx -lt $n) {
                if ($c -lt ($Columns - 1)) {
                    $line += $Cells[$idx].PadRight($ColumnWidth)
                } else {
                    $line += $Cells[$idx]
                }
            }
        }
        $out.Add($line.TrimEnd())
    }
    return $out.ToArray()
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

    # Layout width; falls back to 80 in a redirected/headless host. Two columns when wide enough.
    $width = 80
    try { $cw = [Console]::WindowWidth; if ($cw -and $cw -gt 0) { $width = [int]$cw } } catch { $width = 80 }
    $usable = $width - 1
    if ($usable -lt 40) { $usable = 40 }
    $columns = 2
    if ($usable -lt 72) { $columns = 1 }
    $colWidth = [int][math]::Floor($usable / $columns)
    if ($colWidth -lt 30) { $colWidth = 30 }
    $bannerWidth = $columns * $colWidth

    foreach ($cat in $categories) {
        $color = Get-CategoryColor $cat
        $catTools = @($tools | Where-Object { $_.Category -eq $cat } | Sort-Object { Get-NmmLegacyIdSortKey $_.LegacyId })

        # v8-style boxed banner in the category colour.
        $inner = $bannerWidth - 2
        $bar = '+' + ('=' * $inner) + '+'
        $titleText = ('  {0} ({1} tools)' -f $cat, $catTools.Count)
        if ($titleText.Length -gt $inner) { $titleText = $titleText.Substring(0, $inner) }
        $titleLine = '|' + $titleText.PadRight($inner) + '|'
        Write-Host ''
        Write-Host $bar -ForegroundColor $color
        Write-Host $titleLine -ForegroundColor $color
        Write-Host $bar -ForegroundColor $color

        # One cell per tool: " <id>. <Name>", truncated to fit a column.
        $cellMax = $colWidth - 1
        $cells = @()
        foreach ($t in $catTools) {
            $cell = ' {0,4}. {1}' -f $t.LegacyId, $t.Name
            if ($cell.Length -gt $cellMax) { $cell = $cell.Substring(0, $cellMax - 3) + '...' }
            $cells += $cell
        }
        foreach ($row in (Format-MenuColumns -Cells $cells -Columns $columns -ColumnWidth $colWidth)) {
            Write-Host $row -ForegroundColor $color
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
