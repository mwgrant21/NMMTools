# Per-technician usage store (NMMTools\usage.json in %LOCALAPPDATA%). Records interactive tool
# runs and ranks the most-used for the menu's Common Fixes section. All IO failures are swallowed -
# usage tracking must never take down a tool run or the menu.

$script:UsageFilePathOverride = $null   # tests set this to a temp file

function Get-NmmUsagePath {
    if ($script:UsageFilePathOverride) { return $script:UsageFilePathOverride }
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }
    return (Join-Path $base 'NMMTools\usage.json')
}

function Import-NmmUsage {
    # Returns @{ <toolId> = @{ Count = <int>; Last = <string 'o'> } }. Missing/corrupt -> @{}. Never throws.
    $path = Get-NmmUsagePath
    $table = @{}
    if (-not (Test-Path $path -PathType Leaf)) { return $table }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($json -and $json.Tools) {
            foreach ($p in $json.Tools.PSObject.Properties) {
                # ConvertFrom-Json silently coerces an ISO-8601 string back into
                # [DateTime]. A plain [string] cast on that renders the culture
                # short format (MM/dd/yyyy HH:mm:ss), which drops the fractional
                # seconds the tie-break needs and sorts by month before year.
                # Re-render through the round-trip format to undo both.
                $rawLast = $p.Value.Last
                if ($rawLast -is [datetime]) { $last = $rawLast.ToString('o') }
                else { $last = [string]$rawLast }
                $table[$p.Name] = @{ Count = [int]$p.Value.Count; Last = $last }
            }
        }
    } catch {
        return @{}
    }
    return $table
}

function Add-NmmUsage {
    # Increment a tool's count, stamp Last=now, persist. IO failure swallowed. Callers gate on sink.
    param([Parameter(Mandatory)][string]$Id)
    try {
        $table = Import-NmmUsage
        if ($table.ContainsKey($Id)) {
            $table[$Id]['Count'] = [int]$table[$Id]['Count'] + 1
        } else {
            $table[$Id] = @{ Count = 1; Last = '' }
        }
        $table[$Id]['Last'] = (Get-Date).ToString('o')
        $path = Get-NmmUsagePath
        $dir = Split-Path $path -Parent
        if ($dir -and -not (Test-Path $dir -PathType Container)) {
            New-Item -ItemType Directory -Force $dir -ErrorAction Stop | Out-Null
        }
        $obj = [PSCustomObject]@{ Version = 1; Tools = [PSCustomObject]$table }
        Set-Content -Path $path -Value ($obj | ConvertTo-Json -Depth 4) -Encoding UTF8 -ErrorAction Stop
    } catch {
        # drop the write, keep going
    }
}

function Get-NmmCommonFixes {
    # Top-$Max tools by usage (Count desc, then Last desc). Resolves ids against the live registry,
    # skipping ids no longer present. Returns @() when there is no usage.
    param([int]$Max = 6)
    $table = Import-NmmUsage
    if ($table.Count -eq 0) { return @() }
    # Sort Last chronologically, not as text: a culture-formatted stamp left by
    # an older build (MM/dd/yyyy) orders by month before year as a string.
    # Unparseable values sort oldest rather than throwing.
    $ranked = $table.GetEnumerator() | Sort-Object `
        @{ Expression = { [int]$_.Value['Count'] }; Descending = $true }, `
        @{ Expression = {
                $parsed = [datetime]::MinValue
                if ([datetime]::TryParse([string]$_.Value['Last'], [ref]$parsed)) { $parsed }
                else { [datetime]::MinValue }
            }; Descending = $true }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $ranked) {
        if ($out.Count -ge $Max) { break }
        $tool = Resolve-NmmTool -Query $entry.Key
        if ($tool) { [void]$out.Add($tool) }
    }
    return $out.ToArray()
}
