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
        @{
            Id            = 'scheduled-tasks'
            LegacyId      = '17'
            Name          = 'Scheduled Tasks Review'
            Category      = 'Diagnostics'
            Function      = 'Get-ScheduledTasksReview'
            Description   = 'Active (non-Disabled) scheduled tasks with name and current state'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('tasks','scheduler','scheduled')
        }
        @{
            Id            = 'file-system-check'
            LegacyId      = '18'
            Name          = 'File System Check'
            Category      = 'Diagnostics'
            Function      = 'Start-FileSystemCheck'
            Description   = 'Volume health report via Get-Volume (DriveLetter, FileSystem, HealthStatus); flags Unhealthy volumes'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('filesystem','disk','volume','health','chkdsk')
        }
        @{
            Id            = 'windows-features'
            LegacyId      = '19'
            Name          = 'Windows Features Status'
            Category      = 'Diagnostics'
            Function      = 'Get-WindowsFeatures'
            Description   = 'Enabled Windows optional features via Get-WindowsOptionalFeature -Online (requires admin)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('features','windows-features','optional','dism')
        }
        @{
            Id            = 'pending-reboot'
            LegacyId      = '94'
            Name          = 'Pending Reboot Status'
            Category      = 'Diagnostics'
            Function      = 'Get-PendingRebootStatus'
            Description   = 'Pending-reboot indicators from WU, CBS, PendingFileRename, computer rename, and SCCM'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('reboot','pending','restart')
        }
        @{
            Id            = 'winget-upgrade'
            LegacyId      = '104'
            Name          = 'winget App Update Sweep'
            Category      = 'Diagnostics'
            Function      = 'Invoke-WingetUpgradeAll'
            Description   = 'Upgrades all winget-managed apps (can close or replace running applications)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('winget','upgrade','apps','updates')
        }
        @{
            Id            = 'hardware-summary'
            LegacyId      = '69'
            Name          = 'Offline Hardware Summary'
            Category      = 'Diagnostics'
            Function      = 'Export-HardwareSummary'
            Description   = 'Exports a hardware summary file for ticket attachments'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('hardware','summary','export','ticket')
        }
        @{
            Id            = 'azure-ad-health'
            LegacyId      = '21'
            Name          = 'Azure AD Health Check'
            Category      = 'Cloud'
            Function      = 'Get-AzureADHealthCheck'
            Description   = 'Entra/Azure AD + domain join state from dsregcmd (AzureAdJoined, DomainJoined, DeviceId)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('azuread','entra','join','dsregcmd')
        }
        @{
            Id            = 'intune-health'
            LegacyId      = '29'
            Name          = 'Intune/MDM Health Check'
            Category      = 'Cloud'
            Function      = 'Get-IntuneHealthCheck'
            Description   = 'MDM enrollment status from HKLM Enrollments (UPN, provider); notes if access is restricted'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('intune','mdm','enrollment','management')
        }
        @{
            Id            = 'windows-hello'
            LegacyId      = '30'
            Name          = 'Windows Hello / MFA Status'
            Category      = 'Cloud'
            Function      = 'Get-WindowsHelloStatus'
            Description   = 'Windows Hello / Passport-for-Work policy and biometric device status (covers MFA-readiness check)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('hello','mfa','biometric','passport')
        }
        @{
            Id            = 'm365-connectivity'
            LegacyId      = '25'
            Name          = 'M365 Connectivity Test'
            Category      = 'Cloud'
            Function      = 'Test-M365Connectivity'
            Description   = 'TCP reachability (3s timeout per host) to login.microsoftonline.com, outlook, onedrive, teams'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('m365','connectivity','network','endpoints')
        }
        @{
            Id            = 'group-policy-update'
            LegacyId      = '28'
            Name          = 'Group Policy Update'
            Category      = 'Cloud'
            Function      = 'Update-GroupPolicy'
            Description   = 'Runs gpupdate /force (user policy always; machine policy needs admin + domain)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('gpupdate','grouppolicy','gpo','domain')
        }
        @{
            Id            = 'office-repair'
            LegacyId      = '22'
            Name          = 'Office 365 Health and Repair'
            Category      = 'Cloud'
            Function      = 'Repair-Office365'
            Description   = 'Triggers Office Click-to-Run update/repair and optionally clears cached Office credentials'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('office','m365','repair','clicktorun')
        }
        @{
            Id            = 'onedrive-repair'
            LegacyId      = '23'
            Name          = 'OneDrive Health and Reset'
            Category      = 'Cloud'
            Function      = 'Repair-OneDriveClient'
            Description   = 'Restarts OneDrive, or resets it (/reset wipes the local sync database - full re-sync)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('onedrive','sync','reset','restart')
        }
        @{
            Id            = 'teams-cache'
            LegacyId      = '24'
            Name          = 'Teams Cache Clear and Reset'
            Category      = 'Cloud'
            Function      = 'Clear-TeamsCache'
            Description   = 'Clears classic + New Teams cache after closing Teams (drops active calls)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('teams','cache','reset','newteams')
        }
    )
}
