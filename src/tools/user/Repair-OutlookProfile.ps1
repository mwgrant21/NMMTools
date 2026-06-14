function Repair-OutlookProfile {
    [CmdletBinding()]
    param([switch]$Silent)

    function Stop-OutlookGraceful {
        $proc = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue)
        if ($proc.Count -eq 0) { return $true }
        foreach ($p in $proc) { $p.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        if (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0) {
            Stop-Process -Name 'OUTLOOK' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        return (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -eq 0)
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-profile-repair'
        $profilesKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
        $outlookKey  = 'HKCU:\Software\Microsoft\Office\16.0\Outlook'

        # --- Report ---
        $profiles = @(Get-ChildItem -LiteralPath $profilesKey -ErrorAction SilentlyContinue)
        Write-ToolOutput ('Outlook profiles: {0}' -f $profiles.Count) -Level Info
        foreach ($p in $profiles) { Write-ToolOutput ('  {0}' -f $p.PSChildName) -Level Detail }
        $def = (Get-ItemProperty -LiteralPath $outlookKey -Name 'DefaultProfile' -ErrorAction SilentlyContinue).DefaultProfile
        if ($def) { Write-ToolOutput ('Default profile: {0}' -f $def) -Level Detail }
        Write-ToolOutput 'WARNING: RecreateProfile deletes ALL Outlook profile settings. Mail data on the server is unaffected.' -Level Warning

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook profile repair' -Choices @('None','RecreateProfile') -Default 'None' -Silent:$Silent

        if ($action -ne 'RecreateProfile') {
            Complete-ToolRun $run -Status Success -Summary ('{0} profile(s) reported; no action taken' -f $profiles.Count)
            return
        }

        # Nuclear: require typed confirmation (free-text after an interactive choice; never reached under -Silent)
        $typed = Read-Host 'Type REBUILD to delete and recreate the Outlook profile'
        if ($typed -ne 'REBUILD') {
            Complete-ToolRun $run -Status Skipped -Summary 'RecreateProfile cancelled (confirmation not typed)'
            return
        }

        [void](Stop-OutlookGraceful)

        $backup = Join-Path $env:TEMP ('OutlookProfiles_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        reg export 'HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles' $backup /y 2>$null | Out-Null

        Remove-Item -LiteralPath $profilesKey -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $profilesKey -Force | Out-Null
        New-Item -Path (Join-Path $profilesKey 'Outlook') -Force | Out-Null
        Set-ItemProperty -LiteralPath $outlookKey -Name 'DefaultProfile' -Value 'Outlook' -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath (Join-Path $profilesKey 'Outlook')) {
            Complete-ToolRun $run -Status Success -Summary ('Outlook profile recreated; backup at {0}; relaunch Outlook to run setup' -f $backup)
        } else {
            Write-ToolOutput ('Profile recreation FAILED. Restore from backup: {0}' -f $backup) -Level Error
            Complete-ToolRun $run -Status Failed -Summary ('Profile recreation failed; restore from backup: {0}' -f $backup)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
