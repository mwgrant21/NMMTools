function Set-DefaultApps {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'default-apps'

        # --- Report: current associations for common types (read-only) ---
        Write-ToolOutput 'Current file associations (common types):' -Level Info
        $exts = @('.txt','.pdf','.jpg','.png','.docx','.xlsx','.html','.zip','.mp4')
        foreach ($ext in $exts) {
            $assoc = $null
            # assoc exits non-zero for an unregistered extension; a non-zero native exit does NOT throw
            # in PS 5.1, so gate the display on $LASTEXITCODE (the catch only handles PS-level errors).
            try { $assoc = (cmd /c ('assoc {0}' -f $ext) 2>$null) } catch { $assoc = $null }
            if ($LASTEXITCODE -eq 0 -and $assoc) {
                Write-ToolOutput ('  {0}' -f ($assoc -join ' ')) -Level Detail
            } else {
                Write-ToolOutput ('  {0} = (none)' -f $ext) -Level Detail
            }
        }
        Write-ToolOutput 'Note: Windows 10/11 protect the per-user default-app choice; per-type changes must be made in Settings.' -Level Info

        # --- Action menu ---
        $action = Read-ToolChoice -Prompt 'Default apps action' `
            -Choices @('None','OpenDefaultApps') -Default 'None' -Silent:$Silent

        switch ($action) {

            'OpenDefaultApps' {
                Start-Process 'ms-settings:defaultapps' -ErrorAction SilentlyContinue
                Write-ToolOutput 'Default Apps settings opened. Set per-type and per-protocol defaults there.' -Level Info
                Complete-ToolRun $run -Status Success -Summary 'Opened Default Apps settings'
            }

            default {
                Complete-ToolRun $run -Status Success -Summary 'Reported current associations; no action taken'
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
