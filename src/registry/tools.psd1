@{
    Tools = @(
        @{
            Id            = 'system-uptime'
            LegacyId      = '20'
            Name          = 'System Uptime and Boot Info'
            Category      = 'Diagnostics'
            Function      = 'Get-SystemUptime'
            Description   = 'Shows last boot time and uptime duration; flags stale uptime'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('uptime','boot','restart','reboot')
        }
        @{
            Id            = 'temp-cleanup'
            LegacyId      = '11'
            Name          = 'Temp Files Cleanup'
            Category      = 'Diagnostics'
            Function      = 'Start-TempFilesCleanup'
            Description   = 'Clears user and system temp folders and reports space reclaimed'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('temp','cleanup','disk','space')
        }
        @{
            Id            = 'system-info'
            LegacyId      = '1'
            Name          = 'System Information'
            Category      = 'Diagnostics'
            Function      = 'Get-SystemInformation'
            Description   = 'OS, hardware, BIOS, and domain summary for the machine'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('system','os','hardware','bios')
        }
        @{
            Id            = 'disk-space'
            LegacyId      = '2'
            Name          = 'Disk Space Analysis'
            Category      = 'Diagnostics'
            Function      = 'Get-DiskSpaceAnalysis'
            Description   = 'Per-volume capacity, free space, and low-space warnings'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('disk','space','storage','volume')
        }
        @{
            Id            = 'network-diagnostics'
            LegacyId      = '3'
            Name          = 'Network Diagnostics'
            Category      = 'Diagnostics'
            Function      = 'Get-NetworkDiagnostics'
            Description   = 'Adapter, IP, gateway, and DNS configuration overview'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('network','ip','dns','adapter')
        }
        @{
            Id            = 'running-processes'
            LegacyId      = '4'
            Name          = 'Running Processes'
            Category      = 'Diagnostics'
            Function      = 'Get-RunningProcesses'
            Description   = 'Top processes by CPU and memory usage'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('process','cpu','memory')
        }
        @{
            Id            = 'services-status'
            LegacyId      = '5'
            Name          = 'Windows Services Status'
            Category      = 'Diagnostics'
            Function      = 'Get-ServicesStatus'
            Description   = 'Stopped automatic services and key service health'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('services','automatic','stopped')
        }
    )
}
