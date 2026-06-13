function Export-HardwareSummary {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'hardware-summary'

        Write-ToolOutput 'Collecting hardware information...'

        # Singleton CIM queries — Select-Object -First 1 guards against unexpected multi-instance results
        $cs   = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
        $os   = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS            | Select-Object -First 1
        $proc = Get-CimInstance Win32_Processor       | Select-Object -First 1   # first socket; multi-socket reports socket 0

        $memory   = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
        $totalRAM = [math]::Round($memory.Sum / 1GB, 2)

        $disks = @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 })

        # Optional hardware sections — Detail level; present only when the device is detected
        $battery   = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        $bitlocker = Get-BitLockerVolume -ErrorAction SilentlyContinue |
            Where-Object { $_.VolumeType -eq 'OperatingSystem' } | Select-Object -First 1

        # Build flat-text report (matches v8 section layout verbatim)
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $reportFile  = Join-Path $desktopPath ('Hardware_Summary_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

        $report = @()
        $report += '========================================'
        $report += 'NMM System Toolkit - Hardware Summary'
        $report += ('Generated: {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date))
        $report += '========================================'
        $report += ''
        $report += '=== SYSTEM INFORMATION ==='
        $report += "Computer Name: $($cs.Name)"
        $report += "Manufacturer: $($cs.Manufacturer)"
        $report += "Model: $($cs.Model)"
        $report += "Serial Number: $($bios.SerialNumber)"
        $report += "BIOS Version: $($bios.SMBIOSBIOSVersion)"
        $report += "BIOS Date: $($bios.ReleaseDate)"
        $report += "OS: $($os.Caption) $($os.OSArchitecture)"
        $report += "OS Version: $($os.Version)"
        $report += "Last Boot: $($os.LastBootUpTime)"
        $report += ''
        $report += '=== PROCESSOR ==='
        $report += "CPU: $($proc.Name)"
        $report += "Cores: $($proc.NumberOfCores)"
        $report += "Logical Processors: $($proc.NumberOfLogicalProcessors)"
        $report += "Max Clock Speed: $($proc.MaxClockSpeed) MHz"
        $report += ''
        $report += '=== MEMORY ==='
        $report += "Total RAM: $totalRAM GB"
        $report += ''
        $report += '=== STORAGE ==='
        foreach ($disk in $disks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $report += "$($disk.DeviceID) - Size: $sizeGB GB, Free: $freeGB GB"
        }
        $report += ''

        if ($battery) {
            $report += '=== BATTERY ==='
            $report += "Design Capacity: $($battery.DesignCapacity) mWh"
            $report += "Full Charge Capacity: $($battery.FullChargeCapacity) mWh"
            if ($battery.DesignCapacity -gt 0) {
                $wear    = [math]::Round((1 - ($battery.FullChargeCapacity / $battery.DesignCapacity)) * 100, 1)
                $report += "Battery Wear: $wear%"
            }
            $report += ''
        }

        if ($bitlocker) {
            $report += '=== BITLOCKER ==='
            $report += "Status: $($bitlocker.VolumeStatus)"
            $report += "Protection Status: $($bitlocker.ProtectionStatus)"
            $report += ''
        }

        # Summary rows — emit BEFORE file write so console output is never swallowed by a write failure
        Write-ToolOutput ('Computer  : {0} ({1} {2})' -f $cs.Name, $cs.Manufacturer, $cs.Model)
        Write-ToolOutput ('Serial    : {0}' -f $bios.SerialNumber)
        Write-ToolOutput ('CPU       : {0}' -f $proc.Name) -Level Detail
        Write-ToolOutput ('RAM       : {0} GB' -f $totalRAM) -Level Detail

        $reportWritten = $false
        try {
            $report | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction Stop
            $reportWritten = $true
            Write-ToolOutput ('Report    : {0}' -f $reportFile)
        }
        catch {
            Write-ToolOutput ('Could not write report to {0}: {1}' -f $reportFile, $_.Exception.Message) -Level Warning
        }

        if ($reportWritten) {
            Complete-ToolRun $run -Status Success -Summary (
                '{0} | {1} | SN {2} | {3} GB RAM | Report: {4}' -f
                $cs.Name, $cs.Model, $bios.SerialNumber, $totalRAM, (Split-Path $reportFile -Leaf))
        } else {
            Complete-ToolRun $run -Status Warning -Summary (
                '{0} | {1} | SN {2} | {3} GB RAM | Report: file write failed' -f
                $cs.Name, $cs.Model, $bios.SerialNumber, $totalRAM)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
