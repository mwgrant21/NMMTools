function Get-SystemInformation {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'system-info'

        $os   = Get-CimInstance Win32_OperatingSystem
        $cs   = Get-CimInstance Win32_ComputerSystem
        $bios = Get-CimInstance Win32_BIOS
        $proc = Get-CimInstance Win32_Processor

        $totalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)

        Write-ToolOutput ('Computer Name  : {0}' -f $cs.Name)
        Write-ToolOutput ('OS             : {0}' -f $os.Caption)
        Write-ToolOutput ('OS Build       : {0}' -f $os.Version)
        Write-ToolOutput ('Architecture   : {0}' -f $os.OSArchitecture)
        Write-ToolOutput ('Manufacturer   : {0}' -f $cs.Manufacturer)
        Write-ToolOutput ('Model          : {0}' -f $cs.Model)
        Write-ToolOutput ('Processor      : {0}' -f $proc.Name)
        Write-ToolOutput ('Cores          : {0}' -f $proc.NumberOfCores)
        Write-ToolOutput ('Total RAM      : {0} GB' -f $totalRamGB)
        Write-ToolOutput ('Serial Number  : {0}' -f $bios.SerialNumber)
        Write-ToolOutput ('Last Boot      : {0:g}' -f $os.LastBootUpTime)

        Complete-ToolRun $run -Status Success -Summary (
            '{0} | {1} | {2} GB RAM | {3}' -f $cs.Name, $os.Caption, $totalRamGB, $proc.Name)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
