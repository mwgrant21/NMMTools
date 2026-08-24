function Repair-AutoDiscover {
    [CmdletBinding()]
    param([switch]$Silent)

    # HEAD the AutoDiscover endpoint; returns a human-readable status string.
    function Test-AutoDiscoverEndpoint {
        try {
            $r = Invoke-WebRequest -Uri 'https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml' -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            return ('reachable (HTTP {0})' -f $r.StatusCode)
        } catch {
            return ('unreachable: {0}' -f $_.Exception.Message)
        }
    }

    $run = $null
    try {
        $run = New-ToolRun -Id 'autodiscover-fix'

        # The AutoDiscover cache and its registry key are per-user.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx

        $adGlob = $null
        if ($ctx.Resolved) { $adGlob = Join-Path $ctx.LocalAppData 'Microsoft\Outlook\*autodiscover*' }
        $adKey  = $null
        if ($ctx.Resolved) { $adKey = Get-UserHivePath -Context $ctx -SubPath 'Software\Microsoft\Office\16.0\Outlook\AutoDiscover' }

        # --- Report ---
        Write-ToolOutput ('AutoDiscover endpoint: {0}' -f (Test-AutoDiscoverEndpoint)) -Level Info
        # The endpoint test above is machine-wide and stays useful either way;
        # the two per-user readings below would describe the technician's own
        # AutoDiscover state if the target hive is unreachable.
        if ($ctx.Resolved) {
            $adFiles = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
            Write-ToolOutput ('AutoDiscover cache files: {0}' -f $adFiles.Count) -Level Detail
            Write-ToolOutput ('AutoDiscover registry key present: {0}' -f (Test-Path -LiteralPath $adKey)) -Level Detail
        } else {
            Write-ToolOutput ('AutoDiscover cache/registry state not readable - {0}' -f $ctx.Reason) -Level Warning
        }

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'AutoDiscover fix' -Choices @('None','Fix') -Default 'None' -Silent:$Silent

        if ($action -ne 'Fix') {
            Complete-ToolRun $run -Status Success -Summary 'AutoDiscover state reported; no action taken'
            return
        }
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot clear the AutoDiscover cache - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        # DNS cache is machine-wide, so this is correct regardless of account.
        ipconfig /flushdns | Out-Null
        $before = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        $before | Remove-Item -Force -ErrorAction SilentlyContinue
        $after = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        $removed = $before.Count - $after.Count
        if (Test-Path -LiteralPath $adKey) {
            Remove-Item -LiteralPath $adKey -Recurse -Force -ErrorAction SilentlyContinue
        }
        $retest = Test-AutoDiscoverEndpoint
        if ($retest -like 'reachable*') {
            Complete-ToolRun $run -Status Success -Summary ('DNS flushed, {0} cache file(s) + reg key cleared; endpoint {1}' -f $removed, $retest)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('DNS flushed, {0} cache file(s) + reg key cleared; endpoint still {1}' -f $removed, $retest)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
