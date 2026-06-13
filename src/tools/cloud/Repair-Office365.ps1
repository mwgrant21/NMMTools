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
            'C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe',
            'C:\Program Files (x86)\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'
        )
        $c2r = $c2rCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $c2r) {
            Write-ToolOutput 'Office Click-to-Run client not found.' -Level Warning
        }

        $choice = Read-ToolChoice -Prompt 'Office action' `
            -Choices @('UpdateRepair', 'ClearCreds', 'Skip') `
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
            'ClearCreds' {
                $credLines = cmdkey /list | Select-String 'MicrosoftOffice'
                $count = 0
                foreach ($cred in $credLines) {
                    $target = ($cred.Line -replace '.*Target:\s*', '').Trim()
                    if ($target) {
                        cmdkey /delete:$target | Out-Null
                        $count++
                    }
                }
                Complete-ToolRun $run -Status Success `
                    -Summary ('Cleared {0} Office credential(s) from Credential Manager' -f $count)
            }
            'Skip' {
                Complete-ToolRun $run -Status Skipped -Summary 'No action selected (silent default)'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
