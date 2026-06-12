# Registry-driven dispatch. The menu, search, and CLI all resolve tools here.

function Get-NmmTools {
    @($script:RegistryData.Tools)
}

function Resolve-NmmTool {
    param([Parameter(Mandatory)][string]$Query)
    $tools = Get-NmmTools
    $hit = $tools | Where-Object { $_.Id -eq $Query } | Select-Object -First 1
    if (-not $hit) {
        $hit = $tools | Where-Object { $_.LegacyId -eq $Query } | Select-Object -First 1
    }
    return $hit
}

function Search-NmmTools {
    param([Parameter(Mandatory)][string]$Term)
    Get-NmmTools | Where-Object {
        $_.Name -like "*$Term*" -or
        $_.Description -like "*$Term*" -or
        $_.Tags -contains $Term.ToLower()
    }
}

function Invoke-NmmTool {
    param(
        [Parameter(Mandatory)][hashtable]$Tool,
        [switch]$Silent,
        [switch]$Force
    )
    if ($Silent -and -not $Tool.SilentCapable) {
        Write-ToolOutput ("'{0}' requires interaction and cannot run silently." -f $Tool.Name) -Level Error
        return 'Refused'
    }
    if ($Silent -and $Tool.Risk -eq 'Disruptive' -and -not $Force) {
        Write-ToolOutput ("'{0}' is disruptive; add -Force to run it silently." -f $Tool.Name) -Level Error
        return 'Refused'
    }
    if ($Tool.RequiresAdmin -and -not $script:IsAdmin) {
        Write-ToolOutput ("'{0}' requires administrator rights. Re-launch elevated." -f $Tool.Name) -Level Error
        return 'Refused'
    }
    & $Tool.Function -Silent:$Silent
    $run = $script:ToolRuns | Where-Object { $_.Id -eq $Tool.Id } | Select-Object -Last 1
    if ($run) { return $run.Status }
    return 'Unknown'
}
