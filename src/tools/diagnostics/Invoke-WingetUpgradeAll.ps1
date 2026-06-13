function Invoke-WingetUpgradeAll {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'winget-upgrade'

        # Verify winget is available (requires App Installer from Microsoft Store)
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-ToolOutput 'winget not found. Requires Windows Package Manager (App Installer from Microsoft Store).' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'winget not available'
            return
        }

        # List available upgrades — Detail level; output can be voluminous
        Write-ToolOutput 'Checking for available upgrades...'
        $upgradeList = & winget upgrade 2>&1
        $upgradeList | ForEach-Object {
            $str = [string]$_
            if ($str.Trim()) { Write-ToolOutput $str -Level Detail }
        }

        # Confirm before proceeding — Default 'No': upgrading all apps can close/replace running software
        $choice = Read-ToolChoice -Prompt 'Upgrade all apps now?' -Default 'No' -Silent:$Silent
        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined upgrade'
            return
        }

        # Run upgrade — args verbatim from v8
        Write-ToolOutput 'Running winget upgrade --all --silent --accept-source-agreements --accept-package-agreements...'
        $upgradeOutput = & winget upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1
        $exitCode = $LASTEXITCODE
        $upgradeOutput | ForEach-Object {
            $str = [string]$_
            if ($str.Trim()) { Write-ToolOutput $str -Level Detail }
        }

        Write-ToolOutput ("winget upgrade exited with code: $exitCode") -Level Detail
        Complete-ToolRun $run -Status Success -Summary "winget upgrade --all completed (exit $exitCode)"
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
