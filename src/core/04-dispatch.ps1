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
    $lower = $Term.ToLower()
    Get-NmmTools | Where-Object {
        $_.Name.ToLower().IndexOf($lower)        -ge 0 -or
        $_.Description.ToLower().IndexOf($lower) -ge 0 -or
        $_.Tags -contains $lower
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
    try {
        & $Tool.Function -Silent:$Silent
    } catch [System.Management.Automation.CommandNotFoundException] {
        # Two very different causes land here and they need different answers.
        # Only a missing TOOL function is registry/implementation drift. A command
        # missing from inside the tool body - a module cmdlet that did not autoload,
        # or a helper absent from the GUI's cloned tool Runspace - is a machine or
        # session problem, and naming the tool instead of the real command sends the
        # technician chasing the registry when nothing is wrong with it.
        $missing = $_.Exception.CommandName
        if ([string]::IsNullOrWhiteSpace($missing) -or $missing -eq $Tool.Function) {
            Write-ToolOutput ("'{0}': function '{1}' not found - registry/implementation drift." -f $Tool.Name, $Tool.Function) -Level Error
        } else {
            Write-ToolOutput ("'{0}': required command '{1}' is not available in this session - the module that provides it is missing or did not load." -f $Tool.Name, $missing) -Level Error
        }
        return 'Failed'
    } catch {
        Write-ToolOutput ("'{0}': unhandled error - {1}" -f $Tool.Name, $_) -Level Error
        return 'Failed'
    }
    $run = $script:ToolRuns | Where-Object { $_.Id -eq $Tool.Id } | Select-Object -Last 1
    if ($run) { return $run.Status }
    return 'Unknown'
}
