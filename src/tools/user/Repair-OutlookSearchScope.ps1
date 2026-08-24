function Repair-OutlookSearchScope {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-search-all'

        # Profile layout and search scope are per-user; the WSearch keys below
        # are HKLM and stay machine-wide.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # This gate must sit BEFORE the profile lookup, not next to the action.
        # Every reported value here - profile name, data files, search scope -
        # comes from the user hive, so an unresolved context would silently
        # describe (and then fix) the technician's own Outlook instead. The
        # "no profile found" early return below would otherwise hide that on any
        # machine where the technician has no profile.
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot read or fix Outlook search scope - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $olKey     = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Office\16.0\Outlook'
        $searchKey = Join-Path $olKey 'Search'
        $profRoot  = Join-Path $olKey 'Profiles'

        # --- Active profile ---
        $activeProfile = (Get-ItemProperty -LiteralPath $olKey -Name 'DefaultProfile' `
                          -ErrorAction SilentlyContinue).DefaultProfile
        if ([string]::IsNullOrWhiteSpace($activeProfile)) {
            $profileDirs = @(Get-ChildItem -LiteralPath $profRoot -ErrorAction SilentlyContinue)
            if ($profileDirs.Count -gt 0) { $activeProfile = $profileDirs[0].PSChildName }
        }
        if ([string]::IsNullOrWhiteSpace($activeProfile)) {
            Complete-ToolRun $run -Status Warning `
                -Summary 'No Outlook profile found -- Outlook may not be installed or configured'
            return
        }
        Write-ToolOutput ('Outlook profile: {0}' -f $activeProfile) -Level Info

        # --- Enumerate data files from profile registry ---
        # The 001f6610 binary value holds the Unicode path to a data file
        $dataFiles = New-Object System.Collections.Generic.List[object]
        $profPath  = Join-Path $profRoot $activeProfile
        if (Test-Path -LiteralPath $profPath) {
            Get-ChildItem -LiteralPath $profPath -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if ($props -and ($props.PSObject.Properties.Name -contains '001f6610')) {
                    $raw = $props.'001f6610'
                    if ($raw -is [byte[]]) {
                        $filePath = [System.Text.Encoding]::Unicode.GetString($raw).TrimEnd([char]0)
                        if ($filePath -match '\.(ost|pst)$' -and
                            -not [string]::IsNullOrWhiteSpace($filePath)) {
                            $exists  = Test-Path -LiteralPath $filePath -ErrorAction SilentlyContinue
                            $sizeMB  = $null
                            if ($exists) {
                                $item = Get-Item -LiteralPath $filePath -ErrorAction SilentlyContinue
                                if ($item) { $sizeMB = [math]::Round($item.Length / 1MB, 1) }
                            }
                            $dataFiles.Add([PSCustomObject]@{
                                Path      = $filePath
                                Extension = [IO.Path]::GetExtension($filePath).ToLower()
                                SizeMB    = $sizeMB
                                Exists    = $exists
                            })
                        }
                    }
                }
            }
        }

        # Deduplicate by path
        $seen   = @{}
        $unique = New-Object System.Collections.Generic.List[object]
        foreach ($f in $dataFiles) {
            $key = $f.Path.ToLower()
            if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $unique.Add($f) }
        }
        $dataFiles = $unique

        Write-ToolOutput ('Data files in profile: {0}' -f $dataFiles.Count) -Level Info
        $largeFiles   = New-Object System.Collections.Generic.List[object]
        $missingFiles = New-Object System.Collections.Generic.List[object]
        foreach ($f in $dataFiles) {
            $name = [IO.Path]::GetFileName($f.Path)
            if (-not $f.Exists) {
                Write-ToolOutput ('  {0} -- NOT FOUND on disk (orphaned)' -f $name) -Level Warning
                $missingFiles.Add($f)
            } elseif ($f.SizeMB -ne $null -and $f.SizeMB -gt 5000) {
                Write-ToolOutput ('  {0} ({1}MB) -- LARGE (may hit WSearch size limit)' -f $name, $f.SizeMB) -Level Warning
                $largeFiles.Add($f)
            } else {
                $sizeLabel = if ($f.SizeMB -ne $null) { '{0}MB' -f $f.SizeMB } else { '(size unknown)' }
                Write-ToolOutput ('  {0} ({1})' -f $name, $sizeLabel) -Level Detail
            }
        }

        # --- SearchDefaultScope ---
        $currentScope = (Get-ItemProperty -LiteralPath $searchKey -Name 'SearchDefaultScope' `
                         -ErrorAction SilentlyContinue).SearchDefaultScope
        $scopeText = switch ([string]$currentScope) {
            '1'     { 'All Mailboxes [OK]' }
            '0'     { 'Current Mailbox only [should be All Mailboxes]' }
            default { '(not set - defaults to Current Mailbox)' }
        }
        $scopeLevel = if ($currentScope -eq 1) { 'Info' } else { 'Warning' }
        Write-ToolOutput ('Search scope: {0}' -f $scopeText) -Level $scopeLevel

        # --- Windows Search service ---
        $ws    = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
        $wsLvl = if (-not $ws -or $ws.Status -ne 'Running') { 'Warning' } else { 'Info' }
        $wsTxt = if ($ws) { '{0} (StartType: {1})' -f $ws.Status, $ws.StartType } else { 'Not found' }
        Write-ToolOutput ('Windows Search: {0}' -f $wsTxt) -Level $wsLvl

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Outlook search scope fix' `
            -Choices @('None','FixScope') -Default 'None' -Silent:$Silent

        if ($action -eq 'None') {
            Complete-ToolRun $run -Status Success `
                -Summary ('{0} file(s) found; scope={1}; no action taken' -f $dataFiles.Count, $currentScope)
            return
        }

        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot fix the search scope - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $changes = New-Object System.Collections.Generic.List[string]

        # Set SearchDefaultScope = 1 (All Mailboxes)
        if ($currentScope -ne 1) {
            if (-not (Test-Path -LiteralPath $searchKey)) {
                New-Item -LiteralPath $searchKey -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Set-ItemProperty -LiteralPath $searchKey -Name 'SearchDefaultScope' `
                -Value 1 -Type DWord -ErrorAction SilentlyContinue
            $verify = (Get-ItemProperty -LiteralPath $searchKey -Name 'SearchDefaultScope' `
                       -ErrorAction SilentlyContinue).SearchDefaultScope
            if ($verify -eq 1) {
                $changes.Add('SearchDefaultScope set to All Mailboxes')
            } else {
                Write-ToolOutput 'Could not write SearchDefaultScope=1 (may require Outlook restart)' -Level Warning
            }
        }

        # Raise WSearch MaxObjectSize for large files
        # Prevents WSearch from skipping .ost files over 5 GB by default
        if ($largeFiles.Count -gt 0) {
            $wdsKey = 'HKLM:\SOFTWARE\Microsoft\Windows Search'
            Set-ItemProperty -LiteralPath $wdsKey -Name 'MaxObjectSize' `
                -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $verifyMax = (Get-ItemProperty -LiteralPath $wdsKey -Name 'MaxObjectSize' `
                          -ErrorAction SilentlyContinue).MaxObjectSize
            if ($verifyMax -eq 0) {
                $changes.Add(('{0} large file(s) -- WSearch MaxObjectSize limit raised' -f $largeFiles.Count))
            } else {
                Write-ToolOutput ('Large file(s) found but MaxObjectSize could not be set (elevation required for HKLM write)') -Level Warning
            }
        }

        # Start WSearch if stopped
        if ($ws -and $ws.Status -ne 'Running') {
            Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $ws2 = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue
            if ($ws2 -and $ws2.Status -eq 'Running') {
                $changes.Add('WSearch service started')
            }
        }

        # Trigger Outlook to re-register its data files with WSearch
        # The Catalog property under HKCU\...\Search triggers Outlook to re-register on next start
        Remove-ItemProperty -LiteralPath $searchKey -Name 'Catalog' -ErrorAction SilentlyContinue
        $changes.Add('Outlook index registration cleared (re-registers on next Outlook launch)')

        Complete-ToolRun $run -Status Success `
            -Summary ('{0} change(s): {1}. Restart Outlook for full effect.' -f `
                $changes.Count, ($changes -join '; '))
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
