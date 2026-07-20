function Get-NitroProStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'nitro-pro-status'

        # --- Install detection ---
        $regPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $installed = $null
        foreach ($path in $regPaths) {
            $installed = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'Nitro (PDF|Pro)' } |
                Select-Object -First 1
            if ($installed) { break }
        }
        if (-not $installed) {
            Write-ToolOutput 'Nitro PDF Pro is not installed (no matching uninstall registry entry found)' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'Nitro PDF Pro not installed'
            return
        }
        Write-ToolOutput ('Installed: {0} (version {1})' -f $installed.DisplayName, $installed.DisplayVersion) -Level Info

        # --- License / activation state ---
        $nitroBases = @(
            'HKLM:\SOFTWARE\Nitro\PDF Pro',
            'HKLM:\SOFTWARE\WOW6432Node\Nitro\PDF Pro'
        )
        $licenseFound  = $false
        $licenseStatus = 'Unknown'
        foreach ($nitroBase in $nitroBases) {
            if ($licenseFound) { break }
            if (-not (Test-Path -LiteralPath $nitroBase)) { continue }
            $verKeys = @(Get-ChildItem -LiteralPath $nitroBase -ErrorAction SilentlyContinue)
            foreach ($verKey in $verKeys) {
                $nlsPath = '{0}\{1}\settings\NLS' -f $nitroBase, $verKey.PSChildName
                if (Test-Path -LiteralPath $nlsPath) {
                    $nls = Get-ItemProperty -LiteralPath $nlsPath -ErrorAction SilentlyContinue
                    if ($nls) {
                        $licenseFound = $true
                        if ($nls.PSObject.Properties.Name -contains 'ActivationState') {
                            $licenseStatus = $nls.ActivationState
                        } elseif ($nls.PSObject.Properties.Name -contains 'IsActivated') {
                            $licenseStatus = if ($nls.IsActivated -eq 1) { 'Activated' } else { 'Trial' }
                        }
                    }
                    break
                }
            }
        }
        $licenseLevel = if ($licenseFound -and $licenseStatus -match 'Activ') { 'Info' } else { 'Warning' }
        $licenseText  = if ($licenseFound) { $licenseStatus } else { 'License registry key not found (unable to confirm activation state)' }
        Write-ToolOutput ('License state: {0}' -f $licenseText) -Level $licenseLevel

        # --- Process check ---
        $process = Get-Process -Name 'NitroPDF*' -ErrorAction SilentlyContinue | Select-Object -First 1
        $processLevel = if ($process) { 'Info' } else { 'Detail' }
        $processText  = if ($process) { 'Running ({0})' -f $process.ProcessName } else { 'Not currently running' }
        Write-ToolOutput ('Process: {0}' -f $processText) -Level $processLevel

        # --- Default PDF handler ---
        $userChoiceKey  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice'
        $defaultHandler = 'Unknown'
        if (Test-Path -LiteralPath $userChoiceKey) {
            $choice = Get-ItemProperty -LiteralPath $userChoiceKey -ErrorAction SilentlyContinue
            if ($choice -and $choice.PSObject.Properties.Name -contains 'ProgId') {
                $defaultHandler = $choice.ProgId
            }
        }
        $isNitroDefault = $defaultHandler -match 'Nitro'
        $handlerLevel   = if ($isNitroDefault) { 'Info' } else { 'Warning' }
        Write-ToolOutput ('Default PDF handler: {0}' -f $defaultHandler) -Level $handlerLevel

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if (-not ($licenseFound -and $licenseStatus -match 'Activ')) { $issues.Add('license not confirmed activated') }
        if (-not $isNitroDefault) { $issues.Add('Nitro is not the default PDF handler') }

        $verdict = if ($issues.Count -eq 0) {
            'Installed, activated, set as default PDF handler'
        } else {
            'Issues: ' + ($issues -join '; ')
        }
        Write-ToolOutput ('Verdict: {0}' -f $verdict) -Level Info

        $status = if ($issues.Count -eq 0) { 'Success' } else { 'Warning' }
        Complete-ToolRun $run -Status $status -Summary $verdict
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
