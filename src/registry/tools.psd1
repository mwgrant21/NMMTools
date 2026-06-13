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
            Description   = 'Active network adapters: name, status, link speed, and IPv4 address'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('network','ip','ipv4','adapter')
        }
        @{
            Id            = 'running-processes'
            LegacyId      = '4'
            Name          = 'Running Processes'
            Category      = 'Diagnostics'
            Function      = 'Get-RunningProcesses'
            Description   = 'Top 10 processes by memory (WorkingSet)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('process','workingset','memory')
        }
        @{
            Id            = 'services-status'
            LegacyId      = '5'
            Name          = 'Windows Services Status'
            Category      = 'Diagnostics'
            Function      = 'Get-ServicesStatus'
            Description   = 'All services grouped by status with counts'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('services','automatic','stopped')
        }
        @{
            Id            = 'event-log-errors'
            LegacyId      = '6'
            Name          = 'Recent Event Log Errors'
            Category      = 'Diagnostics'
            Function      = 'Get-EventLogErrors'
            Description   = 'Recent System/Application error events (Level 2) in the last 24 hours'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('events','errors','eventlog')
        }
        @{
            Id            = 'performance-metrics'
            LegacyId      = '7'
            Name          = 'Performance Metrics'
            Category      = 'Diagnostics'
            Function      = 'Get-PerformanceMetrics'
            Description   = 'Memory usage percentage and running process count; warns if memory exceeds 80%'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('performance','memory','counters')
        }
        @{
            Id            = 'installed-software'
            LegacyId      = '8'
            Name          = 'Installed Software List'
            Category      = 'Diagnostics'
            Function      = 'Get-InstalledSoftware'
            Description   = 'Installed applications from registry uninstall keys'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('software','installed','apps','programs')
        }
        @{
            Id            = 'windows-updates'
            LegacyId      = '9'
            Name          = 'Windows Updates Status'
            Category      = 'Diagnostics'
            Function      = 'Get-WindowsUpdates'
            Description   = 'Most recent installed hotfix from Get-HotFix'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('updates','hotfix','patch','kb')
        }
        @{
            Id            = 'user-accounts'
            LegacyId      = '10'
            Name          = 'User Account Information'
            Category      = 'Diagnostics'
            Function      = 'Get-UserAccounts'
            Description   = 'Local user accounts: name, enabled state, and last logon time'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('users','accounts')
        }
        @{
            Id            = 'network-connectivity'
            LegacyId      = '12'
            Name          = 'Network Connectivity Tests'
            Category      = 'Diagnostics'
            Function      = 'Test-NetworkConnectivity'
            Description   = 'Ping/DNS reachability tests to Google DNS, Cloudflare DNS, and microsoft.com'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('network','ping','connectivity','dns')
        }
        @{
            Id            = 'system-health'
            LegacyId      = '13'
            Name          = 'System Health Check'
            Category      = 'Diagnostics'
            Function      = 'Get-SystemHealthCheck'
            Description   = 'Disk and memory health; warns if any volume is below 10% free or RAM exceeds 90%'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('health','check','overview')
        }
        @{
            Id            = 'security-analysis'
            LegacyId      = '14'
            Name          = 'Security Analysis'
            Category      = 'Diagnostics'
            Function      = 'Get-SecurityAnalysis'
            Description   = 'Defender and firewall posture; reports Unable to check when access is restricted'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('security','defender','firewall')
        }
        @{
            Id            = 'driver-info'
            LegacyId      = '15'
            Name          = 'Driver Information'
            Category      = 'Diagnostics'
            Function      = 'Get-DriverInformation'
            Description   = 'Signed driver inventory sorted by install date; shows first 15 of total'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('drivers','devices','pnp')
        }
        @{
            Id            = 'startup-programs'
            LegacyId      = '16'
            Name          = 'Startup Programs'
            Category      = 'Diagnostics'
            Function      = 'Get-StartupPrograms'
            Description   = 'Auto-start entries from HKLM and HKCU Run registry keys'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('startup','autorun','boot')
        }
    )
}
