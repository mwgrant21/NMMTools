function Repair-OnBaseAddinPermanent {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'onbase-addin-fix'

        # Add-in registration and Outlook resiliency state are per-user. Resolve
        # the target account before building key paths.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # Hive labels are explicit, not inferred from the path: once the
        # per-user root can be 'Registry::HKEY_USERS\<sid>\...', any pattern
        # test against the path string is a silent-failure waiting to happen.
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot read or repair the OnBase add-in - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $addinRoots = @(
            @{ Path = (Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Office\16.0\Outlook\Addins'); Hive = 'HKCU' },
            @{ Path = 'HKLM:\Software\Microsoft\Office\16.0\Outlook\Addins';             Hive = 'HKLM' },
            @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Office\16.0\Outlook\Addins'; Hive = 'HKLM' }
        )
        $resilRoot     = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Office\16.0\Outlook\Resiliency'
        $disabledKey   = Join-Path $resilRoot 'DisabledItems'
        $crashKey      = Join-Path $resilRoot 'CrashedAddinList'
        $doNotDisKey   = Join-Path $resilRoot 'DoNotDisableAddinList'
        $addinTimesKey = Join-Path $resilRoot 'AddinLoadTimes'
        $hklmBase      = 'HKLM:\Software\Microsoft\Office\16.0\Outlook\Addins'

        # --- Find OnBase/Hyland add-in across all hives ---
        $onbaseAddins = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $addinRoots) {
            $root = $entry.Path
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                if ($k.PSChildName -match 'OnBase|Hyland') {
                    $props = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                    $lb    = $null
                    if ($props -and ($props.PSObject.Properties.Name -contains 'LoadBehavior')) {
                        $lb = [int]$props.LoadBehavior
                    }
                    $fn = $k.PSChildName
                    if ($props -and $props.FriendlyName) { $fn = $props.FriendlyName }
                    $onbaseAddins.Add([PSCustomObject]@{
                        ProgId       = $k.PSChildName
                        FriendlyName = $fn
                        LoadBehavior = $lb
                        Hive         = $entry.Hive
                        PSPath       = $k.PSPath
                    })
                }
            }
        }

        if ($onbaseAddins.Count -eq 0) {
            Complete-ToolRun $run -Status Warning `
                -Summary 'No OnBase/Hyland add-in found in HKCU or HKLM Outlook Addins'
            return
        }

        Write-ToolOutput ('OnBase/Hyland add-in(s) found: {0}' -f $onbaseAddins.Count) -Level Info
        foreach ($a in $onbaseAddins) {
            $lbText = if ($null -ne $a.LoadBehavior) { [string]$a.LoadBehavior } else { 'n/a' }
            $lbLabel = switch ($a.LoadBehavior) {
                3       { 'Load at startup (correct)' }
                2       { 'Load on demand' }
                0       { 'Disabled' }
                default { 'Unknown' }
            }
            $level = if ($a.LoadBehavior -ne 3) { 'Warning' } else { 'Info' }
            Write-ToolOutput ('  [{0}] {1}  LoadBehavior={2} ({3})' -f `
                $a.Hive, $a.FriendlyName, $lbText, $lbLabel) -Level $level
        }

        # --- Resiliency state ---
        $disabledCount = 0
        if (Test-Path -LiteralPath $disabledKey) {
            $dp = (Get-ItemProperty -LiteralPath $disabledKey -ErrorAction SilentlyContinue).PSObject.Properties |
                  Where-Object { $_.Name -notmatch '^PS' }
            $disabledCount = @($dp).Count
        }
        $crashCount = 0
        if (Test-Path -LiteralPath $crashKey) {
            $cp = (Get-ItemProperty -LiteralPath $crashKey -ErrorAction SilentlyContinue).PSObject.Properties |
                  Where-Object { $_.Name -notmatch '^PS' }
            $crashCount = @($cp).Count
        }
        Write-ToolOutput ('Resiliency DisabledItems: {0}; CrashedAddinList: {1}' -f `
            $disabledCount, $crashCount) -Level $(if ($disabledCount -gt 0 -or $crashCount -gt 0) { 'Warning' } else { 'Info' })

        # --- Load time ---
        $recordedMs = $null
        if (Test-Path -LiteralPath $addinTimesKey) {
            foreach ($a in $onbaseAddins) {
                $ms = (Get-ItemProperty -LiteralPath $addinTimesKey -Name $a.ProgId `
                       -ErrorAction SilentlyContinue).$($a.ProgId)
                if ($null -ne $ms) { $recordedMs = [int]$ms; break }
            }
        }
        if ($null -ne $recordedMs) {
            $tLevel = if ($recordedMs -gt 1000) { 'Warning' } else { 'Info' }
            Write-ToolOutput ('Recorded add-in load time: {0}ms (threshold: 1000ms)' -f $recordedMs) -Level $tLevel
        }

        # --- DoNotDisable check ---
        $alreadyPinned = $false
        if (Test-Path -LiteralPath $doNotDisKey) {
            foreach ($a in $onbaseAddins) {
                $val = (Get-ItemProperty -LiteralPath $doNotDisKey -Name $a.ProgId `
                        -ErrorAction SilentlyContinue).$($a.ProgId)
                if ($val -eq 1) { $alreadyPinned = $true; break }
            }
        }
        Write-ToolOutput ('DoNotDisableAddinList: {0}' -f $(if ($alreadyPinned) { 'Already pinned' } else { 'Not set' })) `
            -Level $(if ($alreadyPinned) { 'Info' } else { 'Warning' })

        # --- Self-heal task check ---
        $taskName  = 'NMMTools-OnBaseAddinCheck'
        $taskExists = $false
        try {
            $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            $taskExists = $null -ne $existing
        } catch { }
        Write-ToolOutput ('Self-heal task ({0}): {1}' -f $taskName, $(if ($taskExists) { 'Exists' } else { 'Not created' })) `
            -Level $(if ($taskExists) { 'Info' } else { 'Warning' })

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'OnBase add-in permanent fix' `
            -Choices @('None','Fix','Harden') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success `
                -Summary ('{0} OnBase add-in(s) found; LB={1}; disabled={2}; crashed={3}; no action taken' -f `
                    $onbaseAddins.Count, $onbaseAddins[0].LoadBehavior, $disabledCount, $crashCount)
            return
        }

        # Everything past this point writes per-user state. Applying it to the
        # technician's hive would leave the reported Outlook fault untouched.
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot apply the OnBase add-in fix - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $changes = New-Object System.Collections.Generic.List[string]

        # Clear resiliency blocks
        if (Test-Path -LiteralPath $disabledKey) {
            Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $disabledKey)) {
                $changes.Add(('Cleared {0} DisabledItems entr(ies)' -f $disabledCount))
            } else {
                Write-ToolOutput 'DisabledItems key could not be removed (may be locked)' -Level Warning
            }
        }
        if (Test-Path -LiteralPath $crashKey) {
            Remove-Item -LiteralPath $crashKey -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $crashKey)) {
                $changes.Add(('Cleared {0} CrashedAddinList entr(ies)' -f $crashCount))
            } else {
                Write-ToolOutput 'CrashedAddinList key could not be removed (may be locked)' -Level Warning
            }
        }

        # Restore LoadBehavior = 3
        foreach ($a in $onbaseAddins) {
            if ($a.LoadBehavior -ne 3) {
                Set-ItemProperty -LiteralPath $a.PSPath -Name 'LoadBehavior' `
                    -Value 3 -Type DWord -ErrorAction SilentlyContinue
                $verifyLb = (Get-ItemProperty -LiteralPath $a.PSPath -Name 'LoadBehavior' `
                             -ErrorAction SilentlyContinue).LoadBehavior
                if ($verifyLb -eq 3) {
                    $changes.Add(('{0} LoadBehavior set to 3' -f $a.ProgId))
                } else {
                    Write-ToolOutput ('{0} LoadBehavior write failed (key may be HKLM-locked)' -f $a.ProgId) -Level Warning
                }
            }
        }

        if ($action -eq 'Harden') {
            # Add to DoNotDisableAddinList
            if (-not (Test-Path -LiteralPath $doNotDisKey)) {
                New-Item -LiteralPath $doNotDisKey -Force -ErrorAction SilentlyContinue | Out-Null
            }
            foreach ($a in $onbaseAddins) {
                New-ItemProperty -LiteralPath $doNotDisKey -Name $a.ProgId `
                    -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
                $verifyDnd = (Get-ItemProperty -LiteralPath $doNotDisKey -Name $a.ProgId `
                              -ErrorAction SilentlyContinue).$($a.ProgId)
                if ($verifyDnd -eq 1) {
                    $changes.Add(('{0} added to DoNotDisableAddinList' -f $a.ProgId))
                } else {
                    Write-ToolOutput ('{0} DoNotDisableAddinList write failed' -f $a.ProgId) -Level Warning
                }
            }

            # Raise startup timeout to 5000ms
            $addinTimeoutDir = Join-Path $resilRoot 'AddinLoadTimeOut'
            if (-not (Test-Path -LiteralPath $addinTimeoutDir)) {
                New-Item -LiteralPath $addinTimeoutDir -Force -ErrorAction SilentlyContinue | Out-Null
            }
            foreach ($a in $onbaseAddins) {
                New-ItemProperty -LiteralPath $addinTimeoutDir -Name $a.ProgId `
                    -Value 5000 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
                $verifyTo = (Get-ItemProperty -LiteralPath $addinTimeoutDir -Name $a.ProgId `
                             -ErrorAction SilentlyContinue).$($a.ProgId)
                if ($verifyTo -eq 5000) {
                    $changes.Add(('{0} startup timeout raised to 5000ms' -f $a.ProgId))
                } else {
                    Write-ToolOutput ('{0} AddinLoadTimeOut write failed' -f $a.ProgId) -Level Warning
                }
            }

            # HKLM registration fallback: REMOVED, deliberately.
            #
            # This used to copy an add-in registration found under the target
            # user's HKCU into HKLM so it would survive a profile reset. That is
            # a privilege escalation, not a repair: HKCU\...\Outlook\Addins is
            # writable by the standard user who owns the profile, so they can
            # create a key matching /OnBase|Hyland/ with a Manifest or CLSID of
            # their choosing, open a ticket, and have the elevated toolkit
            # promote it to a machine-wide registration that loads in Outlook
            # for every user of the box. Nothing here can distinguish a genuine
            # Hyland registration from one the user planted a minute earlier.
            #
            # Machine-wide registration is legitimate, but it has to come from a
            # trusted source (the vendor installer or a PDQ package), never from
            # data copied out of a user-writable hive.
            $hkcuOnly = @($onbaseAddins | Where-Object { $_.Hive -eq 'HKCU' })
            if ($hkcuOnly.Count -gt 0) {
                Write-ToolOutput ('{0} add-in(s) are registered only in the user hive.' -f $hkcuOnly.Count) -Level Warning
                Write-ToolOutput 'Not promoting them to HKLM: that hive is user-writable, so a planted key would become a machine-wide Outlook add-in.' -Level Warning
                Write-ToolOutput ('To make OnBase survive a profile reset, deploy the vendor installer machine-wide (HKLM {0}) via PDQ instead.' -f $hklmBase) -Level Info
            }

            # Self-heal scheduled task.
            #
            # ProgIds are REGISTRY KEY NAMES read from a hive the standard user
            # can write. The previous version pasted them into the generated
            # script as quoted literals, so a key named
            #     OnBase'; <arbitrary code>; '
            # became executable code inside a scheduled task. Two independent
            # defences now apply, because either one alone is a single point of
            # failure:
            #
            #   1. Whitelist. A real Outlook ProgID is dotted alphanumerics.
            #      Anything else is dropped, loudly, and never reaches the task.
            #   2. Data, not code. The survivors are carried as a base64 blob and
            #      decoded at runtime. The base64 alphabet has no quote or
            #      statement separator in it, so the value provably cannot
            #      terminate the string literal that holds it.
            $validProgId = '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
            $safeProgIds = New-Object System.Collections.Generic.List[string]
            foreach ($a in $onbaseAddins) {
                if ($a.ProgId -match $validProgId) {
                    $safeProgIds.Add($a.ProgId)
                } else {
                    Write-ToolOutput ('SECURITY: add-in key name is not a valid ProgID and was excluded from the self-heal task: {0}' -f $a.ProgId) -Level Warning
                }
            }
            $progIdBlob = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes(($safeProgIds -join ';'))
            )
            $healScript = @"
