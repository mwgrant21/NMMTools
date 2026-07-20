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
            Description   = 'Office Click-to-Run update, silent forced update, full online repair, or clear cached Office credentials'
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
        @{
            Id            = 'driver-integrity-scan'
            LegacyId      = '72'
            Name          = 'Driver Integrity Scan'
            Category      = 'Repair'
            Function      = 'Get-DriverIntegrityScan'
            Description   = 'Inventories installed drivers; flags duplicates, unknown publishers, and stale (3yr+) drivers'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('driver','integrity','scan','inventory')
        }
        @{
            Id            = 'bsod-crash-parser'
            LegacyId      = '75'
            Name          = 'BSOD Crash Dump Parser'
            Category      = 'Repair'
            Function      = 'Get-BSODCrashDumpParser'
            Description   = 'Parses minidumps for bug-check codes and likely causes; optional report export'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('bsod','crashdump','minidump','bugcheck')
        }
        @{
            Id            = 'windows-activation'
            LegacyId      = '90'
            Name          = 'Windows Activation Status and Repair'
            Category      = 'Repair'
            Function      = 'Repair-WindowsActivation'
            Description   = 'Reports license/activation status; attempts online activation (slmgr /ato) if unlicensed'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('activation','license','slmgr','kms')
        }
        @{
            Id            = 'dism-repair'
            LegacyId      = '31'
            Name          = 'DISM System Image Repair'
            Category      = 'Repair'
            Function      = 'Invoke-DISMRepair'
            Description   = 'DISM CheckHealth/ScanHealth then optional RestoreHealth (repairs the component store; may contact Windows Update)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('dism','image','restorehealth','corruption')
        }
        @{
            Id            = 'sfc-repair'
            LegacyId      = '32'
            Name          = 'System File Checker'
            Category      = 'Repair'
            Function      = 'Invoke-SFCRepair'
            Description   = 'sfc /scannow - scans and repairs protected system files from the local cache'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('sfc','scannow','systemfile','corruption')
        }
        @{
            Id            = 'chkdsk-repair'
            LegacyId      = '33'
            Name          = 'Check Disk'
            Category      = 'Repair'
            Function      = 'Invoke-ChkDskRepair'
            Description   = 'chkdsk scan, or /F /R which schedules a boot-time check on the system drive'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('chkdsk','disk','filesystem','badsector')
        }
        @{
            Id            = 'deep-disk-cleanup'
            LegacyId      = '34'
            Name          = 'Deep Disk Cleanup'
            Category      = 'Repair'
            Function      = 'Invoke-DeepDiskCleanup'
            Description   = 'Tiered cleanup: temp/WU cache/CBS/WER (Conservative); plus Windows.old (Full tier, typed confirm)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('cleanup','disk','space','windowsold')
        }
        @{
            Id            = 'windows-old-removal'
            LegacyId      = '102'
            Name          = 'Remove Windows.old'
            Category      = 'Repair'
            Function      = 'Remove-WindowsOld'
            Description   = 'Removes the C:\Windows.old folder (rmdir + DISM component cleanup); ends OS rollback - irreversible; typed confirm'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('windowsold','rollback','dism','cleanup')
        }
        @{
            Id            = 'adobe-cc-removal'
            LegacyId      = '89'
            Name          = 'Adobe Creative Cloud Force Removal'
            Category      = 'Repair'
            Function      = 'Remove-AdobeCC'
            Description   = 'Force-removes all Adobe apps, services, tasks, files, and registry (clears Adobe user data; typed confirm)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('adobe','creativecloud','removal','uninstall')
        }
        @{
            Id            = 'powershell7-install'
            LegacyId      = '87'
            Name          = 'Install / Upgrade PowerShell 7'
            Category      = 'Repair'
            Function      = 'Install-PowerShell7'
            Description   = 'Installs or updates PowerShell 7 via winget or GitHub MSI (also enables PS Remoting)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('powershell7','pwsh','install','winget')
        }
        @{
            Id            = 'win11-feature-unlock'
            LegacyId      = '88'
            Name          = 'Win11 Feature Update Unlock'
            Category      = 'Repair'
            Function      = 'Invoke-Win11FeatureUpdateUnlock'
            Description   = 'Break-glass: removes version-lock GPO keys and stages a Win11 feature upgrade (can reboot); typed confirm'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('win11','featureupdate','unlock','upgrade')
        }
        @{
            Id            = 'oem-driver-update'
            LegacyId      = '35'
            Name          = 'OEM Driver/Firmware Update'
            Category      = 'Repair'
            Function      = 'Invoke-OEMDriverUpdate'
            Description   = 'Launches the vendor updater (Dell Command Update / Lenovo System Update / HP Support Assistant) to scan for driver and firmware updates'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('driver','firmware','oem','vendor')
        }
        @{
            Id            = 'windows-update-repair'
            LegacyId      = '65'
            Name          = 'Local Windows Update Repair'
            Category      = 'Repair'
            Function      = 'Repair-WindowsUpdateLocal'
            Description   = 'Resets Windows Update: stops services, renames SoftwareDistribution and Catroot2, re-registers DLLs'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('windowsupdate','wuauserv','softwaredistribution','reset')
        }
        @{
            Id            = 'proxy-reset'
            LegacyId      = '100'
            Name          = 'Proxy / Internet Settings Repair'
            Category      = 'Repair'
            Function      = 'Repair-ProxySettings'
            Description   = 'Resets WinHTTP/WinINET proxy, clears PAC, flushes DNS, resets Winsock (reboot to finish)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('proxy','winhttp','winsock','internet')
        }
        @{
            Id            = 'display-adapter-reset'
            LegacyId      = '73'
            Name          = 'Reset Display Adapter'
            Category      = 'Repair'
            Function      = 'Reset-DisplayAdapter'
            Description   = 'Disables and re-enables the display adapter (brief black screen) to clear display glitches'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('display','gpu','adapter','pnp')
        }
        @{
            Id            = 'repair-suite'
            LegacyId      = '36'
            Name          = 'Complete Repair Suite'
            Category      = 'Repair'
            Function      = 'Invoke-SystemRepairSuite'
            Description   = 'One-click DISM RestoreHealth + SFC + temp cleanup, run in sequence'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('suite','dism','sfc','cleanup','repair')
        }
        @{
            Id            = 'battery-health'
            LegacyId      = '38'
            Name          = 'Battery Health Check'
            Category      = 'Laptop'
            Function      = 'Get-BatteryHealth'
            Description   = 'Battery design vs full-charge capacity, wear %, and a powercfg battery report'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('battery','health','wear','powercfg')
        }
        @{
            Id            = 'thermal-health'
            LegacyId      = '63'
            Name          = 'Thermal and Fan Health Check'
            Category      = 'Laptop'
            Function      = 'Get-ThermalHealth'
            Description   = 'CPU temperature, load, and throttling-risk snapshot from ACPI thermal zone'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('thermal','temperature','fan','cpu')
        }
        @{
            Id            = 'wifi-environment'
            LegacyId      = '70'
            Name          = 'Wi-Fi Environment Snapshot'
            Category      = 'Laptop'
            Function      = 'Get-WiFiEnvironment'
            Description   = 'Passive scan of nearby Wi-Fi networks (signal, channel, congestion)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('wifi','scan','channel','environment')
        }
        @{
            Id            = 'travel-readiness'
            LegacyId      = '71'
            Name          = 'Laptop Readiness for Travel'
            Category      = 'Laptop'
            Function      = 'Test-LaptopTravelReadiness'
            Description   = 'Quick read-only pre-flight: disk space, battery wear, BitLocker, Wi-Fi adapter, VPN service presence'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('travel','readiness','preflight','laptop')
        }
        @{
            Id            = 'wifi-diagnostics'
            LegacyId      = '39'
            Name          = 'Wi-Fi Diagnostics'
            Category      = 'Laptop'
            Function      = 'Get-WiFiDiagnostics'
            Description   = 'Wi-Fi adapter/SSID/signal report; optional adapter restart or forget-network actions'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('wifi','wireless','adapter','signal')
        }
        @{
            Id            = 'vpn-health'
            LegacyId      = '40'
            Name          = 'VPN Health and Connection'
            Category      = 'Laptop'
            Function      = 'Test-VPNHealth'
            Description   = 'Windows VPN profile status + reachability (timeout-bounded); optional reconnect/disconnect'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('vpn','rasdial','connection','reachability')
        }
        @{
            Id            = 'network-profile-cleanup'
            LegacyId      = '47'
            Name          = 'Network Profile Cleanup'
            Category      = 'Laptop'
            Function      = 'Clear-NetworkProfiles'
            Description   = 'Lists saved Wi-Fi profiles; delete (typed confirm), show saved password (warned), or stack reset'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('wifi','profile','cleanup','credential')
        }
        @{
            Id            = 'network-stack-reset'
            LegacyId      = '67'
            Name          = 'Advanced Network Stack Deep Reset'
            Category      = 'Laptop'
            Function      = 'Reset-NetworkStack'
            Description   = 'Flush DNS + winsock + TCP/IP reset + cycle all active adapters (typed RESET; reboot to finish)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('network','winsock','tcpip','reset')
        }
        @{
            Id            = 'webcam-audio-test'
            LegacyId      = '41'
            Name          = 'Webcam and Audio Device Test'
            Category      = 'Laptop'
            Function      = 'Test-WebcamAudio'
            Description   = 'Lists camera and sound devices; opens test apps; optional close-conflicting-apps (confirmed)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('webcam','camera','audio','microphone')
        }
        @{
            Id            = 'bluetooth-devices'
            LegacyId      = '45'
            Name          = 'Bluetooth Device Management'
            Category      = 'Laptop'
            Function      = 'Get-BluetoothDevices'
            Description   = 'Bluetooth adapter and paired device list; optional bthserv restart (drops BT briefly)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('bluetooth','bthserv','pairing','wireless')
        }
        @{
            Id            = 'docking-displays'
            LegacyId      = '44'
            Name          = 'Docking Station and Displays'
            Category      = 'Laptop'
            Function      = 'Get-DockingDisplays'
            Description   = 'Connected monitors; optional display topology switch (extend/clone/external/internal)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('docking','display','monitor','displayswitch')
        }
        @{
            Id            = 'power-management'
            LegacyId      = '43'
            Name          = 'Power Management and Plans'
            Category      = 'Laptop'
            Function      = 'Get-PowerManagement'
            Description   = 'Active power plan and battery; optional plan switch or USB-selective-suspend change'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('power','powercfg','plan','battery')
        }
        @{
            Id            = 'sleep-hibernate'
            LegacyId      = '64'
            Name          = 'Sleep / Hibernate / Lid-Close Repair'
            Category      = 'Laptop'
            Function      = 'Repair-SleepHibernate'
            Description   = 'Reports sleep states and wake blockers; optionally applies standard sleep timers or clears wake blockers (confirmed)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('sleep','hibernate','lid','powercfg')
        }
        @{
            Id            = 'touchpad-keyboard'
            LegacyId      = '62'
            Name          = 'Touchpad and Keyboard Troubleshooter'
            Category      = 'Laptop'
            Function      = 'Repair-TouchpadKeyboard'
            Description   = 'Re-enables errored HID touchpad/keyboard devices; optionally clears Filter/Sticky Keys'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('touchpad','keyboard','hid','input')
        }
        @{
            Id            = 'hotkey-fn'
            LegacyId      = '68'
            Name          = 'Input and Hotkey / Fn Key Check'
            Category      = 'Laptop'
            Function      = 'Repair-HotkeyFnKeys'
            Description   = 'Checks OEM hotkey services (Lenovo/Dell/HP/Synaptics/ELAN); optionally starts/enables stopped ones'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('hotkey','fnkey','oem','service')
        }
        @{
            Id            = 'bitlocker-status'
            LegacyId      = '42'
            Name          = 'BitLocker Status and Recovery'
            Category      = 'Laptop'
            Function      = 'Get-BitLockerStatus'
            Description   = 'BitLocker encryption/protection status; AAD/Intune or hardened file key backup; suspend/resume'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('bitlocker','encryption','recovery','key')
        }
        @{
            Id            = 'storage-health'
            LegacyId      = '46'
            Name          = 'Storage Health (SSD/NVMe)'
            Category      = 'Laptop'
            Function      = 'Get-StorageHealth'
            Description   = 'Physical disk health, wear, temperature; optional Optimize-Volume (TRIM) or online scan'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('storage','ssd','nvme','disk')
        }
        @{
            Id            = 'browser-backup-restore'
            LegacyId      = '48'
            Name          = 'Browser Backup and Restore'
            Category      = 'Browser'
            Function      = 'Invoke-BrowserBackupRestore'
            Description   = 'Back up or restore Chrome/Edge/Firefox/Brave bookmarks, passwords, and preferences; backup is ACL-locked'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('browser','backup','restore','bookmarks')
        }
        @{
            Id            = 'browser-clear'
            LegacyId      = '50'
            Name          = 'Comprehensive Browser Clear'
            Category      = 'Browser'
            Function      = 'Clear-BrowserData'
            Description   = 'Clear cache, cookies, history, sessions, and site permissions across all profiles; preserves passwords, autofill, and Firefox bookmarks'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('browser','cache','cookies','privacy')
        }
        @{
            Id            = 'windows-search-rebuild'
            LegacyId      = '54'
            Name          = 'Windows Search Rebuild'
            Category      = 'User'
            Function      = 'Reset-WindowsSearch'
            Description   = 'Restart the Windows Search service, rebuild the search index, or open Indexing Options'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('search','wsearch','index','cortana')
        }
        @{
            Id            = 'start-menu-taskbar'
            LegacyId      = '55'
            Name          = 'Start Menu and Taskbar Repair'
            Category      = 'User'
            Function      = 'Repair-StartMenuTaskbar'
            Description   = 'Restart Explorer, reset the Start Menu layout, or re-register the Start Menu app for the current user'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('startmenu','taskbar','explorer','shell')
        }
        @{
            Id            = 'windows-explorer-reset'
            LegacyId      = '57'
            Name          = 'Windows Explorer Reset'
            Category      = 'User'
            Function      = 'Reset-WindowsExplorer'
            Description   = 'Restart Explorer, clear thumbnail/Recent/jump-list caches, or rebuild the icon cache'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('explorer','shell','thumbnail','iconcache')
        }
        @{
            Id            = 'default-apps'
            LegacyId      = '59'
            Name          = 'Default Apps and File Types'
            Category      = 'User'
            Function      = 'Set-DefaultApps'
            Description   = 'Report current file-type associations and open Default Apps settings (Windows protects per-user defaults; per-type changes are made in Settings)'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('defaultapps','fileassociation','fta','settings')
        }
        @{
            Id            = 'teams-addin-repair'
            LegacyId      = '83'
            Name          = 'Teams Meeting Add-in Repair'
            Category      = 'User'
            Function      = 'Repair-TeamsAddin'
            Description   = 'Fix the missing New Teams Meeting button in Outlook: re-register the add-in COM DLL, set LoadBehavior, clear DisabledItems and add-in cache'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','outlook','addin','meeting')
        }
        @{
            Id            = 'teams-deep-diagnostic'
            LegacyId      = '85'
            Name          = 'Teams Deep Diagnostic and Repair'
            Category      = 'User'
            Function      = 'Repair-TeamsDeep'
            Description   = '11-check diagnostic for New Teams auth/WAM/network issues; optional deep repair (clears credentials/WAM/MSIX cache, re-registers Teams) - sign-out required'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','wam','msal','auth','diagnostic')
        }
        @{
            Id            = 'teams-camera-repair'
            LegacyId      = '84'
            Name          = 'Camera and Mic Repair'
            Category      = 'User'
            Function      = 'Repair-TeamsCamera'
            Description   = 'Fix camera/mic: set Windows privacy access to Allow (FixPermissions), reset the media stack (ResetMediaStack - close hogging apps, clear cache, cycle the device), or remove and reinstall the camera driver (ReinstallDriver - reboot required)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','camera','microphone','media','webcam','driver')
        }
        @{
            Id            = 'network-drives'
            LegacyId      = '58'
            Name          = 'Mapped Network Drive Repair'
            Category      = 'User'
            Function      = 'Repair-NetworkDrives'
            Description   = 'Report mapped network drives and reconnect disconnected ones, or remap a drive letter to a UNC path'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('network','drive','mapped','unc')
        }
        @{
            Id            = 'credential-manager'
            LegacyId      = '60'
            Name          = 'Credential Manager Cleanup'
            Category      = 'User'
            Function      = 'Clear-SavedCredentials'
            Description   = 'List saved Windows credentials and clear network, web, Office 365, or all of them (stops the Office sign-in loop); or open Credential Manager'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('credential','cmdkey','password','office365')
        }
        @{
            Id            = 'profile-cache'
            LegacyId      = '66'
            Name          = 'Profile Size and Cache Cleanup'
            Category      = 'User'
            Function      = 'Clear-ProfileCache'
            Description   = 'Report user-profile cache folder sizes (Teams/OneDrive/Office/Chrome/Edge/Temp/Downloads) and optionally clear the safe caches; never touches OneDrive or Downloads'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('profile','cache','cleanup','roaming')
        }
        @{
            Id            = 'temp-profile-repair'
            LegacyId      = '95'
            Name          = 'Temporary Profile Repair'
            Category      = 'User'
            Function      = 'Repair-TemporaryProfile'
            Description   = 'Detect the "signed in with a temporary profile" issue (orphaned .bak keys in HKLM ProfileList) and repair it via reg copy after a registry backup; affected user must be logged off'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('profile','temporary','profilelist','registry')
        }
        @{
            Id            = 'orphaned-profiles'
            LegacyId      = '105'
            Name          = 'Orphaned Profile Cleanup'
            Category      = 'User'
            Function      = 'Remove-OrphanedProfile'
            Description   = 'Audit local user profiles and flag orphaned ones (SID no longer resolves to an account, or the profile folder is missing); on typed confirm, remove the registration and quarantine the folder (rename, not delete) after a ProfileList registry backup. Affected users must be logged off.'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('profile','orphaned','unknown','sid','profilelist','cleanup')
        }
        @{
            Id            = 'printer-repair'
            LegacyId      = '52'
            Name          = 'Printer Troubleshooter'
            Category      = 'User'
            Function      = 'Repair-PrinterIssues'
            Description   = 'Report printers, spooler status, and stuck jobs; restart the spooler, clear jobs, clear the spool folder (deep reset), remove offline/ghost printers, or full reset'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('printer','spooler','print','queue')
        }
        @{
            Id            = 'perf-optimizer'
            LegacyId      = '53'
            Name          = 'Performance Optimizer'
            Category      = 'User'
            Function      = 'Optimize-Performance'
            Description   = 'Report CPU/RAM and top processes, then open startup apps, clear TEMP, set visual effects to performance, or set the page file to system-managed (see also tools 4/7/11/16)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('performance','startup','pagefile','optimize')
        }
        @{
            Id            = 'audio-repair'
            LegacyId      = '56'
            Name          = 'Audio Troubleshooter'
            Category      = 'User'
            Function      = 'Repair-AudioAdvanced'
            Description   = 'Report audio devices and services, then restart the audio services, cycle the audio devices, or launch the Windows audio troubleshooter'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('audio','sound','playback','services')
        }
        @{
            Id            = 'outlook-search-repair'
            LegacyId      = '76'
            Name          = 'Outlook Search Repair'
            Category      = 'User'
            Function      = 'Repair-OutlookSearch'
            Description   = 'Report Windows Search/WSearch, index size, the Outlook catalog, and the PreventIndexingOutlook policy; then fix the search config (WSearch startup, PreventIndexingOutlook), restart WSearch, or rebuild the index (deletes Windows.edb); see also tool 54'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','search','wsearch','index')
        }
        @{
            Id            = 'm365-auth-reset'
            LegacyId      = '79'
            Name          = 'M365 Auth Reset'
            Category      = 'User'
            Function      = 'Reset-M365Auth'
            Description   = 'Report Office/M365 saved credentials and MSAL/WAM token caches, then clear them (stops the sign-in loop); optionally also clear AutoDiscover cache + OutlookSecurityMode for shared-mailbox access; see also tools 60/85'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','m365','auth','token','wam','credential')
        }
        @{
            Id            = 'autodiscover-fix'
            LegacyId      = '80'
            Name          = 'AutoDiscover Fix'
            Category      = 'User'
            Function      = 'Repair-AutoDiscover'
            Description   = 'Test the Outlook AutoDiscover endpoint and report cache/registry state, then flush DNS, clear AutoDiscover cache files and the AutoDiscover registry key, and re-test; see also m365-auth-reset'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','autodiscover','dns','exchange')
        }
        @{
            Id            = 'outlook-ost-rebuild'
            LegacyId      = '81'
            Name          = 'Outlook OST Rebuild'
            Category      = 'User'
            Function      = 'Reset-OutlookOst'
            Description   = 'List Outlook OST cache files and sizes, then close Outlook and rename each OST (keeps a timestamped .bak) so Outlook re-syncs from Exchange on next launch'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','ost','cache','exchange','resync')
        }
        @{
            Id            = 'outlook-profile-repair'
            LegacyId      = '82'
            Name          = 'Outlook Profile Repair'
            Category      = 'User'
            Function      = 'Repair-OutlookProfile'
            Description   = 'List Outlook profiles, then (nuclear) back up the Profiles registry key, delete it, and recreate a fresh default profile - all account settings are wiped; requires a typed REBUILD confirmation; see also tool 22'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('outlook','profile','registry','nuclear')
        }
        @{
            Id            = 'outlook-addin-repair'
            LegacyId      = '96'
            Name          = 'Outlook Add-in Repair'
            Category      = 'User'
            Function      = 'Repair-OutlookAddins'
            Description   = 'Report Outlook add-ins, Resiliency disabled/crashing lists, and the OnBase pin state; then re-enable disabled add-ins (LoadBehavior 3), or permanently pin the OnBase/Hyland add-in via policy so Outlook stops disabling it for "slowing down Outlook"'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','addin','onbase','loadbehavior','resiliency')
        }
        @{
            Id            = 'domain-trust-repair'
            LegacyId      = '51'
            Name          = 'Domain Trust and Connection Repair'
            Category      = 'Security'
            Function      = 'Repair-DomainTrust'
            Description   = 'Report domain join, secure channel, DC list, DNS and time, then test/repair the secure channel, reset the machine password, resync time, purge Kerberos tickets, rejoin the domain (typed REJOIN), or show detailed domain info'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('domain','kerberos','securechannel','nltest','ad')
        }
        @{
            Id            = 'time-sync-repair'
            LegacyId      = '91'
            Name          = 'Time Sync Repair'
            Category      = 'Security'
            Function      = 'Repair-TimeSync'
            Description   = 'Report w32tm status and NTP peers, then resync the clock or full-repair the Windows Time service (re-register, configure source, resync); Kerberos fails past 5 min drift'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('time','w32tm','ntp','kerberos','sync')
        }
        @{
            Id            = 'local-admin-audit'
            LegacyId      = '92'
            Name          = 'Local Admin Account Audit'
            Category      = 'Security'
            Function      = 'Get-LocalAdminAudit'
            Description   = 'Audit the local Administrators group, flag unexpected active accounts and the built-in Administrator, then optionally disable the unexpected LOCAL accounts'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('admin','audit','localgroup','security','accounts')
        }
        @{
            Id            = 'defender-status'
            LegacyId      = '93'
            Name          = 'Windows Defender Security Status'
            Category      = 'Security'
            Function      = 'Get-DefenderStatus'
            Description   = 'Report Windows Defender real-time protection, definition age, last scan, threats and tamper protection, then optionally update signatures; warns if a third-party AV is active'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('defender','antivirus','security','threats','signatures')
        }
        @{
            Id            = 'rdp-config'
            LegacyId      = '101'
            Name          = 'Remote Desktop Configuration'
            Category      = 'Security'
            Function      = 'Set-RemoteDesktop'
            Description   = 'Report Remote Desktop state (fDenyTSConnections, NLA, firewall, TermService), then enable RDP (typed ENABLE - increases exposure) or disable it (re-deny + close firewall)'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('rdp','remotedesktop','firewall','nla','termservice')
        }
        @{
            Id            = 'office-quick-fix'
            LegacyId      = 'Q1'
            Name          = 'Quick Fix: Office Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-OfficeQuickFix'
            Description   = 'One-click Office fix: close Office apps, clear Office sign-in credentials, and launch a Click-to-Run update; see also office-repair'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','office','m365','credentials')
        }
        @{
            Id            = 'onedrive-quick-fix'
            LegacyId      = 'Q2'
            Name          = 'Quick Fix: OneDrive Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-OneDriveQuickFix'
            Description   = 'One-click OneDrive fix: stop OneDrive, reset it (/reset), and restart it; see also onedrive-repair'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','onedrive','sync','reset')
        }
        @{
            Id            = 'teams-quick-fix'
            LegacyId      = 'Q3'
            Name          = 'Quick Fix: Teams Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-TeamsQuickFix'
            Description   = 'One-click Teams fix: close Teams (classic and new), clear the Teams cache, and restart Teams; see also teams-cache'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','teams','cache')
        }
        @{
            Id            = 'login-quick-fix'
            LegacyId      = 'Q4'
            Name          = 'Quick Fix: Login Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-LoginQuickFix'
            Description   = 'One-click login fix: clear Office/M365 sign-in credentials and report the device join state; see also credential-manager and m365-auth-reset'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','login','credentials','signin')
        }
        @{
            Id            = 'wifi-quick-fix'
            LegacyId      = 'Q5'
            Name          = 'Quick Fix: Wi-Fi Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-WiFiQuickFix'
            Description   = 'One-click Wi-Fi fix: restart the Wi-Fi adapter, release/renew the IP, and flush DNS; see also wifi-diagnostics and network-stack-reset'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','wifi','network','dns')
        }
        @{
            Id            = 'vpn-quick-fix'
            LegacyId      = 'Q6'
            Name          = 'Quick Fix: VPN Issues'
            Category      = 'QuickFix'
            Function      = 'Invoke-VpnQuickFix'
            Description   = 'One-click VPN fix: disconnect active VPNs, flush DNS, and clear the ARP cache (does not delete VPN profiles); see also vpn-health'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','vpn','network','dns')
        }
        @{
            Id            = 'av-prep-quick-fix'
            LegacyId      = 'Q7'
            Name          = 'Quick Fix: Audio/Video Prep'
            Category      = 'QuickFix'
            Function      = 'Invoke-AvPrepQuickFix'
            Description   = 'One-click meeting prep: close meeting apps and browsers to free the camera/mic, restart the audio service, and open the Camera app; see also webcam-audio-test and teams-camera-repair'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','audio','camera','meeting')
        }
        @{
            Id            = 'docking-quick-fix'
            LegacyId      = 'Q8'
            Name          = 'Quick Fix: Docking Station'
            Category      = 'QuickFix'
            Function      = 'Invoke-DockingQuickFix'
            Description   = 'One-click docking fix: detect displays and switch to extend mode (use Win+P to change mode); see also docking-displays'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('quickfix','docking','display','monitor')
        }
        @{
            Id            = 'browser-backup-quick-fix'
            LegacyId      = 'Q9'
            Name          = 'Quick Fix: Browser Backup'
            Category      = 'QuickFix'
            Function      = 'Invoke-BrowserBackupQuickFix'
            Description   = 'One-click browser backup: close browsers and back up bookmarks/logins for installed browsers to a timestamped ZIP; see also browser-backup-restore'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('quickfix','browser','backup','bookmarks')
        }
        @{
            Id            = 'teams-camera-deep'
            LegacyId      = '106'
            Name          = 'Teams Camera Deep Fix'
            Category      = 'User'
            Function      = 'Repair-TeamsCameraDeep'
            Description   = 'Detect dock type (Dell D6000 DisplayLink or WD19 Thunderbolt), identify camera failure mode (consent store wiped, DisplayLink virtual camera priority, or IR camera conflict), apply targeted fix, and harden against recurrence (USB suspend off, power mgmt pinned). Logs fix history to %PROGRAMDATA%\NMMTools\camera-fix-history.json.'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('teams','camera','displaylink','docking','ir','d6000','wd19','usb')
        }
        @{
            Id            = 'teams-meeting-quality'
            LegacyId      = '107'
            Name          = 'Teams Meeting Quality Diagnostic'
            Category      = 'Cloud'
            Function      = 'Get-TeamsMeetingQuality'
            Description   = 'Read-only meeting quality check: detect active NIC (flags D6000 DisplayLink USB NIC), measure latency/jitter/packet-loss to M365 endpoints, check VPN tunnel status, QoS/DSCP marking, hardware video encoder, CPU/RAM, and sample Teams logs for recent quality events. Produces a scored verdict.'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('teams','quality','network','latency','jitter','qos','vpn','displaylink','diagnostic')
        }
        @{
            Id            = 'outlook-search-all'
            LegacyId      = '108'
            Name          = 'Outlook Search: All Mailboxes Fix'
            Category      = 'User'
            Function      = 'Repair-OutlookSearchScope'
            Description   = 'Fix Outlook search showing results only from the current mailbox. Sets SearchDefaultScope=1 (All Mailboxes), checks each .ost/.pst data file in the active profile for Windows Search coverage, raises the per-file size limit for oversized archives, and triggers a targeted scope re-index. See also outlook-search-repair for full index rebuild.'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('outlook','search','mailbox','ost','pst','scope','index')
        }
        @{
            Id            = 'onbase-addin-fix'
            LegacyId      = '109'
            Name          = 'OnBase Add-in Permanent Enable'
            Category      = 'User'
            Function      = 'Repair-OnBaseAddinPermanent'
            Description   = 'Permanently prevent Outlook from auto-disabling the Hyland/OnBase add-in. Detects Resiliency DisabledItems/CrashedAddinList state, re-enables LoadBehavior=3, adds to DoNotDisableAddinList, raises the add-in startup timeout to 5s, optionally adds HKLM registration (survives profile resets), and creates a weekly self-heal scheduled task (NMMTools-OnBaseAddinCheck). See also outlook-addin-repair.'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('onbase','hyland','outlook','addin','resiliency','loadbehavior','permanentfix')
        }
        @{
            Id            = 'cert-expiry'
            LegacyId      = '110'
            Name          = 'Certificate Expiry Report'
            Category      = 'Security'
            Function      = 'Get-CertificateExpiry'
            Description   = 'Reports machine certificates (LocalMachine\My) expiring within 60 days or already expired, with subject, thumbprint, NotAfter, and days remaining'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('certificate','expiry','ssl','tls','security','localmachine')
        }
        @{
            Id            = 'wmi-repair'
            LegacyId      = '111'
            Name          = 'WMI Repository Repair'
            Category      = 'Repair'
            Function      = 'Repair-WmiRepository'
            Description   = 'Checks WMI repository health and repairs it if corrupted'
            RequiresAdmin = $true
            SilentCapable = $true
            Risk          = 'Disruptive'
            Tags          = @('wmi', 'repository', 'repair', 'cim')
        }
        @{
            Id            = 'reliability-history'
            LegacyId      = '112'
            Name          = 'Reliability Monitor History'
            Category      = 'Diagnostics'
            Function      = 'Get-ReliabilityHistory'
            Description   = 'Summarizes recurring failure sources from Reliability Monitor within a lookback window'
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'ReadOnly'
            Tags          = @('reliability', 'crash', 'history', 'stability')
        }
    )
}
