function Invoke-AvPrepQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'av-prep-quick-fix'

        Write-ToolOutput 'Audio/Video prep will: close meeting apps and browsers (Teams, Zoom, Skype, Edge, Chrome, Firefox), restart the audio service, and open the Camera app.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed? This closes browsers and meeting apps.' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Audio/Video prep declined'
            return
        }

        $killed = 0
        foreach ($name in @('Teams','ms-teams','MSTeams','Zoom','Skype','msedge','chrome','firefox')) {
            $p = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
            if ($p.Count -gt 0) {
                $p | Stop-Process -Force -ErrorAction SilentlyContinue
                $killed++
            }
        }
        Start-Sleep -Seconds 2
        Restart-Service -Name 'Audiosrv' -Force -ErrorAction SilentlyContinue
        Start-Process 'microsoft.windows.camera:' -ErrorAction SilentlyContinue

        $svc = (Get-Service -Name 'Audiosrv' -ErrorAction SilentlyContinue).Status
        if (-not $svc) { $svc = 'Unknown' }
        if ($svc -eq 'Running') {
            Complete-ToolRun $run -Status Success -Summary ('{0} app group(s) closed; audio service Running; Camera opened' -f $killed)
        } else {
            Complete-ToolRun $run -Status Warning -Summary ('{0} app group(s) closed; audio service status {1}' -f $killed, $svc)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