`$resil = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
`$log   = (Join-Path `$env:ProgramData 'NMMTools\onbase-addin-heal.log')
`$addins = @(([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$progIdBlob')) -split ';') | Where-Object { `$_ })
foreach (`$progId in `$addins) {
    `$roots = @(
        "HKCU:\Software\Microsoft\Office\16.0\Outlook\Addins\`$progId",
        "HKLM:\Software\Microsoft\Office\16.0\Outlook\Addins\`$progId"
    )
    foreach (`$root in `$roots) {
        if (Test-Path -LiteralPath `$root) {
            `$lb = (Get-ItemProperty -LiteralPath `$root -Name LoadBehavior -ErrorAction SilentlyContinue).LoadBehavior
            if (`$lb -ne 3) {
                Set-ItemProperty -LiteralPath `$root -Name LoadBehavior -Value 3 -ErrorAction SilentlyContinue
                Add-Content -Path `$log -Value "`$(Get-Date -Format 'yyyy-MM-dd HH:mm') Healed `$progId LoadBehavior from `$lb to 3"
            }
        }
    }
    `$dis = Join-Path `$resil 'DisabledItems'
    if (Test-Path -LiteralPath `$dis) {
        Remove-Item -LiteralPath `$dis -Recurse -Force -ErrorAction SilentlyContinue
        Add-Content -Path `$log -Value "`$(Get-Date -Format 'yyyy-MM-dd HH:mm') Cleared DisabledItems"
    }
}
"@
            $encodedCmd = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($healScript)
            )
            # The task runs AS the target user, which is why the HKCU: paths in
            # the generated heal script above are correct as written and must
            # NOT be redirected: inside that task HKCU: already resolves to the
            # right hive. The principal is what makes that true, so it comes
            # from the resolved context rather than from this process.
            # RunLevel Limited, not Highest. The heal script only writes the
            # user's own HKCU LoadBehavior, which needs no elevation. Highest
            # bought nothing (an end user who is not a local admin cannot elevate
            # anyway) while making the task a high-value target if its command
            # line were ever influenced again.
            $taskPrincipal = New-ScheduledTaskPrincipal -UserId $ctx.UserName -LogonType Interactive -RunLevel Limited

            $taskAction  = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
                -Argument ('-NonInteractive -WindowStyle Hidden -EncodedCommand {0}' -f $encodedCmd)
            $taskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '8:00AM'
            $taskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
                -StartWhenAvailable

            if ($safeProgIds.Count -eq 0) {
                # Every candidate failed the ProgID whitelist. Registering a task
                # with an empty list would be pointless; more importantly, that
                # combination is itself a signal worth surfacing.
                Write-ToolOutput 'No add-in passed the ProgID validation, so no self-heal task was created.' -Level Warning
            } else {
                if ($taskExists) {
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                }
                Register-ScheduledTask -TaskName $taskName `
                    -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings `
                    -Principal $taskPrincipal -Force -ErrorAction SilentlyContinue | Out-Null

                $verifyTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                if ($verifyTask) {
                    $changes.Add('Self-heal task created (weekly Monday 8AM)')
                } else {
                    Write-ToolOutput 'Could not create self-heal task (check task scheduler permissions)' -Level Warning
                }
            }
        }

        $status = if ($changes.Count -gt 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status `
            -Summary ('{0} change(s): {1}' -f $changes.Count, ($changes -join '; '))
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
