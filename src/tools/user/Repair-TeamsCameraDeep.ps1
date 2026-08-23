function Repair-TeamsCameraDeep {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-camera-deep'

        # HKCU: and $env:APPDATA under SYSTEM/PDQ resolve to the SYSTEM profile, not any
        # technician's - resolve the effective user's hive/profile so these fixes don't
        # silently no-op while still reporting Success.
        $userHive = Resolve-NmmUserRegistryHive
        if (-not $userHive.Root) { Write-ToolOutput ('Camera consent-store check limited: {0}' -f $userHive.Reason) -Level Warning }
        $camStore = if ($userHive.Root) { '{0}\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' -f $userHive.Root } else { 'Registry::HKEY_USERS\NO-USER-RESOLVED\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' }
        $userProfile = Resolve-NmmUserProfileBase
        $teamsPrefs = if ($userProfile.Roaming) { Join-Path $userProfile.Roaming 'Microsoft\Teams\desktop-config.json' } else { 'C:\NO-USER-RESOLVED\Microsoft\Teams\desktop-config.json' }
        $historyPath = Join-Path $env:ProgramData 'NMMTools\camera-fix-history.json'

        # --- Detect dock type ---
        $dockType = 'None'
        $dlSvc    = Get-Service -Name 'DisplayLinkService' -ErrorAction SilentlyContinue
        $dlDrv    = Get-WmiObject Win32_PnPSignedDriver -Filter "DriverProviderName='DisplayLink Corp.'" `
                        -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dlSvc -or $dlDrv) {
            $dockType = 'D6000-DisplayLink'
        } else {
            $tbDev = Get-PnpDevice -FriendlyName '*Thunderbolt*' -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if (-not $tbDev) {
                $tbDev = Get-PnpDevice -FriendlyName '*USB-C Dock*' -ErrorAction SilentlyContinue |
                         Select-Object -First 1
            }
            if ($tbDev) { $dockType = 'WD19-Thunderbolt' }
        }
        Write-ToolOutput ('Dock detected: {0}' -f $dockType) -Level Info

        # --- Enumerate camera devices ---
        $allCams = @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue)
        if ($allCams.Count -eq 0) {
            $allCams = @(Get-PnpDevice -FriendlyName '*camera*' -ErrorAction SilentlyContinue)
        }
        Write-ToolOutput ('Camera devices found: {0}' -f $allCams.Count) -Level Info
        foreach ($c in $allCams) {
            Write-ToolOutput ('  {0} [{1}]' -f $c.FriendlyName, $c.Status) -Level Detail
        }

        # Classify cameras
        $displayLinkCam = $null
        $irCam          = $null
        $physicalCam    = $null
        foreach ($c in $allCams) {
            if ($c.FriendlyName -match 'DisplayLink|Virtual Camera') {
                $displayLinkCam = $c
            } elseif ($c.FriendlyName -match 'IR Camera|Infrared|Windows Hello|IR$') {
                $irCam = $c
            } else {
                if (-not $physicalCam) { $physicalCam = $c }
            }
        }

        # --- Detect failure mode ---
        $failureMode = 'None'
        $consentVal = (Get-ItemProperty -LiteralPath $camStore -Name 'Value' -ErrorAction SilentlyContinue).Value
        if ([string]::IsNullOrWhiteSpace($consentVal) -or $consentVal -eq 'Deny') {
            $failureMode = 'ConsentMissing'
            Write-ToolOutput ('Consent store webcam value: {0} -- UNAVAILABLE mode' -f $consentVal) -Level Warning
        } else {
            Write-ToolOutput ('Consent store webcam value: {0}' -f $consentVal) -Level Detail
        }

        if ($failureMode -eq 'None') {
            if ($dockType -eq 'D6000-DisplayLink' -and $displayLinkCam) {
                $failureMode = 'DisplayLinkPriority'
                Write-ToolOutput ('DisplayLink virtual camera: {0} -- BLACK SCREEN mode likely' -f $displayLinkCam.FriendlyName) -Level Warning
            } elseif ($irCam -and $physicalCam) {
                $failureMode = 'IRCameraConflict'
                Write-ToolOutput ('IR camera ({0}) present alongside physical camera -- CONFLICT possible' -f $irCam.FriendlyName) -Level Warning
            }
        }

        if ($physicalCam) {
            Write-ToolOutput ('Physical camera: {0}' -f $physicalCam.FriendlyName) -Level Detail
        }

        # --- USB selective suspend check ---
        if ($physicalCam) {
            $devParamPath = ('HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters' -f $physicalCam.InstanceId)
            $usbSuspend = (Get-ItemProperty -LiteralPath $devParamPath -Name 'EnableSelectiveSuspend' `
                           -ErrorAction SilentlyContinue).EnableSelectiveSuspend
            if ($null -eq $usbSuspend -or $usbSuspend -eq 1) {
                Write-ToolOutput 'USB selective suspend: enabled -- may cause camera dropout on dock cycle' -Level Warning
            } else {
                Write-ToolOutput 'USB selective suspend: disabled' -Level Detail
            }
        }

        # --- Fix history ---
        $priorFixes = 0; $lastFix = ''
        if (Test-Path -LiteralPath $historyPath) {
            try {
                $hist = Get-Content $historyPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($hist -and $hist.Entries) {
                    $mine = @($hist.Entries | Where-Object { $_.ComputerName -eq $env:COMPUTERNAME })
                    $priorFixes = $mine.Count
                    if ($priorFixes -gt 0) { $lastFix = $mine[-1].Date }
                }
            } catch { }
        }
        if ($priorFixes -gt 0) {
            Write-ToolOutput ('{0} prior fix(es) on this machine (last: {1})' -f $priorFixes, $lastFix) -Level Warning
            Write-ToolOutput ('Pattern: dock re-enumeration on {0} resets the camera state on every cycle' -f $dockType) -Level Info
        } else {
            Write-ToolOutput 'No prior fixes recorded on this machine' -Level Detail
        }

        Write-ToolOutput ('Failure mode: {0}' -f $failureMode) -Level Info

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Camera deep fix' `
            -Choices @('None','Fix','Harden') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success `
                -Summary ('Diagnostic complete; mode={0}; {1} prior fix(es)' -f $failureMode, $priorFixes)
            return
        }

        $fixApplied    = New-Object System.Collections.Generic.List[string]
        $hardenApplied = New-Object System.Collections.Generic.List[string]

        # Consent store fix (always applied when missing)
        if ($failureMode -eq 'ConsentMissing' -and -not $userHive.Root) {
            # $camStore falls back to a path under a fabricated SID when the hive can't be
            # resolved - New-Item below would actually CREATE that bogus key under
            # HKEY_USERS if allowed to proceed. Skip outright instead.
            Write-ToolOutput ('Consent store fix skipped: {0}' -f $userHive.Reason) -Level Warning
        } elseif ($failureMode -eq 'ConsentMissing') {
            if (-not (Test-Path -LiteralPath $camStore)) {
                New-Item -LiteralPath $camStore -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Set-ItemProperty -LiteralPath $camStore -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
            $np = Join-Path $camStore 'NonPackaged'
            if (-not (Test-Path -LiteralPath $np)) {
                New-Item -LiteralPath $np -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Set-ItemProperty -LiteralPath $np -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
            $fixApplied.Add('Consent store restored (Allow)')
        }

        # DisplayLink virtual camera disable
        if ($failureMode -eq 'DisplayLinkPriority' -and $displayLinkCam) {
            Disable-PnpDevice -InstanceId $displayLinkCam.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
            $fixApplied.Add(('DisplayLink virtual camera disabled: {0}' -f $displayLinkCam.FriendlyName))
            # Clear Teams camera preference (new Teams)
            if (Test-Path -LiteralPath $teamsPrefs) {
                try {
                    $cfg = Get-Content $teamsPrefs -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($cfg.PSObject.Properties.Name -contains 'cameraDeviceId') {
                        $cfg.PSObject.Properties.Remove('cameraDeviceId')
                        $json = $cfg | ConvertTo-Json -Depth 10
                        [System.IO.File]::WriteAllText($teamsPrefs, $json, (New-Object System.Text.UTF8Encoding($false)))
                        $fixApplied.Add('Teams camera preference cleared')
                    }
                } catch { }
            }
        }

        # IR camera conflict fix
        if ($failureMode -eq 'IRCameraConflict' -and $irCam -and $physicalCam) {
            if (Test-Path -LiteralPath $teamsPrefs) {
                try {
                    $cfg = Get-Content $teamsPrefs -Raw -Encoding UTF8 | ConvertFrom-Json
                    $cfg | Add-Member -NotePropertyName 'cameraDeviceId' `
                        -NotePropertyValue $physicalCam.InstanceId -Force
                    $json = $cfg | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($teamsPrefs, $json, (New-Object System.Text.UTF8Encoding($false)))
                    $fixApplied.Add(('Teams preferred camera set to: {0}' -f $physicalCam.FriendlyName))
                } catch { }
            }
        }

        # Harden phase
        if ($action -eq 'Harden') {
            if ($physicalCam) {
                $devParamPath = ('HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters' -f $physicalCam.InstanceId)
                if (Test-Path -LiteralPath $devParamPath) {
                    Set-ItemProperty -LiteralPath $devParamPath -Name 'EnableSelectiveSuspend' `
                        -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    Set-ItemProperty -LiteralPath $devParamPath -Name 'IdleInWorkingState' `
                        -Value 0 -Type DWord -ErrorAction SilentlyContinue
                    $hardenApplied.Add('USB selective suspend disabled for physical camera')
                }
            }
            if (-not $userHive.Root) {
                Write-ToolOutput ('Consent store pin skipped: {0}' -f $userHive.Reason) -Level Warning
            } else {
                if (-not (Test-Path -LiteralPath $camStore)) {
                    New-Item -LiteralPath $camStore -Force -ErrorAction SilentlyContinue | Out-Null
                }
                Set-ItemProperty -LiteralPath $camStore -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
                $hardenApplied.Add('Consent store pinned Allow')
            }
        }

        # Write history
        $histDir = Split-Path $historyPath -Parent
        if (-not (Test-Path -LiteralPath $histDir)) {
            New-Item -ItemType Directory -Force -Path $histDir -ErrorAction SilentlyContinue | Out-Null
        }
        try {
            $existing = if (Test-Path -LiteralPath $historyPath) {
                Get-Content $historyPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } else {
                [PSCustomObject]@{ Entries = @() }
            }
            $newEntry = [PSCustomObject]@{
                Date         = (Get-Date -Format 'yyyy-MM-dd HH:mm')
                ComputerName = $env:COMPUTERNAME
                User         = $env:USERNAME
                DockType     = $dockType
                FailureMode  = $failureMode
                FixApplied   = ($fixApplied -join '; ')
                Hardened     = ($hardenApplied.Count -gt 0)
            }
            $allEntries = [System.Collections.ArrayList]@($existing.Entries)
            [void]$allEntries.Add($newEntry)
            [PSCustomObject]@{ Entries = $allEntries } |
                ConvertTo-Json -Depth 5 |
                Set-Content -Path $historyPath -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch { }

        $parts = @()
        if ($fixApplied.Count -gt 0)    { $parts += 'Fix: ' + ($fixApplied -join '; ') }
        if ($hardenApplied.Count -gt 0) { $parts += 'Hardened: ' + ($hardenApplied -join '; ') }
        if ($parts.Count -eq 0)         { $parts += 'No changes applied (mode: {0})' -f $failureMode }

        Complete-ToolRun $run -Status Success -Summary ($parts -join ' | ')
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
