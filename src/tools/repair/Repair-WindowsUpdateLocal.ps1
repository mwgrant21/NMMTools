function Repair-WindowsUpdateLocal {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'windows-update-repair'

        $choice = Read-ToolChoice `
            -Prompt 'Reset Windows Update components? (stops WU services, renames SoftwareDistribution + Catroot2)' `
            -Choices @('Yes', 'No') `
            -Default 'No' `
            -Silent:$Silent

        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined Windows Update component reset'
            return
        }

        # Stop Windows Update services - cryptSvc last, matching the Codex-validated WU cache
        # flush order used elsewhere in this codebase (Invoke-Win11FeatureUpdateUnlock.ps1).
        Write-ToolOutput 'Stopping Windows Update services...' -Level Info
        foreach ($svc in @('wuauserv', 'bits', 'msiserver', 'cryptSvc')) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        }
        Write-ToolOutput 'Services stopped.' -Level Info

        # Rename SoftwareDistribution (guard pre-existing .old)
        $sdPath    = Join-Path $env:SystemRoot 'SoftwareDistribution'
        $sdOldPath = Join-Path $env:SystemRoot 'SoftwareDistribution.old'
        $sdRenamed = $false
        if (Test-Path $sdPath) {
            if (Test-Path $sdOldPath) {
                Write-ToolOutput 'Pre-existing SoftwareDistribution.old found - removing before rename...' -Level Info
                Remove-Item $sdOldPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -Path $sdPath -NewName 'SoftwareDistribution.old' -ErrorAction SilentlyContinue
            $sdRenamed = -not (Test-Path $sdPath)
            if ($sdRenamed) {
                Write-ToolOutput 'SoftwareDistribution renamed to SoftwareDistribution.old.' -Level Info
            } else {
                Write-ToolOutput 'SoftwareDistribution rename failed (folder may be locked).' -Level Warning
            }
        } else {
            Write-ToolOutput 'SoftwareDistribution folder not found - skipped rename.' -Level Warning
        }

        # Rename Catroot2 (guard pre-existing .old)
        $catPath    = Join-Path $env:SystemRoot 'System32\Catroot2'
        $catOldPath = Join-Path $env:SystemRoot 'System32\Catroot2.old'
        $catRenamed = $false
        if (Test-Path $catPath) {
            if (Test-Path $catOldPath) {
                Write-ToolOutput 'Pre-existing Catroot2.old found - removing before rename...' -Level Info
                Remove-Item $catOldPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Rename-Item -Path $catPath -NewName 'Catroot2.old' -ErrorAction SilentlyContinue
            $catRenamed = -not (Test-Path $catPath)
            if ($catRenamed) {
                Write-ToolOutput 'Catroot2 renamed to Catroot2.old.' -Level Info
            } else {
                Write-ToolOutput 'Catroot2 rename failed (folder may be locked).' -Level Warning
            }
        } else {
            Write-ToolOutput 'Catroot2 folder not found - skipped rename.' -Level Warning
        }

        # Re-register 36 Windows Update DLLs
        Write-ToolOutput 'Re-registering Windows Update DLLs...' -Level Info
        $dlls = @(
            'atl.dll',      'urlmon.dll',   'mshtml.dll',   'shdocvw.dll',  'browseui.dll',
            'jscript.dll',  'vbscript.dll', 'scrrun.dll',   'msxml.dll',    'msxml3.dll',
            'msxml6.dll',   'actxprxy.dll', 'softpub.dll',  'wintrust.dll', 'dssenh.dll',
            'rsaenh.dll',   'gpkcsp.dll',   'sccbase.dll',  'slbcsp.dll',   'cryptdlg.dll',
            'oleaut32.dll', 'ole32.dll',    'shell32.dll',  'initpki.dll',  'wuapi.dll',
            'wuaueng.dll',  'wuaueng1.dll', 'wucltui.dll',  'wups.dll',     'wups2.dll',
            'wuweb.dll',    'qmgr.dll',     'qmgrprxy.dll', 'wucltux.dll',  'muweb.dll',
            'wuwebv.dll'
        )
        foreach ($dll in $dlls) {
            & regsvr32.exe /s $dll 2>&1 | Out-Null
        }
        Write-ToolOutput 'Windows Update DLLs re-registered.' -Level Info

        # Restart services - cryptSvc first, matching the Codex-validated WU cache flush order.
        Write-ToolOutput 'Restarting Windows Update services...' -Level Info
        foreach ($svc in @('cryptSvc', 'bits', 'msiserver', 'wuauserv')) {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
        Write-ToolOutput 'Services restarted.' -Level Info

        $resetParts = @()
        if ($sdRenamed)  { $resetParts += 'SoftwareDistribution' }
        if ($catRenamed) { $resetParts += 'Catroot2' }
        if ($resetParts.Count -eq 0) {
            # Neither folder renamed - the tool's entire purpose (forcing a fresh
            # SoftwareDistribution/Catroot2) didn't happen, most likely because WU services
            # were still holding handles on them. Services cycled and DLLs re-registered, but
            # reporting Success here would hide that the actual reset never took effect.
            Complete-ToolRun $run -Status Warning `
                -Summary 'Windows Update reset incomplete: services cycled and DLLs re-registered, but SoftwareDistribution and Catroot2 could not be renamed (likely still locked)'
        } else {
            $resetItems = $resetParts -join ', '
            Complete-ToolRun $run -Status Success `
                -Summary ('Windows Update reset: services cycled, DLLs re-registered, folders renamed ({0})' -f $resetItems)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
