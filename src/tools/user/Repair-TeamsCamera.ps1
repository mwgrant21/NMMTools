function Repair-TeamsCamera {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-camera-repair'

        # Camera and mic consent are per-user settings, so resolve WHOSE settings
        # to touch before building any path. When a technician elevates with
        # their own credentials on a standard user's laptop, HKCU: is the
        # technician's hive and every fix below would miss the reported fault.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # Gate BEFORE building any per-user path. Everything this tool reports
        # about permissions comes from the consent store, so an unresolved
        # target means the whole diagnosis is unavailable - not "clean".
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot read or repair camera/mic permissions - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $consentBase = 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
        $camStore = Get-UserHivePath -Context $ctx -SubPath ('{0}\webcam' -f $consentBase)
        $micStore = Get-UserHivePath -Context $ctx -SubPath ('{0}\microphone' -f $consentBase)

        # --- Report ---
        $cams = @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue)
        if ($cams.Count -eq 0) { $cams = @(Get-PnpDevice -FriendlyName '*camera*' -ErrorAction SilentlyContinue) }
        if ($cams.Count -gt 0) {
            Write-ToolOutput ('Camera devices: {0}' -f $cams.Count) -Level Info
            foreach ($c in $cams) { Write-ToolOutput ('  {0} [{1}]' -f $c.FriendlyName, $c.Status) -Level Detail }
        } else {
            Write-ToolOutput 'No camera devices found via PnP.' -Level Warning
        }

        $camVal = (Get-ItemProperty -LiteralPath $camStore -Name 'Value' -ErrorAction SilentlyContinue).Value
        $micVal = (Get-ItemProperty -LiteralPath $micStore -Name 'Value' -ErrorAction SilentlyContinue).Value
        $camLabel = '(unset)'; if ($camVal) { $camLabel = $camVal }
        $micLabel = '(unset)'; if ($micVal) { $micLabel = $micVal }
        Write-ToolOutput ('Camera access: {0}   Microphone access: {1}' -f $camLabel, $micLabel) -Level Detail

        $policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
        $policyBlock = $false
        if (Test-Path -LiteralPath $policyKey) {
            $camPol = (Get-ItemProperty -LiteralPath $policyKey -Name 'LetAppsAccessCamera' -ErrorAction SilentlyContinue).LetAppsAccessCamera
            $micPol = (Get-ItemProperty -LiteralPath $policyKey -Name 'LetAppsAccessMicrophone' -ErrorAction SilentlyContinue).LetAppsAccessMicrophone
            if ($camPol -eq 2 -or $micPol -eq 2) {
                Write-ToolOutput 'WARNING: camera/mic access is BLOCKED by IT policy (GPO/MDM) - cannot be overridden here.' -Level Warning
                $policyBlock = $true
            } else {
                Write-ToolOutput 'No GPO/MDM camera/mic policy block detected.' -Level Detail
            }
        } else {
            Write-ToolOutput 'No AppPrivacy policy key (no GPO/MDM block).' -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Camera / mic action' `
            -Choices @('None','FixPermissions','ResetMediaStack','ReinstallDriver') -Default 'None' -Silent:$Silent

        switch ($action) {

            'FixPermissions' {
                if (-not $ctx.Resolved) {
                    Complete-ToolRun $run -Status Failed `
                        -Summary ('Cannot set camera/mic permissions - {0}. Nothing was changed.' -f $ctx.Reason)
                    return
                }
                foreach ($store in @($camStore, $micStore)) {
                    if (-not (Test-Path -LiteralPath $store)) { New-Item -LiteralPath $store -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -LiteralPath $store -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
                    $np = Join-Path $store 'NonPackaged'
                    if (-not (Test-Path -LiteralPath $np)) { New-Item -LiteralPath $np -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -LiteralPath $np -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
                }
                $fixed = 0
                foreach ($store in @($camStore, $micStore)) {
                    $np = Join-Path $store 'NonPackaged'
                    if (Test-Path -LiteralPath $np) {
                        Get-ChildItem -LiteralPath $np -ErrorAction SilentlyContinue | ForEach-Object {
                            if ($_.PSChildName -match 'ms-teams|MSTeams|Teams') {
                                $v = (Get-ItemProperty -LiteralPath $_.PSPath -Name 'Value' -ErrorAction SilentlyContinue).Value
                                if ($v -eq 'Deny') {
                                    Set-ItemProperty -LiteralPath $_.PSPath -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
                                    $fixed++
                                }
                            }
                        }
                    }
                }
                $camOk = (Get-ItemProperty -LiteralPath $camStore -Name 'Value' -ErrorAction SilentlyContinue).Value -eq 'Allow'
                $micOk = (Get-ItemProperty -LiteralPath $micStore -Name 'Value' -ErrorAction SilentlyContinue).Value -eq 'Allow'
                foreach ($p in @('ms-teams','MSTeams','Teams')) { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue }
                Start-Sleep -Seconds 2
                # Start-Process would launch Teams as the ELEVATED account, in the
                # wrong session and against the wrong profile. Only relaunch when
                # this process already belongs to the logged-on user.
                $teamsNote = 'ask the user to reopen Teams'
                if (-not $ctx.IsRedirected) {
                    Start-Process 'ms-teams:' -ErrorAction SilentlyContinue
                    $teamsNote = 'Teams restarted'
                } else {
                    Write-ToolOutput 'Teams was closed. Ask the user to reopen it - it cannot be relaunched as them from an elevated session.' -Level Warning
                }
                if ($policyBlock) {
                    Complete-ToolRun $run -Status Warning -Summary ('Camera/mic set to Allow for {0} ({1} Teams deny entries fixed) but an IT policy block is in effect' -f $ctx.UserName, $fixed)
                } elseif (-not ($camOk -and $micOk)) {
                    Complete-ToolRun $run -Status Warning -Summary ('Camera/mic permission write could not be confirmed for {0} (camera={1}, mic={2}); a higher-level block may be present' -f $ctx.UserName, $camOk, $micOk)
                } else {
                    Complete-ToolRun $run -Status Success -Summary ('Camera/mic set to Allow for {0} ({1} Teams deny entries fixed); {2}' -f $ctx.UserName, $fixed, $teamsNote)
                }
            }

            'ResetMediaStack' {
                $hogs = @('Teams','ms-teams','MSTeams','WebexMeetings','zoom','CiscoCollabHost','lync','communicator','chrome','msedge','firefox','CameraApp')
                $running = @($hogs | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
                Write-ToolOutput 'WARNING: this CLOSES camera-using apps before resetting the media stack.' -Level Warning
                if ($running.Count -gt 0) { Write-ToolOutput ('Will close: {0}' -f ($running -join ', ')) -Level Detail }
                $confirm = Read-ToolChoice -Prompt 'Close those apps and reset the Teams camera/media stack?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ResetMediaStack cancelled'
                } else {
                    foreach ($p in $hogs) { Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
                    Start-Sleep -Seconds 2
                    # $env:APPDATA is the CALLING account's profile. Under an
                    # elevated session that is the technician, so clearing it
                    # would wipe their Teams cache and leave the user's intact.
                    $cleared = 0
                    if ($ctx.Resolved) {
                        $cachePaths = @(
                            (Join-Path $ctx.AppData 'Microsoft\Teams\Cache'),
                            (Join-Path $ctx.AppData 'Microsoft\Teams\blob_storage'),
                            (Join-Path $ctx.AppData 'Microsoft\Teams\databases'),
                            (Join-Path $ctx.AppData 'Microsoft\Teams\GPUCache'),
                            (Join-Path $ctx.AppData 'Microsoft\Teams\IndexedDB'),
                            (Join-Path $ctx.AppData 'Microsoft\Teams\Local Storage'),
                            (Join-Path $ctx.AppData 'Microsoft\Teams\tmp'),
                            (Join-Path $ctx.LocalAppData 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Cache'),
                            (Join-Path $ctx.LocalAppData 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView')
                        )
                        foreach ($cp in $cachePaths) {
                            if (Test-Path -LiteralPath $cp) {
                                # Containment-gated: this is the exact path shape
                                # (LocalCache under the MSIX package) proven to be
                                # junction-hijackable by a non-elevated user.
                                if (-not (Remove-UserPathContent -Context $ctx -Path $cp)) { continue }
                                $cleared++
                            }
                        }
                    } else {
                        Write-ToolOutput ('Skipping Teams cache clear - {0}.' -f $ctx.Reason) -Level Warning
                    }
                    # Camera-focused reset (v8 tool 97); mic permissions are handled by the FixPermissions action.
                    if ($ctx.Resolved -and (Test-Path -LiteralPath $camStore)) { Set-ItemProperty -LiteralPath $camStore -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue }
                    try {
                        Stop-Service -Name 'FrameServer' -Force -ErrorAction Stop
                        Start-Sleep -Seconds 2
                        Start-Service -Name 'FrameServer' -ErrorAction SilentlyContinue
                        Write-ToolOutput 'Camera Frame Server restarted.' -Level Detail
                    } catch {
                        Write-ToolOutput 'Could not restart Camera Frame Server (skipping).' -Level Warning
                    }
                    $cycled = 0
                    foreach ($cam in $cams) {
                        try {
                            if ($cam.Status -eq 'OK') {
                                Disable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                Start-Sleep -Seconds 2
                                Enable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                $cycled++
                            } elseif ($cam.Status -eq 'Error') {
                                Enable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
                                $cycled++
                            }
                        } catch { }
                    }
                    Complete-ToolRun $run -Status Success -Summary ('Media stack reset: {0} cache location(s) cleared, {1} camera device(s) cycled' -f $cleared, $cycled)
                }
            }

            'ReinstallDriver' {
                if ($cams.Count -eq 0) {
                    Complete-ToolRun $run -Status Warning -Summary 'No camera devices found; nothing to reinstall'
                } else {
                    Write-ToolOutput 'WARNING: this REMOVES the camera driver - a REBOOT is required and the camera is offline until then.' -Level Warning
                    Write-ToolOutput 'It will also CLOSE camera-using apps (Teams, browsers, Camera app) to release the device.' -Level Warning
                    $confirm = Read-ToolChoice -Prompt 'Remove the camera driver(s) and let Windows reinstall on reboot?' `
                        -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                    if ($confirm -ne 'Yes') {
                        Complete-ToolRun $run -Status Skipped -Summary 'ReinstallDriver cancelled'
                    } else {
                        foreach ($p in @('Teams','ms-teams','MSTeams','WebexMeetings','zoom','chrome','msedge','firefox','CameraApp','WindowsCamera')) {
                            Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        }
                        Start-Sleep -Seconds 2
                        $removed = 0
                        foreach ($cam in $cams) {
                            & pnputil.exe /remove-device $cam.InstanceId *>$null
                            if ($LASTEXITCODE -eq 0) {
                                Write-ToolOutput ('  Removed driver: {0}' -f $cam.FriendlyName) -Level Success
                                $removed++
                            } else {
                                Write-ToolOutput ('  Could not remove {0} via pnputil (exit {1}); use Device Manager > Uninstall device' -f $cam.FriendlyName, $LASTEXITCODE) -Level Warning
                            }
                        }
                        try {
                            $session = New-Object -ComObject Microsoft.Update.Session
                            $searcher = $session.CreateUpdateSearcher()
                            $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
                            $camUpd = @($result.Updates | Where-Object { $_.Title -match 'camera|webcam|video|imaging' })
                            if ($camUpd.Count -gt 0) {
                                Write-ToolOutput ('Windows Update has {0} camera driver update(s) pending:' -f $camUpd.Count) -Level Info
                                foreach ($u in $camUpd) { Write-ToolOutput ('  - {0}' -f $u.Title) -Level Detail }
                            } else {
                                Write-ToolOutput 'No pending camera driver updates in Windows Update.' -Level Detail
                            }
                        } catch {
                            Write-ToolOutput 'Could not query Windows Update for driver updates (check Settings manually).' -Level Detail
                        }
                        if ($removed -gt 0) {
                            Complete-ToolRun $run -Status Success -Summary ('Removed {0} camera driver(s); REBOOT to trigger automatic reinstall' -f $removed)
                        } else {
                            Complete-ToolRun $run -Status Warning -Summary 'No camera drivers removed; use Device Manager to uninstall manually'
                        }
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Teams camera state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
