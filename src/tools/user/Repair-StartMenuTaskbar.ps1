function Repair-StartMenuTaskbar {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'start-menu-taskbar'

        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        # --- Report ---
        $explorer = @(Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)
        Write-ToolOutput ('explorer.exe running: {0}' -f ($explorer.Count -gt 0)) -Level Info
        $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($os) { Write-ToolOutput ('OS: {0}' -f $os) -Level Detail }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Start Menu / Taskbar action' `
            -Choices @('None','RestartExplorer','ResetStartLayout','ReRegisterStartMenu') -Default 'None' -Silent:$Silent

        # All three actions restart explorer, and ReRegisterStartMenu also calls
        # Add-AppxPackage -Register, which registers for the CALLING account.
        # From an elevated session the kill hits the user's shell while the
        # relaunch and the AppX registration land on the technician - so the
        # user can end up with no desktop and an unchanged Start Menu.
        if ($action -ne 'None' -and $ctx.IsRedirected) {
            Write-ToolOutput ('Start Menu / Explorer actions must run in the user session: the restart and AppX re-registration would target {0}, not {1}.' -f $ctx.ProcessName, $ctx.DisplayName) -Level Error
            Complete-ToolRun $run -Status Failed `
                -Summary ('Start Menu action refused - would target {0}, not {1}. Nothing was changed.' -f $ctx.ProcessName, $ctx.DisplayName)
            return
        }
        if ($action -ne 'None' -and -not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot repair the Start Menu / Taskbar - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        switch ($action) {

            'RestartExplorer' {
                Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Process "$env:SystemRoot\explorer.exe"
                Start-Sleep -Seconds 2
                Write-ToolOutput 'Explorer restarted.' -Level Success
                Complete-ToolRun $run -Status Success -Summary 'Explorer restarted'
            }

            'ResetStartLayout' {
                $confirm = Read-ToolChoice -Prompt 'Reset the Start Menu layout (current layout will be cleared)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ResetStartLayout cancelled'
                } else {
                    $shell = Join-Path $ctx.LocalAppData 'Microsoft\Windows\Shell'
                    $backup = Join-Path $env:TEMP ('StartMenu_Backup_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                    $backupTaken = $false
                    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    if (Test-Path -LiteralPath $shell) {
                        Copy-Item -LiteralPath $shell -Destination $backup -Recurse -ErrorAction SilentlyContinue
                        if (Test-Path -LiteralPath $backup) {
                            $backupTaken = $true
                            Write-ToolOutput ('Backed up layout to {0}' -f $backup) -Level Detail
                        }
                    }
                    $caches = Join-Path $ctx.LocalAppData 'Microsoft\Windows\Caches'
                    if (Test-Path -LiteralPath $caches) {
                        # Containment-gated: see Remove-UserPathContent.
                        [void](Remove-UserPathContent -Context $ctx -Path $caches)
                    }
                    $layoutXml = Join-Path $shell 'LayoutModification.xml'
                    if (Test-Path -LiteralPath $layoutXml) { Remove-Item -LiteralPath $layoutXml -Force -ErrorAction SilentlyContinue }
                    Start-Process "$env:SystemRoot\explorer.exe"
                    Start-Sleep -Seconds 2
                    Write-ToolOutput 'Start layout reset; explorer restarted.' -Level Success
                    if ($backupTaken) {
                        Complete-ToolRun $run -Status Success -Summary ('Start layout reset (backup: {0})' -f $backup)
                    } else {
                        Complete-ToolRun $run -Status Success -Summary 'Start layout reset (no prior layout to back up)'
                    }
                }
            }

            'ReRegisterStartMenu' {
                $confirm = Read-ToolChoice -Prompt 'Re-register the Start Menu app for the current user (can take a minute)?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'ReRegisterStartMenu cancelled'
                } else {
                    Write-ToolOutput 'Re-registering StartMenuExperienceHost...' -Level Info
                    $ok = 0
                    $fail = 0
                    Get-AppxPackage -Name 'Microsoft.Windows.StartMenuExperienceHost' -ErrorAction SilentlyContinue | ForEach-Object {
                        $manifest = Join-Path $_.InstallLocation 'AppXManifest.xml'
                        try {
                            Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                            $ok++
                        } catch {
                            Write-ToolOutput $_.Exception.Message -Level Warning
                            $fail++
                        }
                    }
                    if (($ok + $fail) -eq 0) {
                        Complete-ToolRun $run -Status Warning -Summary 'StartMenuExperienceHost package not found; nothing to re-register'
                    } else {
                        Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        Start-Process "$env:SystemRoot\explorer.exe"
                        Start-Sleep -Seconds 2
                        if ($fail -gt 0) {
                            Complete-ToolRun $run -Status Warning -Summary ('Start Menu re-register: {0} ok, {1} failed' -f $ok, $fail)
                        } else {
                            Complete-ToolRun $run -Status Success -Summary ('Start Menu re-registered ({0} package)' -f $ok)
                        }
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Start Menu / Taskbar reported; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
