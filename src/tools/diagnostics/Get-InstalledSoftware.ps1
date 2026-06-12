function Get-InstalledSoftware {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'installed-software'

        $regPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $software = @()
        foreach ($path in $regPaths) {
            $software += @(Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher)
        }

        $software = @($software | Sort-Object DisplayName | Select-Object -Property * -Unique)

        if ($software.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No applications found in registry uninstall keys'
            return
        }

        Write-ToolOutput ('Total installed applications: {0}' -f $software.Count)
        # Scan rows use Detail; showing first 20 matches v8 display behavior
        foreach ($s in ($software | Select-Object -First 20)) {
            Write-ToolOutput ('{0}  {1}  [{2}]' -f $s.DisplayName, $s.DisplayVersion, $s.Publisher) -Level Detail
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} applications found' -f $software.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
