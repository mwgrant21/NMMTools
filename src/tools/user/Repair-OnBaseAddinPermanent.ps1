function Repair-OnBaseAddinPermanent {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'onbase-addin-fix'

        $addinRoots = @(
            'HKCU:\Software\Microsoft\Office\16.0\Outlook\Addins',
            'HKLM:\Software\Microsoft\Office\16.0\Outlook\Addins',
            'HKLM:\Software\WOW6432Node\Microsoft\Office\16.0\Outlook\Addins'
        )
        $resilRoot     = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
        $disabledKey   = Join-Path $resilRoot 'DisabledItems'
        $crashKey      = Join-Path $resilRoot 'CrashedAddinList'
        $doNotDisKey   = Join-Path $resilRoot 'DoNotDisableAddinList'
        $addinTimesKey = Join-Path $resilRoot 'AddinLoadTimes'
        $hklmBase      = 'HKLM:\Software\Microsoft\Office\16.0\Outlook\Addins'

        # --- Find OnBase/Hyland add-in across all hives ---
        $onbaseAddins = New-Object System.Collections.Generic.List[object]
        foreach ($root in $addinRoots) {
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
                        Hive         = if ($root -match '^HKLM') { 'HKLM' } else { 'HKCU' }
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
            $disabledCount, $crashCount) -Level (if ($disabledCount -gt 0 -or $crashCount -gt 0) { 'Warning' } else { 'Info' })

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
        Write-ToolOutput ('DoNotDisableAddinList: {0}' -f (if ($alreadyPinned) { 'Already pinned' } else { 'Not set' })) `
            -Level (if ($alreadyPinned) { 'Info' } else { 'Warning' })

        # --- Self-heal task check ---
        $taskName  = 'NMMTools-OnBaseAddinCheck'
        $taskExists = $false
        try {
            $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            $taskExists = $null -ne $existing
        } catch { }
        Write-ToolOutput ('Self-heal task ({0}): {1}' -f $taskName, (if ($taskExists) { 'Exists' } else { 'Not created' })) `
            -Level (if ($taskExists) { 'Info' } else { 'Warning' })

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'OnBase add-in permanent fix' `
            -Choices @('None','Fix','Harden') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success `
                -Summary ('{0} OnBase add-in(s) found; LB={1}; disabled={2}; crashed={3}; no action taken' -f `
                    $onbaseAddins.Count, $onbaseAddins[0].LoadBehavior, $disabledCount, $crashCount)
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

            # HKLM registration fallback (requires admin -- tool is RequiresAdmin=$true)
            foreach ($a in ($onbaseAddins | Where-Object { $_.Hive -eq 'HKCU' })) {
                $hklmPath = Join-Path $hklmBase $a.ProgId
                if (-not (Test-Path -LiteralPath $hklmPath)) {
                    try {
                        New-Item -LiteralPath $hklmPath -Force -ErrorAction Stop | Out-Null
                        $srcProps = Get-ItemProperty -LiteralPath $a.PSPath -ErrorAction SilentlyContinue
                        if ($srcProps) {
                            foreach ($propName in @('FriendlyName', 'Description', 'Manifest')) {
                                $val = $srcProps.PSObject.Properties[$propName]
                                if ($val) {
                                    New-ItemProperty -LiteralPath $hklmPath -Name $propName `
                                        -Value $val.Value -PropertyType String -Force `
                                        -ErrorAction SilentlyContinue | Out-Null
                                }
                            }
                            New-ItemProperty -LiteralPath $hklmPath -Name 'LoadBehavior' `
                                -Value 3 -PropertyType DWord -Force `
                                -ErrorAction SilentlyContinue | Out-Null
                        }
                        $changes.Add(('{0} added to HKLM (survives profile resets)' -f $a.ProgId))
                    } catch {
                        Write-ToolOutput ('HKLM registration for {0} failed: {1}' -f $a.ProgId, $_.Exception.Message) -Level Warning
                    }
                } else {
                    Write-ToolOutput ('{0} already registered in HKLM' -f $a.ProgId) -Level Detail
                }
            }

            # Self-heal scheduled task
            $progIds = ($onbaseAddins | ForEach-Object { "'{0}'" -f $_.ProgId }) -join ','
            $healScript = @"
`$resil = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
`$log   = (Join-Path `$env:ProgramData 'NMMTools\onbase-addin-heal.log')
`$addins = @($progIds)
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
            $taskAction  = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
                -Argument ('-NonInteractive -WindowStyle Hidden -EncodedCommand {0}' -f $encodedCmd)
            $taskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '8:00AM'
            $taskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
                -StartWhenAvailable

            if ($taskExists) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            }
            Register-ScheduledTask -TaskName $taskName `
                -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings `
                -RunLevel Highest -Force -ErrorAction SilentlyContinue | Out-Null

            $verifyTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($verifyTask) {
                $changes.Add('Self-heal task created (weekly Monday 8AM)')
            } else {
                Write-ToolOutput 'Could not create self-heal task (check task scheduler permissions)' -Level Warning
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
