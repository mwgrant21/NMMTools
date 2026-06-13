BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\08-browser-helpers.ps1')
    $script:Catalog = @(Get-BrowserCatalog)
}

Describe 'Get-BrowserCatalog' {
    It 'returns the four supported browsers in order' {
        $script:Catalog.Count | Should -Be 4
        ($script:Catalog | ForEach-Object { $_.Name }) | Should -Be @('Chrome','Edge','Brave','Firefox')
    }
    It 'classifies three Chromium browsers and one Firefox' {
        @($script:Catalog | Where-Object { $_.Family -eq 'Chromium' }).Count | Should -Be 3
        @($script:Catalog | Where-Object { $_.Family -eq 'Firefox' }).Count  | Should -Be 1
    }
    It 'gives every browser a BasePath, ProcessNames, and ProfileGlobs' {
        foreach ($b in $script:Catalog) {
            [string]::IsNullOrWhiteSpace($b.BasePath) | Should -BeFalse
            @($b.ProcessNames).Count  | Should -BeGreaterThan 0
            @($b.ProfileGlobs).Count  | Should -BeGreaterThan 0
        }
    }
}

Describe 'browser-clear preserve invariant' {
    It 'never clears a preserved file (ClearFiles intersect PreserveFiles is empty)' {
        foreach ($b in $script:Catalog) {
            $overlap = @($b.ClearFiles | Where-Object { $b.PreserveFiles -contains $_ })
            $overlap | Should -BeNullOrEmpty -Because "$($b.Name) must not clear a preserved file"
        }
    }
    It 'preserves Chromium passwords, autofill, and bookmarks' {
        foreach ($b in @($script:Catalog | Where-Object { $_.Family -eq 'Chromium' })) {
            foreach ($keep in @('Login Data','Web Data','Bookmarks')) {
                $b.ClearFiles    | Should -Not -Contain $keep
                $b.PreserveFiles | Should -Contain $keep
            }
        }
    }
    It 'preserves Firefox passwords, bookmarks (places.sqlite), and autofill' {
        $ff = @($script:Catalog | Where-Object { $_.Name -eq 'Firefox' })[0]
        foreach ($keep in @('key4.db','logins.json','places.sqlite','formhistory.sqlite')) {
            $ff.ClearFiles    | Should -Not -Contain $keep
            $ff.PreserveFiles | Should -Contain $keep
        }
    }
}

Describe 'browser-backup set' {
    It 'includes the password stores' {
        foreach ($b in @($script:Catalog | Where-Object { $_.Family -eq 'Chromium' })) {
            $b.BackupFiles | Should -Contain 'Login Data'
        }
        $ff = @($script:Catalog | Where-Object { $_.Name -eq 'Firefox' })[0]
        $ff.BackupFiles | Should -Contain 'key4.db'
        $ff.BackupFiles | Should -Contain 'logins.json'
    }
}

Describe 'Get-BrowserProfiles' {
    It 'returns an empty array when the base path is absent' {
        $fake = @{ BasePath = 'Z:\NoSuchBrowser\User Data'; ProfileGlobs = @('Default','Profile*') }
        @(Get-BrowserProfiles -Browser $fake).Count | Should -Be 0
    }
}
