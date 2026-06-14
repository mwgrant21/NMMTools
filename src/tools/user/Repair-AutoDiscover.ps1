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
        $adGlob = "$env:LOCALAPPDATA\Microsoft\Outlook\*autodiscover*"
        $adKey  = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\AutoDiscover'

        # --- Report ---
        Write-ToolOutput ('AutoDiscover endpoint: {0}' -f (Test-AutoDiscoverEndpoint)) -Level Info
        $adFiles = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        Write-ToolOutput ('AutoDiscover cache files: {0}' -f $adFiles.Count) -Level Detail
        Write-ToolOutput ('AutoDiscover registry key present: {0}' -f (Test-Path -LiteralPath $adKey)) -Level Detail

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'AutoDiscover fix' -Choices @('None','Fix') -Default 'None' -Silent:$Silent

        if ($action -ne 'Fix') {
            Complete-ToolRun $run -Status Success -Summary 'AutoDiscover state reported; no action taken'
            return
        }

        ipconfig /flushdns | Out-Null
        $removed = @(Get-ChildItem -Path $adGlob -ErrorAction SilentlyContinue)
        $removed | Remove-Item -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $adKey) {
            Remove-Item -LiteralPath $adKey -Recurse -Force -ErrorAction SilentlyContinue
        }
        $retest = Test-AutoDiscoverEndpoint
        if ($retest -like 'reachable*') {
            Complete-ToolRun $run -Status Success -Summary ('DNS flushed, {0} cache file(s) + reg key cleared; endpoint {1}' -f $removed.Count, $retest)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('DNS flushed, {0} cache file(s) + reg key cleared; endpoint still {1}' -f $removed.Count, $retest)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
