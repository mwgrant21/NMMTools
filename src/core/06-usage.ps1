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
                $table[$p.Name] = @{ Count = [int]$p.Value.Count; Last = [string]$p.Value.Last }
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
    $ranked = $table.GetEnumerator() | Sort-Object `
        @{ Expression = { [int]$_.Value['Count'] }; Descending = $true }, `
        @{ Expression = { [string]$_.Value['Last'] }; Descending = $true }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $ranked) {
        if ($out.Count -ge $Max) { break }
        $tool = Resolve-NmmTool -Query $entry.Key
        if ($tool) { [void]$out.Add($tool) }
    }
    return $out.ToArray()
}
