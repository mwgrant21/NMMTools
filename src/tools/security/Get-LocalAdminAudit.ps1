function Get-LocalAdminAudit {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'local-admin-audit'
        # SID/RID-based, not name-based: a name allowlist is evadable (a rogue LOCAL account
        # can legally be named 'Domain Admins') and false-positives on any legitimate account
        # that doesn't match these exact strings (a renamed built-in Administrator - standard
        # CIS hardening practice - or a delegated AD group with a custom name via GPO
        # Restricted Groups, both plausible in a hybrid AD/Entra environment). RID 500 is the
        # built-in Administrator account; RID 512/519 are the well-known Domain Admins /
        # Enterprise Admins group RIDs, which hold regardless of what the group is renamed to.
        $expectedGroupRidSuffixes = @('-512', '-519')
        $currentUserSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

        # --- Report ---
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop)
        Write-ToolOutput ('Local Administrators members: {0}' -f $admins.Count) -Level Info
        $unexpected = New-Object System.Collections.Generic.List[object]
        foreach ($a in $admins) {
            $short = $a.Name -replace '.*\\', ''
            $sidValue = if ($a.SID) { $a.SID.Value } else { $null }
            $isBuiltinAdmin = ($a.PrincipalSource -eq 'Local') -and $sidValue -and ($sidValue -match '-500$')
            $isExpectedGroup = $sidValue -and [bool]($expectedGroupRidSuffixes | Where-Object { $sidValue.EndsWith($_) })
            $isExpected = $isBuiltinAdmin -or $isExpectedGroup
            $disabled = $false
            $pwdNeverExp = $false
            $lastLogon = 'N/A'
            if ($a.PrincipalSource -eq 'Local') {
                $lu = Get-LocalUser -Name $short -ErrorAction SilentlyContinue
                if ($lu) {
                    $disabled = -not $lu.Enabled
                    $pwdNeverExp = $lu.PasswordNeverExpires
                    if ($lu.LastLogon) { $lastLogon = $lu.LastLogon.ToString('yyyy-MM-dd HH:mm') } else { $lastLogon = 'Never' }
                }
            }
            $flags = @()
            if ($disabled) { $flags += 'DISABLED' }
            if ($pwdNeverExp) { $flags += 'PWD-NEVER-EXPIRES' }
            $isUnexpected = (-not $isExpected) -and (-not $disabled)
            if ($isUnexpected) { $flags += 'UNEXPECTED'; $unexpected.Add($a) }
            $flagStr = ''
            if ($flags.Count -gt 0) { $flagStr = ('  [{0}]' -f ($flags -join ', ')) }
            $lvl = 'Detail'
            if ($isUnexpected) { $lvl = 'Warning' }
            Write-ToolOutput ('  {0}  ({1})  last logon: {2}{3}' -f $a.Name, $a.PrincipalSource, $lastLogon, $flagStr) -Level $lvl
        }

        # RID 500, not the literal name 'Administrator' - a renamed built-in account (standard
        # CIS/security-hardening practice) would otherwise be missed here entirely.
        $builtin = @(Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value.EndsWith('-500') }) | Select-Object -First 1
        if ($builtin) {
            if ($builtin.Enabled) { Write-ToolOutput 'Built-in Administrator: ENABLED (consider disabling if not required)' -Level Warning }
            else { Write-ToolOutput 'Built-in Administrator: disabled (good)' -Level Detail }
        }

        # --- Action menu ---
        if ($unexpected.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary ('{0} admin(s); all expected' -f $admins.Count)
            return
        }

        Write-ToolOutput ('{0} unexpected active admin account(s) found.' -f $unexpected.Count) -Level Warning
        $action = Read-ToolChoice -Prompt 'Disable unexpected LOCAL admin accounts?' -Choices @('None','DisableUnexpected') -Default 'None' -Silent:$Silent

        if ($action -ne 'DisableUnexpected') {
            Complete-ToolRun $run -Status Warning -Summary ('{0} unexpected active admin(s); no action taken' -f $unexpected.Count)
            return
        }

        $disabledCount = 0
        foreach ($a in $unexpected) {
            $short = $a.Name -replace '.*\\', ''
            $sidValue = if ($a.SID) { $a.SID.Value } else { $null }
            if ($sidValue -and $sidValue -eq $currentUserSid) {
                # Never disable the account this tool is currently running as - a technician
                # running under a local admin account not on the allowlist could otherwise
                # lock themselves out mid-run.
                Write-ToolOutput ('  Skipped {0}: this is the account currently running the audit' -f $short) -Level Warning
                continue
            }
            if ($a.PrincipalSource -eq 'Local') {
                $lu = Get-LocalUser -Name $short -ErrorAction SilentlyContinue
                if ($lu -and $lu.Enabled) {
                    try {
                        Disable-LocalUser -Name $short -ErrorAction Stop
                        $disabledCount++
                        Write-ToolOutput ('  Disabled: {0}' -f $short) -Level Detail
                    } catch {
                        Write-ToolOutput ('  Could not disable {0}: {1}' -f $short, $_.Exception.Message) -Level Warning
                    }
                }
            } else {
                Write-ToolOutput ('  {0} is a domain account - cannot disable locally.' -f $a.Name) -Level Detail
            }
        }
        Complete-ToolRun $run -Status Success -Summary ('Disabled {0} of {1} unexpected admin account(s)' -f $disabledCount, $unexpected.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
