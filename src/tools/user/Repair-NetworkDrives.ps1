function Repair-NetworkDrives {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'network-drives'

        # --- Report ---
        $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayRoot -like '\\*' })
        if ($drives.Count -gt 0) {
            Write-ToolOutput ('Mapped network drives: {0}' -f $drives.Count) -Level Info
            foreach ($d in $drives) {
                $state = 'DISCONNECTED'
                if (Test-Path -LiteralPath $d.Root) { $state = 'CONNECTED' }
                Write-ToolOutput ('  {0}: {1}  [{2}]' -f $d.Name, $d.DisplayRoot, $state) -Level Detail
            }
        } else {
            Write-ToolOutput 'No mapped network drives found.' -Level Warning
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Network drive action' `
            -Choices @('None','ReconnectAll','RemapDrive') -Default 'None' -Silent:$Silent

        switch ($action) {

            'ReconnectAll' {
                $configured = @()
                $netUse = & net.exe use
                foreach ($line in $netUse) {
                    $text = [string]$line
                    if ($text -match '^\s*(OK|Disconnected|Unavailable)\s+(\w):\s+(\\\\[^\s]+)') {
                        $configured += [PSCustomObject]@{ Letter = $matches[2]; Path = $matches[3] }
                    }
                }
                $regDrives = @(Get-ItemProperty 'HKCU:\Network\*' -ErrorAction SilentlyContinue)
                foreach ($rd in $regDrives) {
                    if ($rd.RemotePath -and $rd.PSChildName -and -not (@($configured | Where-Object { $_.Letter -eq $rd.PSChildName }).Count)) {
                        $configured += [PSCustomObject]@{ Letter = $rd.PSChildName; Path = $rd.RemotePath }
                    }
                }
                if ($configured.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No configured network drives to reconnect'
                } else {
                    $okCount = 0
                    foreach ($cd in $configured) {
                        $dl = '{0}:' -f $cd.Letter
                        if (Test-Path -LiteralPath $dl) {
                            & net.exe use $dl /delete /y *>$null
                            Start-Sleep -Milliseconds 500
                        }
                        & net.exe use $dl $cd.Path /persistent:yes *>$null
                        Start-Sleep -Milliseconds 500
                        if (Test-Path -LiteralPath $dl) {
                            Write-ToolOutput ('  [OK] {0} -> {1}' -f $dl, $cd.Path) -Level Success
                            $okCount++
                        } else {
                            Write-ToolOutput ('  [FAIL] {0} -> {1}' -f $dl, $cd.Path) -Level Warning
                        }
                    }
                    $reconStatus = 'Success'
                    if ($okCount -eq 0) { $reconStatus = 'Warning' }
                    Complete-ToolRun $run -Status $reconStatus -Summary ('Reconnected {0} of {1} configured drive(s)' -f $okCount, $configured.Count)
                }
            }

            'RemapDrive' {
                # Read-Host is safe here: only reached in the interactive RemapDrive branch (never under -Silent).
                $letter = (Read-Host 'Drive letter to (re)map (e.g. Z)').Trim().TrimEnd(':')
                $unc = (Read-Host 'UNC path (e.g. \\server\share)').Trim()
                if ([string]::IsNullOrWhiteSpace($letter) -or ($unc -notlike '\\*')) {
                    Complete-ToolRun $run -Status Warning -Summary 'RemapDrive aborted: invalid drive letter or UNC path'
                } else {
                    $dl = '{0}:' -f $letter
                    & net.exe use $dl /delete /y *>$null
                    Start-Sleep -Milliseconds 500
                    & net.exe use $dl $unc /persistent:yes *>$null
                    Start-Sleep -Milliseconds 500
                    if (Test-Path -LiteralPath $dl) {
                        Complete-ToolRun $run -Status Success -Summary ('Mapped {0} -> {1}' -f $dl, $unc)
                    } else {
                        Complete-ToolRun $run -Status Warning -Summary ('Mapped {0} -> {1} but not accessible (clear stale share creds via credential-manager)' -f $dl, $unc)
                    }
                }
            }

            default {
                if ($drives.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No mapped network drives; no action taken'
                } else {
                    Complete-ToolRun $run -Status Success -Summary ('{0} mapped drive(s) reported; no action taken' -f $drives.Count)
                }
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
