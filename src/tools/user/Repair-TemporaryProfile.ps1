function Repair-TemporaryProfile {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'temp-profile-repair'

        $plPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $plReg  = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

        # --- Report (read-only scan) ---
        $keys = @(Get-ChildItem -LiteralPath $plPath -ErrorAction SilentlyContinue)
        $tempPattern = @()
        $orphanBak = @()
        foreach ($k in $keys) {
            $sid = Split-Path $k.Name -Leaf
            if ($sid.EndsWith('.bak')) {
                $img = (Get-ItemProperty -LiteralPath $k.PSPath -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
                $realSid = $sid -replace '\.bak$', ''
                $realExists = Test-Path -LiteralPath ('{0}\{1}' -f $plPath, $realSid)
                if ($realExists) {
                    $tempPattern += [PSCustomObject]@{ RealSid = $realSid; Img = $img }
                    Write-ToolOutput ('  [TEMP-PROFILE] {0}  ({1})' -f $sid, $img) -Level Warning
                } else {
                    $orphanBak += [PSCustomObject]@{ Sid = $sid; Img = $img }
                    Write-ToolOutput ('  [orphan .bak] {0}  ({1})' -f $sid, $img) -Level Detail
                }
            }
        }

        if ($tempPattern.Count -eq 0) {
            if ($orphanBak.Count -gt 0) {
                Complete-ToolRun $run -Status Warning -Summary ('{0} orphan .bak key(s) found but no temp-profile pattern; no auto-repair' -f $orphanBak.Count)
            } else {
                Complete-ToolRun $run -Status Success -Summary 'No temporary profile issues detected'
            }
            return
        }

        Write-ToolOutput ('{0} temporary-profile pattern(s) detected (real SID + .bak).' -f $tempPattern.Count) -Level Warning

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Temporary profile action' -Choices @('None','RepairProfile') -Default 'None' -Silent:$Silent

        switch ($action) {

            'RepairProfile' {
                Write-ToolOutput 'WARNING: this edits HKLM ProfileList. The AFFECTED USER MUST BE LOGGED OFF first.' -Level Warning
                $gate = Read-ToolChoice -Prompt 'Type CONFIRM to repair (is the affected user logged off?)' `
                    -Choices @('CONFIRM','Cancel') -Default 'Cancel' -Silent:$Silent
                if ($gate -ne 'CONFIRM') {
                    Complete-ToolRun $run -Status Skipped -Summary 'RepairProfile cancelled (no CONFIRM)'
                } else {
                    # 1. Backup ProfileList FIRST; abort if export fails (no changes made).
                    $backup = Join-Path $env:TEMP ('ProfileList_backup_{0}.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
                    & reg.exe export $plReg $backup /y *>$null
                    if (-not (Test-Path -LiteralPath $backup)) {
                        Complete-ToolRun $run -Status Failed -Summary 'Aborted: could not export ProfileList backup (no changes made)'
                        return
                    }
                    Write-ToolOutput ('ProfileList backed up: {0}' -f $backup) -Level Info

                    # 2. For each temp-profile pattern: reg copy .bak -> real SID (type-correct), then delete .bak.
                    $repaired = 0
                    foreach ($p in $tempPattern) {
                        $realReg = '{0}\{1}' -f $plReg, $p.RealSid
                        $bakReg  = '{0}\{1}.bak' -f $plReg, $p.RealSid
                        & reg.exe delete $realReg /f *>$null
                        & reg.exe copy $bakReg $realReg /s /f *>$null
                        if ($LASTEXITCODE -eq 0) {
                            & reg.exe delete $bakReg /f *>$null
                            Write-ToolOutput ('  Repaired: {0}' -f $p.Img) -Level Success
                            $repaired++
                        } else {
                            Write-ToolOutput ('  Repair failed for {0} (reg copy exit {1}); backup retained at {2}' -f $p.Img, $LASTEXITCODE, $backup) -Level Error
                        }
                    }

                    if ($repaired -gt 0) {
                        Complete-ToolRun $run -Status Success -Summary ('Repaired {0} temp profile(s); backup: {1}; have the user log in again' -f $repaired, $backup)
                    } else {
                        Complete-ToolRun $run -Status Failed -Summary ('No profiles repaired; backup retained at {0}' -f $backup)
                    }
                }
            }

            default {
                Complete-ToolRun $run -Status Warning -Summary ('{0} temp-profile pattern(s) detected; no repair applied' -f $tempPattern.Count)
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
