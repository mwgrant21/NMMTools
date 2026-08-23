function Remove-AdobeCC {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'adobe-cc-removal'

        Write-ToolOutput 'This will stop all Adobe processes, remove services, run the built-in uninstaller,'
        Write-ToolOutput 'attempt to download the Adobe Cleaner Tool, then remove all residual files,'
        Write-ToolOutput 'registry entries, and scheduled tasks.'
        Write-ToolOutput 'Note: clears Adobe user data for the currently logged-on user profile only.' -Level Warning

        # Strong confirm gate - default Cancel (safe)
        $gate = Read-ToolChoice `
            -Prompt 'Force-remove ALL Adobe software, settings, and user data (Lightroom catalogs, Photoshop presets under %APPDATA%\Adobe)? Type REMOVE to proceed' `
            -Choices @('REMOVE', 'Cancel') `
            -Default 'Cancel' `
            -Silent:$Silent

        if ($gate -ne 'REMOVE') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined Adobe CC removal'
            return
        }

        # Safe scoped Remove-Item for file system paths:
        # guards empty, too-short, and drive-root paths before acting
        $removeScopedPath = {
            param([string]$Path)
            if ([string]::IsNullOrWhiteSpace($Path)) { return }
            if ($Path -match '^[A-Za-z]:\\?$' -or $Path.Length -lt 8) { return }
            if (Test-Path $Path) {
                Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Step 1: Kill Adobe processes
        Write-ToolOutput 'Step 1: Stopping Adobe processes...' -Level Info
        $adobeProcs = @(
            'Creative Cloud', 'AdobeDesktopService', 'AdobeIPCBroker', 'AdobeUpdateService',
            'AGMService', 'AGSService', 'CCXProcess', 'CCLibrary', 'AdobeGCClient',
            'AdobeGCInvoker', 'acrobat', 'acrocef', 'acrord32', 'AdobeARM',
            'AdobeCollabSync'
        )
        foreach ($proc in $adobeProcs) {
            $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
            if ($running) {
                $running | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-ToolOutput ("  Stopped: {0}" -f $proc) -Level Detail
            }
        }
        Start-Sleep -Seconds 3
        Write-ToolOutput '  Processes stopped.' -Level Info

        # Step 2: Stop and delete Adobe services
        Write-ToolOutput 'Step 2: Removing Adobe services...' -Level Info
        $adobeSvcs = @(
            'AdobeARMservice', 'AdobeFlashPlayerUpdateSvc', 'AdobeUpdateService',
            'AGMService', 'AGSService', 'AdobeDesktopService'
        )
        foreach ($svc in $adobeSvcs) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                Stop-Service $svc -Force -ErrorAction SilentlyContinue
                & sc.exe delete $svc | Out-Null
                Write-ToolOutput ("  Removed service: {0}" -f $svc) -Level Detail
            }
        }
        Write-ToolOutput '  Services handled.' -Level Info

        # Step 3: Run built-in CC Uninstaller if present
        Write-ToolOutput 'Step 3: Running built-in CC Uninstaller...' -Level Info
        $uninstallers = @(
            "$env:ProgramFiles\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe",
            "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe"
        )
        $uninstRan = $false
        foreach ($u in $uninstallers) {
            if (-not [string]::IsNullOrWhiteSpace($u) -and $u.Length -ge 10 -and (Test-Path $u)) {
                $p = Start-Process $u -ArgumentList '--uninstall' -Wait -PassThru -ErrorAction SilentlyContinue
                Write-ToolOutput ("  Uninstaller exit code: {0}" -f $p.ExitCode) -Level Detail
                $uninstRan = $true
                Start-Sleep -Seconds 5
                break
            }
        }
        if (-not $uninstRan) {
            Write-ToolOutput '  Built-in uninstaller not found - continuing.' -Level Detail
        }

        # Step 4: Download and run Adobe Creative Cloud Cleaner Tool (try/catch guarded)
        Write-ToolOutput 'Step 4: Downloading Adobe Creative Cloud Cleaner Tool...' -Level Info
        $cleanerUrl = 'https://swupdl.adobe.com/updates/oobe/CreativeCloudDesktop/windows/AdobeCreativeCloudCleanerTool.exe'
        # Stage under a freshly created, randomly-named, admin-only-ACL'd directory rather
        # than a fixed filename in $env:TEMP (= C:\Windows\Temp under SYSTEM/PDQ,
        # world-writable) - a predictable path lets a standard user pre-create the file and
        # keep DACL control of it even after the download overwrites its contents, opening a
        # swap window before the elevated run. This download is the highest-risk of the
        # three in this codebase that download-then-execute-elevated: it comes from a
        # third-party CDN rather than a Microsoft/GitHub-signed endpoint.
        $stageDir = Join-Path $env:ProgramData ('NMMTools\stage\{0}' -f ([guid]::NewGuid().ToString('N')))
        try {
            New-Item -Path $stageDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            & icacls "$stageDir" /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' /grant:r 'BUILTIN\Administrators:(OI)(CI)F' | Out-Null
            $cleanerPath = Join-Path $stageDir 'AdobeCreativeCloudCleanerTool.exe'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($cleanerUrl, $cleanerPath)
            Write-ToolOutput '  Download complete.' -Level Info

            $sig = Get-AuthenticodeSignature -FilePath $cleanerPath
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Adobe') {
                throw ('Downloaded cleaner tool failed signature verification (status: {0}, signer: {1}).' -f $sig.Status, $sig.SignerCertificate.Subject)
            }
            Write-ToolOutput '  Authenticode signature verified (Adobe).' -Level Detail

            $cp = Start-Process $cleanerPath `
                -ArgumentList '--cleanupXML="" --removeAll=1 --eulaAccepted=1' `
                -Wait -PassThru -ErrorAction SilentlyContinue
            Write-ToolOutput ("  Cleaner tool exit code: {0}" -f $cp.ExitCode) -Level Detail
            Start-Sleep -Seconds 5
        } catch {
            Write-ToolOutput ("  Cleaner tool unavailable ({0}) - continuing with manual cleanup." -f $_.Exception.Message) -Level Warning
        } finally {
            Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Step 5: Remove residual Adobe file paths (ALL via removeScopedPath)
        Write-ToolOutput 'Step 5: Removing residual Adobe files...' -Level Info
        # $env:LOCALAPPDATA/$env:APPDATA under SYSTEM/PDQ resolve to the SYSTEM profile, not
        # any technician's - resolve the effective user's profile so this claimed
        # "currently logged-on user profile" cleanup doesn't silently miss the real data
        # while the tool still reports Success. Machine-wide paths (ProgramFiles/ProgramData/
        # CommonProgramFiles) are unaffected either way.
        $userProfile = Resolve-NmmUserProfileBase
        if (-not $userProfile.Local) { Write-ToolOutput ('Per-user Adobe data cleanup limited: {0}' -f $userProfile.Reason) -Level Warning }
        $adobePaths = @(
            "$env:ProgramFiles\Adobe",
            "${env:ProgramFiles(x86)}\Adobe",
            "$env:ProgramData\Adobe",
            "$env:CommonProgramFiles\Adobe",
            "${env:CommonProgramFiles(x86)}\Adobe"
        )
        if ($userProfile.Local)   { $adobePaths += (Join-Path $userProfile.Local 'Adobe') }
        if ($userProfile.Roaming) { $adobePaths += (Join-Path $userProfile.Roaming 'Adobe') }
        foreach ($aPath in $adobePaths) {
            & $removeScopedPath $aPath
            if (-not [string]::IsNullOrWhiteSpace($aPath) -and $aPath.Length -ge 8 -and (Test-Path $aPath)) {
                Write-ToolOutput ("  WARN: {0} may have locked files (reboot will clear)" -f $aPath) -Level Warning
            }
        }
        Write-ToolOutput '  File cleanup complete.' -Level Info

        # Step 6: Registry cleanup
        Write-ToolOutput 'Step 6: Removing Adobe registry keys...' -Level Info
        # HKCU: under SYSTEM/PDQ resolves to the SYSTEM profile's hive, not any technician's.
        $userHive = Resolve-NmmUserRegistryHive
        if (-not $userHive.Root) { Write-ToolOutput ('Per-user Adobe registry cleanup skipped: {0}' -f $userHive.Reason) -Level Warning }
        $regKeys = @(
            'HKLM:\SOFTWARE\Adobe',
            'HKLM:\SOFTWARE\WOW6432Node\Adobe'
        )
        if ($userHive.Root) { $regKeys += ('{0}\SOFTWARE\Adobe' -f $userHive.Root) }
        foreach ($regKey in $regKeys) {
            if (Test-Path $regKey) {
                Remove-Item $regKey -Recurse -Force -ErrorAction SilentlyContinue
                Write-ToolOutput ("  Removed: {0}" -f $regKey) -Level Detail
            }
        }
        foreach ($uninstRoot in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )) {
            Get-ChildItem $uninstRoot -ErrorAction SilentlyContinue | ForEach-Object {
                $dn = (Get-ItemProperty $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
                if ($dn -match '^Adobe') {
                    Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-ToolOutput ("  Removed uninstall entry: {0}" -f $dn) -Level Detail
                }
            }
        }
        Write-ToolOutput '  Registry cleanup complete.' -Level Info

        # Step 7: Remove Adobe scheduled tasks
        Write-ToolOutput 'Step 7: Removing Adobe scheduled tasks...' -Level Info
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match 'Adobe' -or $_.TaskPath -match 'Adobe' } |
            ForEach-Object {
                Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath `
                    -Confirm:$false -ErrorAction SilentlyContinue
                Write-ToolOutput ("  Removed task: {0}{1}" -f $_.TaskPath, $_.TaskName) -Level Detail
            }
        Write-ToolOutput '  Scheduled tasks removed.' -Level Info

        Complete-ToolRun $run -Status Success `
            -Summary 'All Adobe components removed (processes, services, files, registry, tasks); reboot recommended; cleared running-user Adobe profile data'
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
