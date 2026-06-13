function Clear-NetworkProfiles {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'network-profile-cleanup'

        # --- List saved Wi-Fi profiles ---
        $profileLines = @(netsh wlan show profiles 2>&1 | ForEach-Object { $_.ToString() })
        $savedProfiles = @()
        foreach ($ln in $profileLines) {
            if ($ln -match 'All User Profile\s*:\s*(.+)') {
                $savedProfiles += $Matches[1].Trim()
            }
        }

        Write-ToolOutput ('{0} saved Wi-Fi profile(s)' -f $savedProfiles.Count)
        foreach ($p in $savedProfiles) {
            Write-ToolOutput ('  - {0}' -f $p) -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice `
            -Prompt 'Network profile action' `
            -Choices @('None', 'DeleteAll', 'DeleteSpecific', 'ShowPassword', 'StackReset') `
            -Default 'None' `
            -Silent:$Silent

        switch ($action) {
            'DeleteAll' {
                $gate = Read-ToolChoice `
                    -Prompt 'Delete ALL saved Wi-Fi profiles? Removes all Wi-Fi credentials. Type CONFIRM to proceed' `
                    -Choices @('CONFIRM', 'Cancel') `
                    -Default 'Cancel' `
                    -Silent:$Silent
                if ($gate -eq 'CONFIRM') {
                    Write-ToolOutput 'Deleting all Wi-Fi profiles...' -Level Info
                    netsh wlan delete profile name=* i=* 2>&1 | Out-Null
                    Write-ToolOutput 'All profiles deleted. You will need to reconnect and enter passwords.' -Level Success
                    Complete-ToolRun $run -Status Success -Summary ('All {0} Wi-Fi profile(s) deleted' -f $savedProfiles.Count)
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'DeleteAll cancelled by user'
                }
            }
            'DeleteSpecific' {
                if ($savedProfiles.Count -eq 0) {
                    Write-ToolOutput 'No saved profiles to delete' -Level Warning
                    Complete-ToolRun $run -Status Skipped -Summary 'DeleteSpecific: no saved profiles'
                } else {
                    $profileChoices = $savedProfiles + @('Cancel')
                    $networkName = Read-ToolChoice `
                        -Prompt 'Select network profile to delete' `
                        -Choices $profileChoices `
                        -Default 'Cancel' `
                        -Silent:$Silent
                    if ($networkName -ne 'Cancel') {
                        $gate2 = Read-ToolChoice `
                            -Prompt ('Confirm delete profile: {0}' -f $networkName) `
                            -Choices @('Yes', 'No') `
                            -Default 'No' `
                            -Silent:$Silent
                        if ($gate2 -eq 'Yes') {
                            Write-ToolOutput ('Deleting profile: {0}' -f $networkName) -Level Info
                            netsh wlan delete profile name="$networkName" 2>&1 | Out-Null
                            Write-ToolOutput ('Profile deleted: {0}' -f $networkName) -Level Success
                            Complete-ToolRun $run -Status Success -Summary ('Wi-Fi profile deleted: {0}' -f $networkName)
                        } else {
                            Complete-ToolRun $run -Status Skipped -Summary 'DeleteSpecific: user declined confirmation'
                        }
                    } else {
                        Complete-ToolRun $run -Status Skipped -Summary 'DeleteSpecific cancelled'
                    }
                }
            }
            'ShowPassword' {
                if ($savedProfiles.Count -eq 0) {
                    Write-ToolOutput 'No saved profiles to inspect' -Level Warning
                    Complete-ToolRun $run -Status Skipped -Summary 'ShowPassword: no saved profiles'
                } else {
                    $profileChoices = $savedProfiles + @('Cancel')
                    $networkName = Read-ToolChoice `
                        -Prompt 'Select network profile to show saved password for' `
                        -Choices $profileChoices `
                        -Default 'Cancel' `
                        -Silent:$Silent
                    if ($networkName -ne 'Cancel') {
                        Write-ToolOutput ('[WARNING] The network key (password) will be shown in plain text on screen.') -Level Warning
                        Write-ToolOutput ('Showing saved credential for: {0}' -f $networkName)
                        $showOut = netsh wlan show profile name="$networkName" key=clear 2>&1
                        foreach ($ln in $showOut) { Write-ToolOutput $ln.ToString() -Level Detail }
                        Complete-ToolRun $run -Status Success `
                            -Summary ('Showed saved credential for: {0} (password visible in output)' -f $networkName)
                    } else {
                        Complete-ToolRun $run -Status Skipped -Summary 'ShowPassword cancelled'
                    }
                }
            }
            'StackReset' {
                $gate = Read-ToolChoice `
                    -Prompt 'Reset network stack (winsock + TCP/IP + DNS flush)? Reboot required to finish.' `
                    -Choices @('Yes', 'No') `
                    -Default 'No' `
                    -Silent:$Silent
                if ($gate -eq 'Yes') {
                    Write-ToolOutput 'Resetting network stack...' -Level Info
                    netsh winsock reset 2>&1 | Out-Null
                    Write-ToolOutput '  Winsock reset' -Level Detail
                    netsh int ip reset 2>&1 | Out-Null
                    Write-ToolOutput '  TCP/IP stack reset' -Level Detail
                    ipconfig /flushdns 2>&1 | Out-Null
                    Write-ToolOutput '  DNS cache flushed' -Level Detail
                    Write-ToolOutput 'Stack reset complete. REBOOT required for full effect.' -Level Success
                    Complete-ToolRun $run -Status Success `
                        -Summary 'Network stack reset (winsock + TCP/IP + DNS); reboot required'
                } else {
                    Complete-ToolRun $run -Status Skipped -Summary 'StackReset cancelled by user'
                }
            }
            default {
                Complete-ToolRun $run -Status Success `
                    -Summary ('{0} saved Wi-Fi profile(s); no action taken' -f $savedProfiles.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
