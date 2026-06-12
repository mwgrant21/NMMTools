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
            RequiresAdmin = $false
            SilentCapable = $true
            Risk          = 'Modifies'
            Tags          = @('temp','cleanup','disk','space')
        }
    )
}
