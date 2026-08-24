function Invoke-OneDriveQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'onedrive-quick-fix'

        $candidates = @(
            "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
            "$env:PROGRAMFILES\Microsoft OneDrive\OneDrive.exe",
            "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
        )
        $exe = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

        Write-ToolOutput 'OneDrive quick fix will: stop OneDrive, reset it (/reset), and restart it.' -Level Info
        if (-not $exe) {
            Write-ToolOutput 'OneDrive.exe not found at the expected paths.' -Level Warning
            Complete-ToolRun $run -Status Warning -Summary 'OneDrive not installed at expected paths; nothing done'
            return
        }
        $go = Read-ToolChoice -Prompt 'Proceed with the OneDrive reset?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'OneDrive quick fix declined'
            return
        }

        Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process -FilePath $exe -ArgumentList '/reset' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Start-Process -FilePath $exe -ErrorAction SilentlyContinue

        Complete-ToolRun $run -Status Success -Summary 'OneDrive reset and restarted'
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
