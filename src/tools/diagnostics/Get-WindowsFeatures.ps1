function Get-WindowsFeatures {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-features'

        # v8: Get-WindowsOptionalFeature -Online - requires admin; filters to Enabled features
        $features = @(Get-WindowsOptionalFeature -Online |
            Where-Object { $_.State -eq 'Enabled' } |
            Select-Object FeatureName |
            Sort-Object FeatureName)

        if ($features.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No enabled Windows optional features found'
            return
        }

        Write-ToolOutput ('Enabled Windows optional features: {0}' -f $features.Count)
        # Each feature is a scan row; Detail level for the listing
        foreach ($f in $features) {
            Write-ToolOutput $f.FeatureName -Level Detail
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} optional feature(s) enabled' -f $features.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
