function Clear-ProfileCache {
    [CmdletBinding()]
    param([switch]$Silent)

    $run = $null
    try {
        $run = New-ToolRun -Id 'profile-cache'

        # Every folder below lives in one specific person's profile. Gate before
        # the report, not just the action: sizing the technician's caches and
        # calling them the user's is a misdiagnosis, and clearing them is worse.
        $ctx = Get-TargetUserContext
        Write-UserContextNotice -Context $ctx
        if (-not $ctx.Resolved) {
            Complete-ToolRun $run -Status Failed `
                -Summary ('Cannot read or clear the profile cache - {0}. Nothing was changed.' -f $ctx.Reason)
            return
        }

        $prof = $ctx.ProfilePath
        # Cleanable=$true folders have their CONTENTS cleared. OneDrive (app folder) and Downloads
        # (user data) are REPORT-ONLY - clearing them would break OneDrive / delete user files.
        $folders = @(
            @{ Name = 'Temp';      Path = (Join-Path $ctx.LocalAppData 'Temp'); Cleanable = $true },
            @{ Name = 'Teams';     Path = (Join-Path $prof 'AppData\Local\Microsoft\Teams'); Cleanable = $true },
            @{ Name = 'Office';    Path = (Join-Path $prof 'AppData\Local\Microsoft\Office\16.0\OfficeFileCache'); Cleanable = $true },
            @{ Name = 'Chrome';    Path = (Join-Path $prof 'AppData\Local\Google\Chrome\User Data\Default\Cache'); Cleanable = $true },
            @{ Name = 'Edge';      Path = (Join-Path $prof 'AppData\Local\Microsoft\Edge\User Data\Default\Cache'); Cleanable = $true },
            @{ Name = 'OneDrive';  Path = (Join-Path $prof 'AppData\Local\Microsoft\OneDrive'); Cleanable = $false },
            @{ Name = 'Downloads'; Path = (Join-Path $prof 'Downloads'); Cleanable = $false }
        )

        # --- Report (read-only sizes) ---
        Write-ToolOutput 'Profile cache sizes:' -Level Info
        $totalBefore = [int64]0
        foreach ($f in $folders) {
            if (Test-Path -LiteralPath $f.Path) {
                $sz = [int64]0
                try {
                    $s = (Get-ChildItem -LiteralPath $f.Path -Recurse -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum).Sum
                    if ($s) { $sz = [int64]$s }
                } catch { }
                $totalBefore += $sz
                $tag = ''
                if (-not $f.Cleanable) { $tag = '  (report-only)' }
                Write-ToolOutput ('  {0,-9} {1,8:N1} MB{2}' -f $f.Name, ($sz / 1MB), $tag) -Level Detail
            }
        }
        Write-ToolOutput ('Total: {0:N1} MB' -f ($totalBefore / 1MB)) -Level Info

        # --- Action ---
        $action = Read-ToolChoice -Prompt 'Profile cache action' -Choices @('None','CleanCaches') -Default 'None' -Silent:$Silent

        switch ($action) {

            'CleanCaches' {
                Write-ToolOutput 'This clears the Temp/Teams/Office/Chrome/Edge caches (NOT OneDrive or Downloads).' -Level Warning
                $confirm = Read-ToolChoice -Prompt 'Clear the cleanable cache folders?' `
                    -Choices @('Yes','No') -Default 'No' -Silent:$Silent
                if ($confirm -ne 'Yes') {
                    Complete-ToolRun $run -Status Skipped -Summary 'CleanCaches cancelled'
                } else {
                    foreach ($f in ($folders | Where-Object { $_.Cleanable })) {
                        if (Test-Path -LiteralPath $f.Path) {
                            # Containment-gated: every cleanable folder here is
                            # inside the target user's own profile, so all of them
                            # are junction-plantable by that user.
                            [void](Remove-UserPathContent -Context $ctx -Path $f.Path)
                        }
                    }
                    $totalAfter = [int64]0
                    foreach ($f in $folders) {
                        if (Test-Path -LiteralPath $f.Path) {
                            try {
                                $s = (Get-ChildItem -LiteralPath $f.Path -Recurse -Force -ErrorAction SilentlyContinue |
                                    Measure-Object -Property Length -Sum).Sum
                                if ($s) { $totalAfter += [int64]$s }
                            } catch { }
                        }
                    }
                    $freed = [math]::Round((($totalBefore - $totalAfter) / 1MB), 1)
                    if ($freed -lt 0) { $freed = 0 }
                    Complete-ToolRun $run -Status Success -Summary ('Cleared cleanable caches; freed {0} MB' -f $freed)
                }
            }

            default {
                Complete-ToolRun $run -Status Success -Summary ('Profile cache reported ({0:N1} MB); no action taken' -f ($totalBefore / 1MB))
            }
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
