function Get-GlobalProtectStatus {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'globalprotect-status'

        # --- Install detection ---
        $regPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $installed = $null
        foreach ($path in $regPaths) {
            $installed = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'GlobalProtect' } |
                Select-Object -First 1
            if ($installed) { break }
        }
        if (-not $installed) {
            Write-ToolOutput 'GlobalProtect is not installed (no matching uninstall registry entry found)' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'GlobalProtect not installed'
            return
        }
        Write-ToolOutput ('Installed: {0} (version {1})' -f $installed.DisplayName, $installed.DisplayVersion) -Level Info

        # --- Service status ---
        $service = Get-Service -Name 'PanGPS' -ErrorAction SilentlyContinue
        $serviceLevel = 'Warning'
        $serviceText  = 'PanGPS service not found'
        if ($service) {
            $serviceText  = 'PanGPS service: {0}' -f $service.Status
            $serviceLevel = if ($service.Status -eq 'Running') { 'Info' } else { 'Warning' }
        }
        Write-ToolOutput $serviceText -Level $serviceLevel

        # --- Process check ---
        $process = Get-Process -Name 'PanGPA' -ErrorAction SilentlyContinue
        $processLevel = if ($process) { 'Info' } else { 'Warning' }
        $processText  = if ($process) { 'Running' } else { 'Not running' }
        Write-ToolOutput ('PanGPA process: {0}' -f $processText) -Level $processLevel

        # --- Active VPN adapter ---
        $vpnAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.InterfaceDescription -match 'GlobalProtect|Palo Alto' -and $_.Status -eq 'Up'
        } | Select-Object -First 1
        $connected = $null -ne $vpnAdapter
        $adapterLevel = if ($connected) { 'Info' } else { 'Warning' }
        $adapterText  = if ($connected) { 'Up ({0})' -f $vpnAdapter.Name } else { 'Not connected' }
        Write-ToolOutput ('VPN tunnel adapter: {0}' -f $adapterText) -Level $adapterLevel

        # --- Portal config ---
        $settingsKey = 'HKLM:\SOFTWARE\Palo Alto Networks\GlobalProtect\Settings'
        $portal = $null
        if (Test-Path -LiteralPath $settingsKey) {
            $settings = Get-ItemProperty -LiteralPath $settingsKey -ErrorAction SilentlyContinue
            if ($settings -and $settings.PSObject.Properties.Name -contains 'Portal') {
                $portal = $settings.Portal
            }
        }
        $portalLevel = if ($portal) { 'Info' } else { 'Warning' }
        $portalText  = if ($portal) { $portal } else { 'Not found' }
        Write-ToolOutput ('Configured portal: {0}' -f $portalText) -Level $portalLevel

        # --- Log scan ---
        $logCandidates = @(
            'C:\Program Files\Palo Alto Networks\GlobalProtect\PanGPS.log',
            (Join-Path $env:LOCALAPPDATA 'Palo Alto Networks\GlobalProtect\PanGPA.log')
        )
        $logErrors = New-Object System.Collections.Generic.List[string]
        foreach ($logPath in $logCandidates) {
            if (Test-Path -LiteralPath $logPath) {
                try {
                    $tail = Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Last 300
                    $hits = @($tail | Where-Object { $_ -match 'fail|error|unreachable|denied|timeout' })
                    foreach ($h in ($hits | Select-Object -Last 5)) {
                        $logErrors.Add($h.Trim())
                    }
                } catch { }
            }
        }
        if ($logErrors.Count -gt 0) {
            Write-ToolOutput ('Recent log errors ({0}):' -f $logErrors.Count) -Level Warning
            foreach ($e in $logErrors) { Write-ToolOutput ('  {0}' -f $e) -Level Detail }
        } else {
            Write-ToolOutput 'No recent log errors found' -Level Detail
        }

        # --- Verdict ---
        $issues = New-Object System.Collections.Generic.List[string]
        if ($serviceLevel -eq 'Warning') { $issues.Add('PanGPS service not running') }
        if (-not $connected)             { $issues.Add('VPN tunnel not connected') }
        if (-not $portal)                { $issues.Add('no portal configured') }
        if ($logErrors.Count -gt 0)      { $issues.Add('{0} recent log error(s)' -f $logErrors.Count) }

        $verdict = if ($issues.Count -eq 0) {
            'Connected, service healthy, no recent errors'
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
