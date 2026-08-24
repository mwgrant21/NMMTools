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

        # Outlook profiles live entirely in the mailbox owner's hive.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # Gate before the report, not just before the action: every line of the
        # diagnostic below reads the user hive, so an unresolved context would
        # list the technician's own Outlook profiles as if they were the user's.
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot read or repair Outlook profiles - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $profilesKey = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Office\16.0\Outlook\Profiles'
        $outlookKey  = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Office\16.0\Outlook'

        # reg.exe takes registry-native roots, not PowerShell provider paths, so
        # the backup target is built separately from the provider paths above.
        $regBackupRoot = 'HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles'
        if ($ctx.IsRedirected -and $ctx.Sid) {
            $regBackupRoot = 'HKU\{0}\Software\Microsoft\Office\16.0\Outlook\Profiles' -f $ctx.Sid
        }

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

        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot recreate the Outlook profile - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        # Nuclear: require typed confirmation. Read-ToolChoice -ExactMatch, not a bare
        # Read-Host: Read-Host throws in the GUI's hostless tool runspace, so the whole
        # tool fails closed and can never be used from the default UI mode. -ExactMatch
        # also makes the compare case-sensitive so 'rebuild' can't satisfy an all-caps gate.
        $typed = Read-ToolChoice -Prompt 'Type REBUILD to delete and recreate the Outlook profile' `
            -Choices @('REBUILD', 'Cancel') -Default 'Cancel' -Silent:$Silent -ExactMatch
        if ($typed -ne 'REBUILD') {
            Complete-ToolRun $run -Status Skipped -Summary 'RecreateProfile cancelled (confirmation not typed)'
            return
        }

        [void](Stop-OutlookGraceful)

        $backup = Join-Path $env:TEMP ('OutlookProfiles_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        reg export $regBackupRoot $backup /y 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) {
            Complete-ToolRun $run -Status Failed -Summary 'Registry backup failed; profile NOT deleted (aborted to avoid unrecoverable data loss)'
            return
        }

        Remove-Item -LiteralPath $profilesKey -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $profilesKey -Force -ErrorAction SilentlyContinue | Out-Null
        New-Item -Path (Join-Path $profilesKey 'Outlook') -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -LiteralPath $outlookKey -Name 'DefaultProfile' -Value 'Outlook' -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath (Join-Path $profilesKey 'Outlook')) {
            Complete-ToolRun $run -Status Success -Summary ('Outlook profile recreated; backup at {0}; relaunch Outlook to run setup' -f $backup)
        } else {
            Write-ToolOutput ('Profile recreation FAILED. Restore from backup: {0}' -f $backup) -Level Error
            Complete-ToolRun $run -Status Failed -Summary ('Profile recreation failed; restore from backup: {0}' -f $backup)
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            $msg = ('{0}; Outlook profile registry backup available at {1}' -f $msg, $backup)
        }
        Complete-ToolRun $run -Status Failed -Summary $msg
    }
}
