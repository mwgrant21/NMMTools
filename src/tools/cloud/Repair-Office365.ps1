function Repair-Office365 {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'office-repair'

        # Detect Office install from registry
        $officeApps = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*Microsoft 365*' -or $_.DisplayName -like '*Office*' }

        if ($officeApps) {
            foreach ($app in $officeApps) {
                Write-ToolOutput ('Installed: {0} {1}' -f $app.DisplayName, $app.DisplayVersion) -Level Detail
            }
        } else {
            Write-ToolOutput 'Office 365 / Microsoft 365 not detected in registry.' -Level Warning
        }

        # Locate Click-to-Run client (64-bit and 32-bit Program Files paths)
        $c2rCandidates = @(
            (Join-Path $env:ProgramFiles 'Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe')
        )
        $x86PF = ${env:ProgramFiles(x86)}
        if ($x86PF) {
            $c2rCandidates += Join-Path $x86PF 'Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'
        }
        $c2r = $c2rCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $c2r) {
            Write-ToolOutput 'Office Click-to-Run client not found.' -Level Warning
        }

        $choice = Read-ToolChoice -Prompt 'Office action' `
            -Choices @('UpdateRepair', 'SilentForcedUpdate', 'FullRepair', 'ClearCreds', 'Skip') `
            -Default 'Skip' `
            -Silent:$Silent

        switch ($choice) {
            'UpdateRepair' {
                if (-not $c2r) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary 'OfficeC2RClient.exe not found; cannot launch update/repair'
                    return
                }
                # Fire-and-forget: /update user triggers the C2R update/repair sequence
                Start-Process $c2r -ArgumentList '/update user'
                Complete-ToolRun $run -Status Success `
                    -Summary 'Office update/repair launched (OfficeC2RClient /update user)'
            }
            'SilentForcedUpdate' {
                if (-not $c2r) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary 'OfficeC2RClient.exe not found; cannot launch silent forced update'
                    return
                }
                # Fire-and-forget: force-closes Office apps, no UI
                Start-Process $c2r -ArgumentList '/update user displaylevel=false forceappshutdown=true'
                Complete-ToolRun $run -Status Success `
                    -Summary 'Office silent forced update launched (Office apps will close)'
            }
            'FullRepair' {
                if (-not $c2r) {
                    Complete-ToolRun $run -Status Warning `
                        -Summary 'OfficeC2RClient.exe not found; cannot launch full online repair'
                    return
                }
                # Fire-and-forget: full online repair (~1-2 GB download), closes Office apps
                Start-Process $c2r -ArgumentList '/scenario RepairAll /displaylevel True /shutdownapps True /forceappshutdown True'
                Complete-ToolRun $run -Status Success `
                    -Summary 'Office full online repair launched (closes Office; may download 1-2 GB)'
            }
            'ClearCreds' {
                $credLines = cmdkey /list | Select-String 'MicrosoftOffice'
                $count = 0
                foreach ($cred in $credLines) {
                    $target = ($cred.Line -replace '.*Target:\s*', '').Trim()
                    if ($target) {
                        cmdkey /delete:$target | Out-Null
                        if ($LASTEXITCODE -eq 0) { $count++ }
                    }
                }
                Complete-ToolRun $run -Status Success `
                    -Summary ('Cleared {0} Office credential(s) from Credential Manager' -f $count)
            }
            'Skip' {
                Complete-ToolRun $run -Status Skipped -Summary 'No action selected (silent default)'
            }
            default {
                Complete-ToolRun $run -Status Failed -Summary ('Unhandled choice: ' + $choice)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
