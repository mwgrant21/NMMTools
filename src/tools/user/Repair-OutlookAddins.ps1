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
        $resiliencyRoot  = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
        $disabledKey     = Join-Path $resiliencyRoot 'DisabledItems'
        $crashKey        = Join-Path $resiliencyRoot 'CrashingAddinList'
        $doNotDisable    = Join-Path $resiliencyRoot 'DoNotDisableAddinList'
        $policyRoot      = 'HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Resiliency'
        $policyAddinList = Join-Path $policyRoot 'AddinList'

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

        # Durable-pin (policy) state.
        $promptSuppressed = $false
        if (Test-Path -LiteralPath $policyRoot) {
            $promptSuppressed = (Get-ItemProperty -LiteralPath $policyRoot -Name 'DisablePromptOnLoadTimeDisable' -ErrorAction SilentlyContinue).DisablePromptOnLoadTimeDisable -eq 1
        }
        $onbasePinned = $false
        if ($onbase.Count -gt 0 -and (Test-Path -LiteralPath $policyAddinList)) {
            $alProps = Get-ItemProperty -LiteralPath $policyAddinList -ErrorAction SilentlyContinue
            $onbasePinned = $true
            foreach ($o in $onbase) {
                $val = $null
                if ($alProps -and ($alProps.PSObject.Properties.Name -contains $o.Name)) { $val = [string]$alProps.$($o.Name) }
                if ($val -ne '1') { $onbasePinned = $false }
            }
        }
        if ($onbase.Count -gt 0) {
            Write-ToolOutput ('OnBase pinned (policy AddinList=1): {0}; slow-add-in prompt suppressed: {1}' -f $onbasePinned, $promptSuppressed) -Level Detail
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Outlook add-in repair' -Choices @('None','ReEnable','PinOnBase') -Default 'None' -Silent:$Silent

        if ($action -eq 'ReEnable') {
            if (Test-Path -LiteralPath $disabledKey) { Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $crashKey)    { Remove-Item -LiteralPath $crashKey -Recurse -Force -ErrorAction SilentlyContinue }
            if (-not (Test-Path -LiteralPath $doNotDisable)) { New-Item -Path $doNotDisable -Force -ErrorAction SilentlyContinue | Out-Null }

            $reenabled = New-Object System.Collections.Generic.List[string]
            foreach ($a in $addins) {
                if ($a.Hive -eq 'HKCU' -and $a.LoadBehavior -eq 0) {
                    Set-ItemProperty -LiteralPath $a.PSPath -Name 'LoadBehavior' -Value 3 -ErrorAction SilentlyContinue
                    # Verify the write took before crediting it - matches the PinOnBase
                    # action's own verify-after-write pattern below. A policy-locked or
                    # otherwise write-protected key would previously fail silently while still
                    # being counted as re-enabled.
                    $nowLb = (Get-ItemProperty -LiteralPath $a.PSPath -Name 'LoadBehavior' -ErrorAction SilentlyContinue).LoadBehavior
                    if ($nowLb -eq 3) {
                        $reenabled.Add($a.FriendlyName)
                    } else {
                        Write-ToolOutput ('LoadBehavior update for {0} did not verify (still {1})' -f $a.FriendlyName, $nowLb) -Level Warning
                    }
                }
                $existing = Get-ItemProperty -LiteralPath $doNotDisable -Name $a.Name -ErrorAction SilentlyContinue
                if ($null -eq $existing) {
                    New-ItemProperty -LiteralPath $doNotDisable -Name $a.Name -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            Complete-ToolRun $run -Status Success -Summary ('Cleared {0} disabled + {1} crashing entr(ies); re-enabled {2} add-in(s)' -f $disabledCount, $crashCount, $reenabled.Count)
            return
        }

        if ($action -eq 'PinOnBase') {
            if ($onbase.Count -eq 0) {
                Complete-ToolRun $run -Status Warning -Summary 'No OnBase/Hyland add-in found to pin'
                return
            }
            # Un-stick now: clear the soft resiliency lists and re-enable any HKCU OnBase registration.
            if (Test-Path -LiteralPath $disabledKey) { Remove-Item -LiteralPath $disabledKey -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $crashKey)    { Remove-Item -LiteralPath $crashKey -Recurse -Force -ErrorAction SilentlyContinue }
            foreach ($o in $onbase) {
                if ($o.Hive -eq 'HKCU' -and $o.LoadBehavior -ne 3) {
                    Set-ItemProperty -LiteralPath $o.PSPath -Name 'LoadBehavior' -Value 3 -ErrorAction SilentlyContinue
                }
            }
            # Pin durably via the policy hive (per-user; works regardless of where OnBase is registered).
            if (-not (Test-Path -LiteralPath $policyRoot)) { New-Item -Path $policyRoot -Force -ErrorAction SilentlyContinue | Out-Null }
            New-ItemProperty -LiteralPath $policyRoot -Name 'DisablePromptOnLoadTimeDisable' -Value 1 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
            if (-not (Test-Path -LiteralPath $policyAddinList)) { New-Item -Path $policyAddinList -Force -ErrorAction SilentlyContinue | Out-Null }
            foreach ($o in $onbase) {
                New-ItemProperty -LiteralPath $policyAddinList -Name $o.Name -Value '1' -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            # Verify the pin took.
            $verified = 0
            $alProps2 = Get-ItemProperty -LiteralPath $policyAddinList -ErrorAction SilentlyContinue
            foreach ($o in $onbase) {
                if ($alProps2 -and ($alProps2.PSObject.Properties.Name -contains $o.Name) -and ([string]$alProps2.$($o.Name) -eq '1')) { $verified++ }
            }
            if ($verified -eq $onbase.Count) {
                Complete-ToolRun $run -Status Success -Summary ('Pinned {0} OnBase/Hyland add-in(s) as always-enabled (policy); Outlook will no longer disable them for slow load time' -f $verified)
            } else {
                Complete-ToolRun $run -Status Warning -Summary ('Pin incomplete: {0} of {1} OnBase add-in(s) verified in the policy AddinList' -f $verified, $onbase.Count)
            }
            return
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} add-in(s) reported; no action taken' -f $addins.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
