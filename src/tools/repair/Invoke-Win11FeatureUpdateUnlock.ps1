function Invoke-Win11FeatureUpdateUnlock {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'win11-feature-unlock'

        # --- Diagnostic: current Windows version (safe read; no changes) ---
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $dispVer  = if ($cv -and $cv.DisplayVersion)    { $cv.DisplayVersion }    else { 'Unknown' }
        $buildNum = if ($cv -and $cv.CurrentBuildNumber) { ('{0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR) } else { 'Unknown' }
        Write-ToolOutput ('Current Windows version : {0}' -f $dispVer)
        Write-ToolOutput ('Build number            : {0}' -f $buildNum)

        # --- Diagnostic: version-lock policy status (safe read; no changes) ---
        $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $uxPath     = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $lockFound  = $false

        Write-ToolOutput 'Checking for version-lock policy keys...' -Level Info
        if (Test-Path $policyPath) {
            $pol = Get-ItemProperty $policyPath -ErrorAction SilentlyContinue
            foreach ($key in @('TargetReleaseVersion', 'TargetReleaseVersionInfo',
                               'DisableWindowsUpdateAccess', 'SetDisableUXWUAccess',
                               'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays')) {
                if ($null -ne $pol.$key) {
                    Write-ToolOutput ('[LOCKED] Policy key present: {0} = {1}' -f $key, $pol.$key) -Level Warning
                    $lockFound = $true
                }
            }
        }
        if (Test-Path $uxPath) {
            $ux = Get-ItemProperty $uxPath -ErrorAction SilentlyContinue
            foreach ($key in @('TargetReleaseVersion', 'TargetReleaseVersionInfo')) {
                if ($null -ne $ux.$key) {
                    Write-ToolOutput ('[LOCKED] UX Settings key present: {0} = {1}' -f $key, $ux.$key) -Level Warning
                    $lockFound = $true
                }
            }
        }
        if (-not $lockFound) {
            Write-ToolOutput 'No version-lock keys detected in registry.' -Level Info
        }

        # --- BREAK-GLASS gate: ALL destructive steps are behind this typed confirm ---
        $gate = Read-ToolChoice `
            -Prompt 'This REMOVES Windows Update version-lock GPO keys and stages a Win11 feature upgrade that can reboot the machine. Type UNLOCK to proceed' `
            -Choices @('UNLOCK', 'Cancel') `
            -Default 'Cancel' `
            -Silent:$Silent

        if ($gate -ne 'UNLOCK') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined Win11 feature update unlock'
            return
        }

        # ================================================================
        # All steps below are executed ONLY after the typed UNLOCK confirm
        # ================================================================

        # Step 1: Remove version-lock policy keys
        Write-ToolOutput 'Removing version-lock policy keys...' -Level Info
        if (Test-Path $policyPath) {
            foreach ($key in @('TargetReleaseVersion', 'TargetReleaseVersionInfo',
                               'DisableWindowsUpdateAccess', 'SetDisableUXWUAccess',
                               'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays')) {
                Remove-ItemProperty -Path $policyPath -Name $key -ErrorAction SilentlyContinue
                Write-ToolOutput ('  Policy key removed (if present): {0}' -f $key) -Level Detail
            }
        }
        if (Test-Path $uxPath) {
            foreach ($key in @('TargetReleaseVersion', 'TargetReleaseVersionInfo')) {
                Remove-ItemProperty -Path $uxPath -Name $key -ErrorAction SilentlyContinue
                Write-ToolOutput ('  UX Settings key removed (if present): {0}' -f $key) -Level Detail
            }
        }
        Write-ToolOutput 'Policy key removal complete.' -Level Info

        # Step 2: gpupdate /force
        Write-ToolOutput 'Running gpupdate /force...' -Level Info
        $gp = Start-Process -FilePath 'gpupdate.exe' `
            -ArgumentList '/force /target:computer /wait:0' `
            -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
        if ($gp -and $gp.ExitCode -eq 0) {
            Write-ToolOutput 'gpupdate completed (exit 0).' -Level Info
        } else {
            $gpExit = if ($gp) { $gp.ExitCode } else { 'n/a' }
            Write-ToolOutput ('gpupdate exit code: {0}' -f $gpExit) -Level Warning
        }

        # Step 3: Stop services, clear SoftwareDistribution\Download, restart services
        Write-ToolOutput 'Flushing Windows Update cache (stop services, clear Download folder, restart)...' -Level Info
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service bits     -Force -ErrorAction SilentlyContinue
        Stop-Service cryptsvc -Force -ErrorAction SilentlyContinue

        $sdDownload = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
        if (Test-Path $sdDownload) {
            Remove-Item (Join-Path $sdDownload '*') -Recurse -Force -ErrorAction SilentlyContinue
        }

        Start-Service cryptsvc -ErrorAction SilentlyContinue
        Start-Service bits     -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Write-ToolOutput 'WU cache flushed; services restarted.' -Level Info

        # Step 4: Download and run Windows 11 Installation Assistant
        Write-ToolOutput 'Downloading Windows 11 Installation Assistant...' -Level Info
        $assistantUrl  = 'https://go.microsoft.com/fwlink/?linkid=2171764'
        $assistantPath = Join-Path $env:TEMP 'Windows11InstallationAssistant.exe'
        try {
            try {
                Import-Module BitsTransfer -ErrorAction Stop
                Start-BitsTransfer -Source $assistantUrl -Destination $assistantPath `
                    -TransferType Download -ErrorAction Stop
                Write-ToolOutput 'Download complete via BITS.' -Level Info
            } catch {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $assistantUrl -OutFile $assistantPath `
                    -UseBasicParsing -ErrorAction Stop
                Write-ToolOutput 'Download complete via WebRequest.' -Level Info
            }

            $fileSize = (Get-Item $assistantPath -ErrorAction SilentlyContinue).Length
            if (-not $fileSize -or $fileSize -lt 1MB) {
                throw ('Downloaded assistant file appears invalid (size: {0} bytes).' -f $fileSize)
            }
            Write-ToolOutput ('File size: {0} MB' -f [math]::Round($fileSize / 1MB, 1)) -Level Detail

            Write-ToolOutput 'Launching Win11 Installation Assistant (silent - this is long-running)...' -Level Info
            $proc = Start-Process -FilePath $assistantPath `
                -ArgumentList '/QuietInstall /SkipEULA /NoRestartUI' `
                -NoNewWindow -Wait -PassThru -ErrorAction Stop
            Write-ToolOutput ('Installation Assistant exit code: {0}' -f $proc.ExitCode) -Level Detail

            if ($proc.ExitCode -notin @(0, 1)) {
                throw ('Installation Assistant returned error code {0}.' -f $proc.ExitCode)
            }
        } catch {
            throw ('Win11 Installation Assistant step failed: {0}' -f $_.Exception.Message)
        }

        Write-ToolOutput 'Feature upgrade staged. The machine will reboot to complete the Win11 upgrade.' -Level Warning
        Complete-ToolRun $run -Status Success `
            -Summary 'Win11 version-lock keys removed, WU cache flushed, feature upgrade staged; machine will reboot'
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
