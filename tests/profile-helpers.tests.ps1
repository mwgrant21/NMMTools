BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\07-repair-helpers.ps1')
}

Describe 'Get-NmmProfileVerdict' {
    It 'protects Special profiles regardless of other facts' {
        Get-NmmProfileVerdict -Special $true -Loaded $false -IsCurrentUser $false -SidResolves $false -FolderExists $false | Should -Be 'Protected'
    }
    It 'protects Loaded profiles' {
        Get-NmmProfileVerdict -Special $false -Loaded $true -IsCurrentUser $false -SidResolves $false -FolderExists $false | Should -Be 'Protected'
    }
    It 'protects the current user profile even when its SID does not resolve' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $true -SidResolves $false -FolderExists $true | Should -Be 'Protected'
    }
    It 'flags an unresolvable SID as Orphan-UnknownSid' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $false -SidResolves $false -FolderExists $true | Should -Be 'Orphan-UnknownSid'
    }
    It 'flags a missing folder as Orphan-MissingFolder when the SID resolves' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $false -SidResolves $true -FolderExists $false | Should -Be 'Orphan-MissingFolder'
    }
    It 'treats a resolving SID with an existing folder as Healthy' {
        Get-NmmProfileVerdict -Special $false -Loaded $false -IsCurrentUser $false -SidResolves $true -FolderExists $true | Should -Be 'Healthy'
    }
    It 'never throws for any boolean combination' {
        foreach ($a in @($true,$false)) {
          foreach ($b in @($true,$false)) {
            foreach ($c in @($true,$false)) {
              foreach ($d in @($true,$false)) {
                foreach ($e in @($true,$false)) {
                  { Get-NmmProfileVerdict -Special $a -Loaded $b -IsCurrentUser $c -SidResolves $d -FolderExists $e } | Should -Not -Throw
                }
              }
            }
          }
        }
    }
}
