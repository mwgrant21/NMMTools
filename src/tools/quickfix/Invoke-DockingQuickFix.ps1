function Invoke-DockingQuickFix {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'docking-quick-fix'

        Write-ToolOutput 'Docking quick fix will: detect displays and switch to extend mode. Use Win+P afterward to change the display mode if needed.' -Level Info
        $go = Read-ToolChoice -Prompt 'Proceed with the docking quick fix?' -Choices @('Yes','No') -Default 'No' -Silent:$Silent
        if ($go -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'Docking quick fix declined'
            return
        }

        Start-Process -FilePath 'DisplaySwitch.exe' -ArgumentList '/detect' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Start-Process -FilePath 'DisplaySwitch.exe' -ArgumentList '/extend' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        Complete-ToolRun $run -Status Success -Summary 'Displays detected and set to extend; use Win+P to change mode'
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
