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
            Description   = 'Reports sleep states and wake blockers; optionally applies standard lid/sleep/hibernate timers (confirmed)'
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
    )
}
