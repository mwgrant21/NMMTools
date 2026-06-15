function Remove-OrphanedProfile {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'orphaned-profiles'

        $plReg = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $ts    = Get-Date -Format 'yyyyMMdd_HHmmss'

        # Account running the tool - never a removal candidate.
        $currentSid = ''
        try { $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $currentSid = '' }

        # --- Audit (read-only) ---
        $profiles = @()
        try {
            $profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop)
        } catch {
            Complete-ToolRun $run -Status Failed -Summary ('Could not enumerate user profiles: {0}' -f $_.Exception.Message)
            return
        }

        $orphans = @()
        foreach ($p in $profiles) {
            $sid       = [string]$p.SID
            $localPath = [string]$p.LocalPath
            $special   = [bool]$p.Special
            $loaded    = [bool]$p.Loaded
            $isCurrent = ($sid -eq $currentSid)

            $sidResolves = $false
            try {
                $null = ([System.Security.Principal.SecurityIdentifier]$sid).Translate([System.Security.Principal.NTAccount])
                $sidResolves = $true
            } catch {
                $sidResolves = $false
            }

            $folderExists = [bool]($localPath -and (Test-Path -LiteralPath $localPath))

            $verdict = Get-NmmProfileVerdict -Special $special -Loaded $loaded -IsCurrentUser $isCurrent -SidResolves $sidResolves -FolderExists $folderExists

            switch ($verdict) {
                'Orphan-UnknownSid' {
                    Write-ToolOutput ('  [orphan: unknown-SID]    {0}  SID={1}' -f $localPath, $sid) -Level Warning
                    $orphans += [PSCustomObject]@{ Sid = $sid; LocalPath = $localPath; Reason = 'unknown-SID'; FolderExists = $folderExists }
                }
                'Orphan-MissingFolder' {
                    Write-ToolOutput ('  [orphan: missing-folder] {0}  SID={1}' -f $localPath, $sid) -Level Warning
                    $orphans += [PSCustomObject]@{ Sid = $sid; LocalPath = $localPath; Reason = 'missing-folder'; FolderExists = $folderExists }
                }
                'Protected' {
                    Write-ToolOutput ('  [protected] {0}' -f $localPath) -Level Detail
                }
                default {
                    Write-ToolOutput ('  [healthy]   {0}' -f $localPath) -Level Detail
                }
            }
        }

        if ($orphans.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary 'No orphaned profiles found'
            return
        }

        Write-ToolOutput ('{0} orphaned profile(s) found.' -f $orphans.Count) -Level Warning

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Orphaned profile action' -Choices @('None','RemoveOrphaned') -Default 'None' -Silent:$Silent
        if ($action -ne 'RemoveOrphaned') {
            Complete-ToolRun $run -Status Warning -Summary ('{0} orphaned profile(s) found; no removal applied' -f $orphans.Count)
            return
        }

        Write-ToolOutput 'WARNING: this removes profile registrations and quarantines (renames) their folders. Affected users must be logged off.' -Level Warning
        $gate = Read-ToolChoice -Prompt ('Type CONFIRM to remove these {0} orphaned profiles' -f $orphans.Count) -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
        if ($gate -ne 'CONFIRM') {
            Complete-ToolRun $run -Status Skipped -Summary 'RemoveOrphaned cancelled (no CONFIRM)'
            return
        }

        # 1. Backup ProfileList FIRST; abort if export fails (no changes made).
        $backup = Join-Path $env:TEMP ('ProfileList_backup_{0}.reg' -f $ts)
        & reg.exe export $plReg $backup /y *>$null
        if (-not (Test-Path -LiteralPath $backup)) {
            Complete-ToolRun $run -Status Failed -Summary 'Aborted: could not export ProfileList backup (no changes made)'
            return
        }
        Write-ToolOutput ('ProfileList backed up: {0}' -f $backup) -Level Info

        # 2. Per orphan: quarantine folder, then remove registration. Failure-isolated.
        $removed = 0
        $failed  = 0
        foreach ($o in $orphans) {
            $sid       = $o.Sid
            $localPath = $o.LocalPath

            if ($o.FolderExists) {
                try {
                    $leaf    = Split-Path -Path $localPath -Leaf
                    $newName = '{0}.orphan_{1}' -f $leaf, $ts
                    Rename-Item -LiteralPath $localPath -NewName $newName -ErrorAction Stop
                    Write-ToolOutput ('  Quarantined folder: {0} -> {1}' -f $localPath, $newName) -Level Info
                } catch {
                    Write-ToolOutput ('  SKIP {0}: could not quarantine folder ({1}); registration left intact; backup: {2}' -f $localPath, $_.Exception.Message, $backup) -Level Error
                    $failed++
                    continue
                }
            }

            $regGone = $false
            try {
                $inst = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { $_.SID -eq $sid }
                if ($inst) {
                    $inst | Remove-CimInstance -ErrorAction Stop
                }
                $regGone = $true
            } catch {
                # Fallback: delete the ProfileList key directly.
                & reg.exe delete ('{0}\{1}' -f $plReg, $sid) /f *>$null
                if ($LASTEXITCODE -eq 0) {
                    $regGone = $true
                } else {
                    Write-ToolOutput ('  FAILED to remove registration for SID {0} ({1}); folder already quarantined; backup: {2}' -f $sid, $_.Exception.Message, $backup) -Level Error
                    $failed++
                }
            }

            if ($regGone) {
                Write-ToolOutput ('  Removed orphaned profile: {0}  SID={1}' -f $localPath, $sid) -Level Success
                $removed++
            }
        }

        if ($removed -gt 0 -and $failed -eq 0) {
            Complete-ToolRun $run -Status Success -Summary ('Removed {0} orphaned profile(s); folders quarantined; backup: {1}' -f $removed, $backup)
        } elseif ($removed -gt 0) {
            Complete-ToolRun $run -Status Warning -Summary ('Removed {0}, failed {1}; ProfileList backup: {2}' -f $removed, $failed, $backup)
        } else {
            Complete-ToolRun $run -Status Failed -Summary ('No profiles removed ({0} failed); ProfileList backup retained: {1}' -f $failed, $backup)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
