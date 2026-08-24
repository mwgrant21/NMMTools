function Reset-OutlookOst {
    [CmdletBinding()]
    param([switch]$Silent)

    function Stop-OutlookGraceful {
        $proc = @(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue)
        if ($proc.Count -eq 0) { return $true }
        foreach ($p in $proc) { $p.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 3
        if (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -gt 0) {
            Stop-Process -Name 'OUTLOOK' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        return (@(Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue).Count -eq 0)
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'outlook-ost-rebuild'

        # The OST lives in the mailbox owner's profile, not the caller's.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        $ostDir = $null
        if ($ctx.Resolved) { $ostDir = Join-Path $ctx.LocalAppData 'Microsoft\Outlook' }

        # --- Report ---
        # An unresolved context leaves $ostDir null, and "$null\*.ost" globs the
        # DRIVE ROOT. Short-circuit rather than let that expand.
        $ost = @()
        if ($ctx.Resolved) {
            $ost = @(Get-ChildItem -Path (Join-Path $ostDir '*.ost') -ErrorAction SilentlyContinue)
        } else {
            Write-ToolOutput ('Cannot read OST files for the target user - {0}.' -f $ctx.Reason) -Level Warning
        }
        if ($ost.Count -eq 0) {
            Write-ToolOutput 'No .ost files found (Outlook may be in IMAP or online mode).' -Level Warning
        } else {
            Write-ToolOutput ('OST files: {0}' -f $ost.Count) -Level Info
            foreach ($o in $ost) {
                Write-ToolOutput ('  {0}  ({1} MB)' -f $o.Name, [math]::Round($o.Length / 1MB, 1)) -Level Detail
            }
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Rename OST to force an Exchange re-sync' -Choices @('None','RenameOst') -Default 'None' -Silent:$Silent

        if ($action -ne 'RenameOst') {
            Complete-ToolRun $run -Status Success -Summary ('{0} OST file(s) reported; no action taken' -f $ost.Count)
            return
        }
        if (-not $ctx.Resolved) {
            # Distinct from the empty-list case below: an unreadable profile is
            # not the same as a mailbox with no OST, and saying 'IMAP/online
            # mode' here would be a plain misdiagnosis.
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot rename the OST - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }
        if ($ost.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary 'No OST file to rebuild (IMAP/online mode)'
            return
        }
        $confirm = Read-ToolChoice -Prompt 'Close Outlook and rename the OST? Outlook re-syncs from Exchange on next launch.' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($confirm -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'RenameOst cancelled'
            return
        }
        if (-not (Stop-OutlookGraceful)) {
            Complete-ToolRun $run -Status Warning -Summary 'Outlook is still running; the OST is locked - close Outlook and retry'
            return
        }
        # Renaming is not deleting, but the enumeration below still walks through
        # a junctioned $ostDir into whatever it points at, and this process is
        # elevated. Gate the directory before touching anything inside it.
        if (-not (Test-UserPathContained -Context $ctx -Path $ostDir)) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Refused to rename the OST: {0} did not pass the profile containment check. Nothing was changed.' -f $ostDir)
            return
        }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $renamed = 0
        foreach ($o in @(Get-ChildItem -Path (Join-Path $ostDir '*.ost') -ErrorAction SilentlyContinue)) {
            $newName = ('{0}.bak_{1}' -f $o.Name, $stamp)
            Rename-Item -LiteralPath $o.FullName -NewName $newName -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $o.FullName)) { $renamed++ }
        }
        if ($renamed -gt 0) {
            Complete-ToolRun $run -Status Success -Summary ('{0} OST file(s) renamed; relaunch Outlook to rebuild from Exchange' -f $renamed)
        } else {
            Complete-ToolRun $run -Status Warning -Summary 'No OST files were renamed (still locked or already gone)'
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
