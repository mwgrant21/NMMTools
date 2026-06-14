function Repair-OutlookAddins {
    [CmdletBinding()]
    param([switch]$Silent)

    # Scan Outlook add-in keys (HKCU + HKLM) read-only.
    function Get-OutlookAddin {
        $roots = @(
            'HKCU:\Software\Microsoft\Office\16.0\Outlook\Addins',
            'HKLM:\Software\Microsoft\Office\16.0\Outlook\Addins',
            'HKLM:\Software\WOW6432Node\Microsoft\Office\16.0\Outlook\Addins'
        )
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                $lb = $null
                if ($props -and ($props.PSObject.Properties.Name -contains 'LoadBehavior')) { $lb = [int]$props.LoadBehavior }
                $fn = $k.PSChildName
                if ($props -and $props.FriendlyName) { $fn = $props.FriendlyName }
                $list.Add([pscustomobject]@{
                    Name         = $k.PSChildName
                    FriendlyName = $fn
                    LoadBehavior = $lb
                    Hive         = ($root -split ':')[0]
                    PSPath       = $k.PSPath
                })
            }
        }
        return $list
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-addin-repair'
        $resiliencyRoot = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
        $disabledKey    = Join-Path $resiliencyRoot 'DisabledItems'
        $crashKey       = Join-Path $resiliencyRoot 'CrashingAddinList'
        $doNotDisable   = Join-Path $resiliencyRoot 'DoNotDisableAddinList'

        # --- Report ---
        $addins = @(Get-OutlookAddin)
        Write-ToolOutput ('Outlook add-ins found: {0}' -f $addins.Count) -Level Info
        foreach ($a in $addins) {
            $lbText = 'n/a'
            if ($null -ne $a.LoadBehavior) { $lbText = [string]$a.LoadBehavior }
            Write-ToolOutput ('  [{0}] {1}  LoadBehavior={2}' -f $a.Hive, $a.FriendlyName, $lbText) -Level Detail
        }
        $disabledCount = 0
        if (Test-Path -LiteralPath $disabledKey) {
            $dp = (Get-ItemProperty -LiteralPath $disabledKey -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
            $disabledCount = @($dp).Count
        }
        $crashCount = 0
        if (Test-Path -LiteralPath $crashKey) {
            $cp = (Get-ItemProperty -LiteralPath $crashKey -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
            $crashCount = @($cp).Count
        }
        Write-ToolOutput ('Resiliency DisabledItems: {0}; CrashingAddinList: {1}' -f $disabledCount, $crashCount) -Level Detail
        $onbase = @($addins | Where-Object { $_.Name -match 'OnBase|Hyland' -or $_.FriendlyName -match 'OnBase|Hyland' })
        if ($onbase.Count -gt 0) { Write-ToolOutput ('OnBase/Hyland add-in detected: {0}' -f $onbase[0].FriendlyName) -Level Info }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook add-in repair' -Choices @('None','ReEnable') -Default 'None' -Silent:$Silent
        if ($action -ne 'ReEnable') {
            Complete-ToolRun $run -Status Success -Summary ('{0} add-in(s) reported; no action taken' -f $addins.Count)
            return
        }

        if (Test-Path -LiteralPath $disabledKey) { Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $crashKey)    { Remove-Item -LiteralPath $crashKey -Recurse -Force -ErrorAction SilentlyContinue }
        if (-not (Test-Path -LiteralPath $doNotDisable)) { New-Item -Path $doNotDisable -Force -ErrorAction SilentlyContinue | Out-Null }

        $reenabled = New-Object System.Collections.Generic.List[string]
        foreach ($a in $addins) {
            if ($a.Hive -eq 'HKCU' -and $a.LoadBehavior -eq 0) {
                Set-ItemProperty -LiteralPath $a.PSPath -Name 'LoadBehavior' -Value 3 -ErrorAction SilentlyContinue
                $reenabled.Add($a.FriendlyName)
            }
            $existing = Get-ItemProperty -LiteralPath $doNotDisable -Name $a.Name -ErrorAction SilentlyContinue
            if ($null -eq $existing) {
                New-ItemProperty -LiteralPath $doNotDisable -Name $a.Name -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }

        Complete-ToolRun $run -Status Success -Summary ('Cleared {0} disabled + {1} crashing entr(ies); re-enabled {2} add-in(s)' -f $disabledCount, $crashCount, $reenabled.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
