function Get-StartupPrograms {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'startup-programs'

        # Note: when run as SYSTEM (PDQ context), HKCU maps to SYSTEM's hive (HKU\S-1-5-18),
        # not the logged-on user's. [User] entries then reflect SYSTEM's autorun keys.
        $regPaths = @(
            [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Location = 'Machine' }
            [PSCustomObject]@{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Location = 'User'    }
        )

        $startupItems = @()
        foreach ($entry in $regPaths) {
            if (Test-Path $entry.Path) {
                $props = Get-ItemProperty $entry.Path -ErrorAction SilentlyContinue
                if ($props) {
                    $props | Get-Member -MemberType NoteProperty |
                        Where-Object { $_.Name -notlike 'PS*' } |
                        ForEach-Object {
                            $startupItems += [PSCustomObject]@{
                                Name     = $_.Name
                                Location = $entry.Location
                            }
                        }
                }
            }
        }

        if ($startupItems.Count -eq 0) {
            Complete-ToolRun $run -Status Warning -Summary 'No startup entries found in Run registry keys'
            return
        }

        Write-ToolOutput ('Startup entries found: {0}' -f $startupItems.Count)
        # Each startup entry is a scan row; Detail level for the table
        foreach ($item in $startupItems) {
            Write-ToolOutput ('{0,-36}  [{1}]' -f $item.Name, $item.Location) -Level Detail
        }

        Complete-ToolRun $run -Status Success -Summary ('{0} startup item(s) found' -f $startupItems.Count)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
