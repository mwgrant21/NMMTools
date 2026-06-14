function Get-LocalAdminAudit {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'local-admin-audit'
        $expected = @('Administrator','Domain Admins','Enterprise Admins')

        # --- Report ---
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop)
        Write-ToolOutput ('Local Administrators members: {0}' -f $admins.Count) -Level Info
        $unexpected = New-Object System.Collections.Generic.List[object]
        foreach ($a in $admins) {
            $short = $a.Name -replace '.*\\', ''
            $isExpected = $false
            foreach ($e in $expected) { if ($short -like $e) { $isExpected = $true } }
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

        $builtin = Get-LocalUser -Name 'Administrator' -ErrorAction SilentlyContinue
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
