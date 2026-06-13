function Invoke-OEMDriverUpdate {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'oem-driver-update'

        $manufacturer = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Manufacturer
        Write-ToolOutput ('Detected manufacturer: {0}' -f $manufacturer)

        if ($manufacturer -like '*Dell*') {
            $vendorName = 'Dell Command Update'
            $vendorExe  = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
            $vendorArgs = '/scan'
            $downloadUrl = 'https://www.dell.com/support/command-update'

            if (Test-Path $vendorExe) {
                Write-ToolOutput ('Found {0} at: {1}' -f $vendorName, $vendorExe)

                $choice = Read-ToolChoice `
                    -Prompt ('Run Dell Command Update driver/firmware scan?') `
                    -Choices @('Yes', 'No') `
                    -Default 'No' `
                    -Silent:$Silent

                if ($choice -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'User declined Dell Command Update scan'
                    return
                }

                Write-ToolOutput 'Launching Dell Command Update scan (this may take several minutes)...' -Level Info
                $proc = Start-Process -FilePath $vendorExe -ArgumentList $vendorArgs -Wait -PassThru -ErrorAction Stop
                Write-ToolOutput ('Dell Command Update exit code: {0}' -f $proc.ExitCode) -Level Detail

                Complete-ToolRun $run -Status Success `
                    -Summary ('Dell Command Update scan completed (exit {0})' -f $proc.ExitCode)
            } else {
                Write-ToolOutput ('Dell Command Update not installed ({0}).' -f $vendorExe) -Level Warning
                Write-ToolOutput ('Download from: {0}' -f $downloadUrl) -Level Detail
                Complete-ToolRun $run -Status Warning `
                    -Summary ('Dell Command Update not installed; download from {0}' -f $downloadUrl)
            }

        } elseif ($manufacturer -like '*Lenovo*') {
            $vendorName  = 'Lenovo System Update'
            $vendorExe   = 'C:\Program Files (x86)\Lenovo\System Update\tvsu.exe'
            $vendorArgs  = '/CM'
            $downloadUrl = 'https://support.lenovo.com/downloads/ds012808'

            if (Test-Path $vendorExe) {
                Write-ToolOutput ('Found {0} at: {1}' -f $vendorName, $vendorExe)

                $choice = Read-ToolChoice `
                    -Prompt ('Run Lenovo System Update driver/firmware update?') `
                    -Choices @('Yes', 'No') `
                    -Default 'No' `
                    -Silent:$Silent

                if ($choice -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'User declined Lenovo System Update'
                    return
                }

                Write-ToolOutput 'Launching Lenovo System Update (this may take several minutes)...' -Level Info
                $proc = Start-Process -FilePath $vendorExe -ArgumentList $vendorArgs -Wait -PassThru -ErrorAction Stop
                Write-ToolOutput ('Lenovo System Update exit code: {0}' -f $proc.ExitCode) -Level Detail

                Complete-ToolRun $run -Status Success `
                    -Summary ('Lenovo System Update completed (exit {0})' -f $proc.ExitCode)
            } else {
                Write-ToolOutput ('Lenovo System Update not installed ({0}).' -f $vendorExe) -Level Warning
                Write-ToolOutput ('Download from: {0}' -f $downloadUrl) -Level Detail
                Complete-ToolRun $run -Status Warning `
                    -Summary ('Lenovo System Update not installed; download from {0}' -f $downloadUrl)
            }

        } elseif ($manufacturer -like '*HP*' -or $manufacturer -like '*Hewlett*') {
            $vendorName      = 'HP Support Assistant'
            $vendorDetectExe = 'C:\Program Files (x86)\HP\HP Support Framework\UnifiedUpdateManager.exe'
            $vendorLaunchExe = 'C:\Program Files (x86)\HP\HP Support Framework\HPSupportSolutionsFrameworkService.exe'
            $downloadUrl     = 'https://support.hp.com/us-en/help/hp-support-assistant'

            if (Test-Path $vendorDetectExe) {
                Write-ToolOutput ('Found {0} at: {1}' -f $vendorName, $vendorDetectExe)

                $choice = Read-ToolChoice `
                    -Prompt ('Run HP Support Assistant driver/firmware update scan?') `
                    -Choices @('Yes', 'No') `
                    -Default 'No' `
                    -Silent:$Silent

                if ($choice -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'User declined HP Support Assistant scan'
                    return
                }

                Write-ToolOutput 'Launching HP Support Assistant...' -Level Info
                $proc = Start-Process -FilePath $vendorLaunchExe -Wait -PassThru -ErrorAction Stop
                Write-ToolOutput ('HP Support Assistant exit code: {0}' -f $proc.ExitCode) -Level Detail

                Complete-ToolRun $run -Status Success `
                    -Summary ('HP Support Assistant launched (exit {0})' -f $proc.ExitCode)
            } else {
                Write-ToolOutput ('HP Support Assistant not installed ({0}).' -f $vendorDetectExe) -Level Warning
                Write-ToolOutput ('Download from: {0}' -f $downloadUrl) -Level Detail
                Complete-ToolRun $run -Status Warning `
                    -Summary ('HP Support Assistant not installed; download from {0}' -f $downloadUrl)
            }

        } else {
            Write-ToolOutput ('Manufacturer "{0}" not recognized for automated OEM driver updates.' -f $manufacturer) -Level Warning
            Write-ToolOutput 'Check the vendor website for driver and firmware updates.' -Level Detail
            Complete-ToolRun $run -Status Warning `
                -Summary ('Manufacturer not recognized ({0}); check vendor website for driver updates' -f $manufacturer)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
