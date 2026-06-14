function Repair-TeamsAddin {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'teams-addin-repair'

        # --- Report ---
        $pkg = Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue
        if ($pkg) {
            Write-ToolOutput ('New Teams (MSTeams) installed: v{0}' -f $pkg.Version) -Level Info
        } else {
            Write-ToolOutput 'New Teams (MSTeams) not registered for this user.' -Level Warning
        }

        $addinRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddin'
        $dll = $null
        if (Test-Path -LiteralPath $addinRoot) {
            $dll = Get-ChildItem -LiteralPath $addinRoot -Filter 'Microsoft.Teams.AddinLoader.dll' -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if ($dll) {
            Write-ToolOutput ('Add-in DLL: {0}' -f $dll.FullName) -Level Detail
        } else {
            Write-ToolOutput 'Teams Meeting Add-in DLL not found.' -Level Warning
        }

        $addinKey = 'HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect'
        $lb = (Get-ItemProperty -Path $addinKey -Name 'LoadBehavior' -ErrorAction SilentlyContinue).LoadBehavior
        if ($null -ne $lb) {
            Write-ToolOutput ('Outlook add-in LoadBehavior: {0}' -f $lb) -Level Detail
        } else {
            Write-ToolOutput 'Outlook add-in LoadBehavior: (not set)' -Level Detail
        }

        $disabledKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems'
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
                    foreach ($p in @('OUTLOOK','ms-teams','MSTeams','Teams')) {
                        Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Seconds 3
                    if (-not $dll) {
                        Complete-ToolRun $run -Status Warning -Summary 'Add-in DLL not found; reinstall New Teams then retry'
                    } else {
                        $regArgs = '/s "{0}"' -f $dll.FullName
                        $rc = Start-Process -FilePath 'regsvr32.exe' -ArgumentList $regArgs -Wait -PassThru -ErrorAction SilentlyContinue
                        if ($rc -and $rc.ExitCode -ne 0) {
                            Write-ToolOutput ('regsvr32 exit {0} (often a 32/64-bit mismatch; continuing).' -f $rc.ExitCode) -Level Warning
                        } else {
                            Write-ToolOutput 'COM add-in re-registered.' -Level Success
                        }
                        if (-not (Test-Path -LiteralPath $addinKey)) { New-Item -Path $addinKey -Force | Out-Null }
                        Set-ItemProperty -Path $addinKey -Name 'LoadBehavior' -Value 3 -Type DWord -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath $disabledKey) {
                            Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue
                            Write-ToolOutput 'Cleared Outlook DisabledItems.' -Level Detail
                        }
                        $cacheDir = Join-Path $addinRoot 'Cache'
                        if (Test-Path -LiteralPath $cacheDir) {
                            Get-ChildItem -LiteralPath $cacheDir -Force -ErrorAction SilentlyContinue |
                                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        Start-Process 'ms-teams:' -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        Complete-ToolRun $run -Status Success -Summary 'Teams Meeting add-in re-registered; relaunch Outlook to see the button'
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
