function Get-DriverIntegrityScan {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'driver-integrity-scan'

        # This scan calls DISM and can take 1-3 minutes on a large driver store
        Write-ToolOutput 'Scanning Windows driver store via DISM (may take 1-3 min)...' -Level Detail

        $allDrivers = @(Get-WindowsDriver -Online -All -ErrorAction SilentlyContinue)

        if ($allDrivers.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'Get-WindowsDriver returned no results; DISM access or Windows 10/11 required'
            return
        }

        # Info headline: total driver count before per-category detail rows
        Write-ToolOutput ('Total drivers found: {0}' -f $allDrivers.Count)

        # Group by inf filename to detect duplicate driver packages
        $driverGroups = $allDrivers | Group-Object -Property Driver
        $duplicateDrivers = @()
        foreach ($group in $driverGroups) {
            if ($group.Count -gt 1) {
                $versions = @($group.Group |
                    Select-Object -ExpandProperty Version |
                    Where-Object { $_ } |
                    Sort-Object -Unique)
                $duplicateDrivers += [PSCustomObject]@{
                    Driver   = $group.Name
                    Count    = $group.Count
                    Versions = ($versions -join ', ')
                }
            }
        }

        # Flag drivers whose ProviderName is absent or not in the trusted-vendor list
        # v8 referenced a 'Publisher' property that does not exist on Get-WindowsDriver objects;
        # ProviderName is the correct DISM property - adjustment reported.
        $unknownPublisherDrivers = @()
        $staleDrivers = @()
        $cutoff = (Get-Date).AddDays(-1095)   # 3 years = 1095 days, matching v8 threshold

        foreach ($driver in $allDrivers) {
            $pub   = [string]$driver.ProviderName
            $class = if ($driver.ClassDescription) { [string]$driver.ClassDescription } else { [string]$driver.ClassName }

            if ($pub -eq '' -or $pub -notmatch 'Microsoft|Intel|AMD|NVIDIA|Realtek|Qualcomm') {
                $unknownPublisherDrivers += [PSCustomObject]@{
                    Driver    = [string]$driver.Driver
                    Class     = $class
                    Publisher = if ($pub) { $pub } else { 'Unknown' }
                    Version   = [string]$driver.Version
                }
            }

            $driverDate = $null
            if ($driver.Date -is [datetime]) {
                $driverDate = $driver.Date
            } elseif ($driver.Date) {
                try { $driverDate = [datetime]::Parse([string]$driver.Date) } catch { }
            }
            if ($driverDate -and $driverDate -lt $cutoff) {
                $staleDrivers += [PSCustomObject]@{
                    Driver  = [string]$driver.Driver
                    Class   = $class
                    Date    = ('{0:yyyy-MM-dd}' -f $driverDate)
                    Version = [string]$driver.Version
                }
            }
        }

        # Unknown-publisher, duplicate, and stale rows use Detail; up to 10 per category
        if ($unknownPublisherDrivers.Count -gt 0) {
            Write-ToolOutput ('Unknown-publisher drivers: {0}' -f $unknownPublisherDrivers.Count) -Level Warning
            foreach ($d in ($unknownPublisherDrivers | Select-Object -First 10)) {
                Write-ToolOutput ('  {0}  [{1}]  {2}' -f $d.Driver, $d.Class, $d.Publisher) -Level Detail
            }
            if ($unknownPublisherDrivers.Count -gt 10) {
                Write-ToolOutput ('  ... and {0} more' -f ($unknownPublisherDrivers.Count - 10)) -Level Detail
            }
        }

        if ($duplicateDrivers.Count -gt 0) {
            Write-ToolOutput ('Duplicate driver packages: {0}' -f $duplicateDrivers.Count) -Level Warning
            foreach ($d in ($duplicateDrivers | Select-Object -First 10)) {
                Write-ToolOutput ('  {0}  count:{1}  versions:{2}' -f $d.Driver, $d.Count, $d.Versions) -Level Detail
            }
            if ($duplicateDrivers.Count -gt 10) {
                Write-ToolOutput ('  ... and {0} more' -f ($duplicateDrivers.Count - 10)) -Level Detail
            }
        }

        if ($staleDrivers.Count -gt 0) {
            Write-ToolOutput ('Stale drivers (3yr+): {0}' -f $staleDrivers.Count) -Level Warning
            foreach ($d in ($staleDrivers | Select-Object -First 10)) {
                Write-ToolOutput ('  {0}  [{1}]  {2}' -f $d.Driver, $d.Class, $d.Date) -Level Detail
            }
            if ($staleDrivers.Count -gt 10) {
                Write-ToolOutput ('  ... and {0} more' -f ($staleDrivers.Count - 10)) -Level Detail
            }
        }

        # Optional report export; default Skip keeps -Silent and unattended runs clean
        $exportChoice = Read-ToolChoice -Prompt 'Export driver integrity report to Desktop?' `
            -Choices @('Export', 'Skip') -Default 'Skip' -Silent:$Silent

        if ($exportChoice -eq 'Export') {
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $reportFile  = Join-Path $desktopPath ('DriverIntegrityScan_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add('Driver Integrity Scan Report')
            $lines.Add(('Generated: {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)))
            $lines.Add('')
            $lines.Add(('Total Drivers     : {0}' -f $allDrivers.Count))
            $lines.Add(('Unknown Publisher : {0}' -f $unknownPublisherDrivers.Count))
            $lines.Add(('Duplicates        : {0}' -f $duplicateDrivers.Count))
            $lines.Add(('Stale (3yr+)      : {0}' -f $staleDrivers.Count))
            $lines.Add('')
            $lines.Add('=== UNKNOWN PUBLISHER ===')
            foreach ($d in $unknownPublisherDrivers) { $lines.Add(('  {0}  [{1}]  {2}' -f $d.Driver, $d.Class, $d.Publisher)) }
            $lines.Add('')
            $lines.Add('=== DUPLICATES ===')
            foreach ($d in $duplicateDrivers) { $lines.Add(('  {0}  count:{1}  versions:{2}' -f $d.Driver, $d.Count, $d.Versions)) }
            $lines.Add('')
            $lines.Add('=== STALE ===')
            foreach ($d in $staleDrivers) { $lines.Add(('  {0}  [{1}]  {2}' -f $d.Driver, $d.Class, $d.Date)) }
            try {
                $lines | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction Stop
                Write-ToolOutput ('Report: {0}' -f $reportFile)
            } catch {
                Write-ToolOutput ('Report write failed: {0}' -f $_.Exception.Message) -Level Warning
            }
        }

        $issueCount = $unknownPublisherDrivers.Count + $duplicateDrivers.Count + $staleDrivers.Count
        $status = if ($issueCount -eq 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status -Summary (
            '{0} drivers scanned - {1} unknown-publisher, {2} duplicate, {3} stale' -f
            $allDrivers.Count, $unknownPublisherDrivers.Count, $duplicateDrivers.Count, $staleDrivers.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
