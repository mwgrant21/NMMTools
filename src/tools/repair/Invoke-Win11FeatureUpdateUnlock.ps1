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

        # gpupdate /force previously ran here. Dropped: in the realistic break-glass scenario
        # for this tool (one machine needs an override while the source GPO is still linked
        # for the rest of the fleet), gpupdate would silently re-apply the exact policy keys
        # Step 1 just removed before the WU cache flush or Installation Assistant even ran -
        # self-defeating the tool's entire purpose. The registry removal above is what
        # actually matters for this override; it does not depend on a gpupdate cycle to take
        # effect.

        # Step 2: Stop services, clear SoftwareDistribution\Download, restart services
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

        # Step 3: Download and run Windows 11 Installation Assistant
        Write-ToolOutput 'Downloading Windows 11 Installation Assistant...' -Level Info
        $assistantUrl  = 'https://go.microsoft.com/fwlink/?linkid=2171764'
        # Stage under a freshly created, randomly-named, admin-only-ACL'd directory rather
        # than a fixed filename in $env:TEMP (= C:\Windows\Temp under SYSTEM/PDQ,
        # world-writable) - a predictable path lets a standard user pre-create the file and
        # keep DACL control of it even after the download overwrites its contents, opening a
        # swap window before the elevated run.
        $stageDir = Join-Path $env:ProgramData ('NMMTools\stage\{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -Path $stageDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        & icacls "$stageDir" /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' /grant:r 'BUILTIN\Administrators:(OI)(CI)F' | Out-Null
        $assistantPath = Join-Path $stageDir 'Windows11InstallationAssistant.exe'
        try {
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

                # A size floor is not an integrity check - verify the file is
                # Authenticode-signed and actually signed by Microsoft before running it
                # elevated.
                $sig = Get-AuthenticodeSignature -FilePath $assistantPath
                if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
                    throw ('Downloaded assistant failed signature verification (status: {0}, signer: {1}).' -f $sig.Status, $sig.SignerCertificate.Subject)
                }
                Write-ToolOutput 'Authenticode signature verified (Microsoft Corporation).' -Level Detail

                Write-ToolOutput 'Launching Win11 Installation Assistant (silent - this is long-running)...' -Level Info
                $proc = Start-Process -FilePath $assistantPath `
                    -ArgumentList '/QuietInstall /SkipEULA /NoRestartUI' `
                    -NoNewWindow -Wait -PassThru -ErrorAction Stop
                Write-ToolOutput ('Installation Assistant exit code: {0}' -f $proc.ExitCode) -Level Detail

                if ($proc.ExitCode -notin @(0, 1)) {
                    throw ('Installation Assistant returned error code {0}.' -f $proc.ExitCode)
                }
            } finally {
                Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
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
