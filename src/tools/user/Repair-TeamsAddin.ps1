function Repair-TeamsAddin {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-addin-repair'

        # The add-in DLL, its COM registration, and the Outlook resiliency keys
        # are all per-user. Resolve the target account before reading any of them.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # --- Report ---
        # AppX registration is per-user. -User queries the target account rather
        # than the technician's, but needs elevation, so degrade to an explicit
        # "unknown" instead of silently reporting the wrong account's state.
        $pkg      = $null
        $pkgKnown = $true
        if ($ctx.IsRedirected) {
            try {
                $pkg = Get-AppxPackage -Name 'MSTeams' -User $ctx.Sid -ErrorAction Stop
            } catch {
                $pkgKnown = $false
            }
        } else {
            $pkg = Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue
        }
        if (-not $pkgKnown) {
            Write-ToolOutput ('New Teams (MSTeams) registration for {0} could not be read (needs elevation).' -f $ctx.DisplayName) -Level Warning
        } elseif ($pkg) {
            Write-ToolOutput ('New Teams (MSTeams) installed: v{0}' -f $pkg.Version) -Level Info
        } else {
            Write-ToolOutput ('New Teams (MSTeams) not registered for {0}.' -f $ctx.DisplayName) -Level Warning
        }

        $addinRoot = $null
        if ($ctx.Resolved) { $addinRoot = Join-Path $ctx.LocalAppData 'Microsoft\TeamsMeetingAddin' }
        $dll = $null
        if ($addinRoot -and (Test-Path -LiteralPath $addinRoot)) {
            $dll = Get-ChildItem -LiteralPath $addinRoot -Filter 'Microsoft.Teams.AddinLoader.dll' -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if ($dll) {
            Write-ToolOutput ('Add-in DLL: {0}' -f $dll.FullName) -Level Detail
        } else {
            Write-ToolOutput 'Teams Meeting Add-in DLL not found.' -Level Warning
        }

        $addinKey = Get-UserHivePath -Context $ctx `
            -SubPath 'Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect'
        $lb = (Get-ItemProperty -LiteralPath $addinKey -Name 'LoadBehavior' -ErrorAction SilentlyContinue).LoadBehavior
        if ($null -ne $lb) {
            Write-ToolOutput ('Outlook add-in LoadBehavior: {0}' -f $lb) -Level Detail
        } else {
            Write-ToolOutput 'Outlook add-in LoadBehavior: (not set)' -Level Detail
        }

        # Office 2016 / 2019 / 2021 / M365 all use the 16.0 hive
        $disabledKey = Get-UserHivePath -Context $ctx `
            -SubPath 'Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems'
        Write-ToolOutput ('Outlook DisabledItems key present: {0}' -f (Test-Path -LiteralPath $disabledKey)) -Level Detail

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Teams add-in action' -Choices @('None','RepairAddin') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RepairAddin' {
                Write-ToolOutput 'WARNING: this CLOSES Outlook (save any open drafts first) and restarts Teams.' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Close Outlook and repair the Teams Meeting add-in?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RepairAddin cancelled'
                } else {
                    if (-not $ctx.Resolved) {
                        Complete-ToolRun $run -Status Failed `
                            -Summary ('Cannot repair the add-in - {0}. Nothing was changed.' -f $ctx.Reason)
                        return
                    }
                    foreach ($p in @('OUTLOOK','ms-teams','MSTeams','Teams')) {
                        Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Seconds 3
                    if (-not $dll) {
                        Complete-ToolRun $run -Status Warning -Summary 'Add-in DLL not found; reinstall New Teams then retry'
                    } else {
                        # regsvr32 self-registers the add-in into the CALLING
                        # account's HKCU\Software\Classes. Under a redirected
                        # session that would register the add-in for the
                        # technician and leave the user's COM registration
                        # untouched, so the step is skipped, not misapplied.
                        $regOk      = $true
                        $regSkipped = $false
                        if ($ctx.IsRedirected) {
                            Write-ToolOutput ('COM re-registration skipped: regsvr32 would register the add-in for {0}, not {1}.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Warning
                            $regOk      = $false
                            $regSkipped = $true
                        } else {
                            $regArgs = '/s "{0}"' -f $dll.FullName
                            $rc = Start-Process -FilePath 'regsvr32.exe' -ArgumentList $regArgs -Wait -PassThru -ErrorAction SilentlyContinue
                            if ($null -eq $rc) {
                                Write-ToolOutput 'regsvr32 did not launch (unexpected).' -Level Warning
                                $regOk = $false
                            } elseif ($rc.ExitCode -ne 0) {
                                Write-ToolOutput ('regsvr32 exit {0} (often a 32/64-bit mismatch; continuing).' -f $rc.ExitCode) -Level Warning
                                $regOk = $false
                            } else {
                                Write-ToolOutput 'COM add-in re-registered.' -Level Success
                            }
                        }
                        if (-not (Test-Path -LiteralPath $addinKey)) { New-Item -LiteralPath $addinKey -Force | Out-Null }
                        Set-ItemProperty -LiteralPath $addinKey -Name 'LoadBehavior' -Value 3 -Type DWord -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath $disabledKey) {
                            Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue
                            Write-ToolOutput 'Cleared Outlook DisabledItems.' -Level Detail
                        }
                        $cacheDir = Join-Path $addinRoot 'Cache'
                        if (Test-Path -LiteralPath $cacheDir) {
                            # Containment-gated: see Remove-UserPathContent.
                            [void](Remove-UserPathContent -Context $ctx -Path $cacheDir)
                        }
                        if (-not $ctx.IsRedirected) {
                            Start-Process 'ms-teams:' -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 2
                        } else {
                            Write-ToolOutput 'Ask the user to reopen Teams and Outlook - neither can be relaunched as them from an elevated session.' -Level Warning
                        }
                        if ($regOk) {
                            Complete-ToolRun $run -Status Success -Summary ('Teams Meeting add-in re-registered for {0}; relaunch Outlook to see the button' -f $ctx.DisplayName)
                        } elseif ($regSkipped) {
                            Complete-ToolRun $run -Status Warning -Summary ('LoadBehavior/DisabledItems repaired for {0}; COM re-registration skipped (session-bound) - run this from the user session if the button is still missing' -f $ctx.DisplayName)
                        } else {
                            Complete-ToolRun $run -Status Warning -Summary ('LoadBehavior/DisabledItems repaired for {0} but COM re-registration failed; relaunch Outlook and verify the add-in' -f $ctx.DisplayName)
                        }
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Teams add-in state reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
