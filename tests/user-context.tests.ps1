BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'src\core\02-output.ps1')
    . (Join-Path $repoRoot 'src\core\12-user-context.ps1')

    # A context object is just a property bag to these helpers, so the tests
    # build one directly instead of depending on the real logged-on user.
    function New-TestContext {
        param([string]$ProfilePath, [bool]$Resolved = $true, [string]$HiveRoot = 'HKCU:')
        [pscustomobject]@{
            Resolved     = $Resolved
            IsRedirected = $false
            IsCurrentUser= $true
            ProcessName  = 'TEST\tech'
            UserName     = 'TEST\enduser'
            HiveRoot     = $HiveRoot
            ProfilePath  = $ProfilePath
            AppData      = (Join-Path $ProfilePath 'AppData\Roaming')
            LocalAppData = (Join-Path $ProfilePath 'AppData\Local')
            Reason       = 'test context'
        }
    }

    # Junctions need no privilege to create - that is precisely why the
    # containment gate exists. If this box cannot make one, the junction tests
    # are skipped rather than silently passing.
    function New-TestJunction {
        param([string]$Link, [string]$Target)
        try {
            New-Item -ItemType Junction -Path $Link -Target $Target -ErrorAction Stop | Out-Null
            return $true
        } catch { return $false }
    }
}

Describe 'Get-UserHivePath' {
    It 'throws when the target user is unresolved' {
        $ctx = New-TestContext -ProfilePath 'C:\Users\nobody' -Resolved $false
        { Get-UserHivePath -Context $ctx -SubPath 'Software\Test' } | Should -Throw
    }

    It 'names the offending context in the error so the call site is findable' {
        $ctx = New-TestContext -ProfilePath 'C:\Users\nobody' -Resolved $false
        { Get-UserHivePath -Context $ctx -SubPath 'Software\Test' } |
            Should -Throw -ExpectedMessage '*Get-UserHivePath*'
    }

    It 'returns the calling hive only when -AllowUnresolved is explicit' {
        $ctx = New-TestContext -ProfilePath 'C:\Users\nobody' -Resolved $false
        Get-UserHivePath -Context $ctx -SubPath 'Software\Test' -AllowUnresolved |
            Should -Be 'HKCU:\Software\Test'
    }

    It 'builds a path under the resolved hive root' {
        $ctx = New-TestContext -ProfilePath 'C:\Users\bob' -HiveRoot 'Registry::HKEY_USERS\S-1-5-21-1-2-3-1001'
        Get-UserHivePath -Context $ctx -SubPath 'Software\Test' |
            Should -Be 'Registry::HKEY_USERS\S-1-5-21-1-2-3-1001\Software\Test'
    }

    It 'does not double a separator when the caller supplies a leading slash' {
        $ctx = New-TestContext -ProfilePath 'C:\Users\bob'
        Get-UserHivePath -Context $ctx -SubPath '\Software\Test' | Should -Be 'HKCU:\Software\Test'
    }
}

Describe 'Test-UserPathContained' {
    BeforeEach {
        $script:sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("nmm-ctx-" + [System.Guid]::NewGuid().ToString('N'))
        $script:profile = Join-Path $script:sandbox 'prof'
        $script:inside  = Join-Path $script:profile 'AppData\Local\Cache'
        New-Item -ItemType Directory -Path $script:inside -Force | Out-Null
        $script:ctx = New-TestContext -ProfilePath $script:profile
    }
    AfterEach {
        if (Test-Path -LiteralPath $script:sandbox) {
            Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts a real directory inside the profile' {
        Test-UserPathContained -Context $script:ctx -Path $script:inside | Should -BeTrue
    }

    It 'rejects an empty path' {
        Test-UserPathContained -Context $script:ctx -Path '' | Should -BeFalse
    }

    It 'rejects any path when the context is unresolved' {
        $bad = New-TestContext -ProfilePath $script:profile -Resolved $false
        Test-UserPathContained -Context $bad -Path $script:inside | Should -BeFalse
    }

    It 'rejects a path that does not exist' {
        Test-UserPathContained -Context $script:ctx -Path (Join-Path $script:profile 'nope') | Should -BeFalse
    }

    It 'rejects a directory outside the profile' {
        $outside = Join-Path $script:sandbox 'elsewhere'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Test-UserPathContained -Context $script:ctx -Path $outside | Should -BeFalse
    }

    It 'rejects a sibling whose name merely starts with the profile name' {
        # 'C:\Users\bob2' must not pass as inside 'C:\Users\bob'. This is the
        # prefix-match bug the trailing-separator comparison exists to stop.
        $sibling = $script:profile + '2'
        New-Item -ItemType Directory -Path $sibling -Force | Out-Null
        Test-UserPathContained -Context $script:ctx -Path $sibling | Should -BeFalse
    }

    It 'rejects a traversal path that escapes the profile' {
        $traversal = Join-Path $script:profile '..\elsewhere'
        New-Item -ItemType Directory -Path (Join-Path $script:sandbox 'elsewhere') -Force | Out-Null
        Test-UserPathContained -Context $script:ctx -Path $traversal | Should -BeFalse
    }

    It 'rejects a junction even when the junction itself sits inside the profile' {
        $victim = Join-Path $script:sandbox 'victim'
        New-Item -ItemType Directory -Path $victim -Force | Out-Null
        $link = Join-Path $script:profile 'AppData\Local\Hijack'
        if (-not (New-TestJunction -Link $link -Target $victim)) {
            Set-ItResult -Skipped -Because 'this filesystem does not support junctions'
            return
        }
        Test-UserPathContained -Context $script:ctx -Path $link | Should -BeFalse
    }
}

Describe 'Remove-UserPathContent' {
    BeforeEach {
        $script:sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("nmm-rm-" + [System.Guid]::NewGuid().ToString('N'))
        $script:profile = Join-Path $script:sandbox 'prof'
        $script:cache   = Join-Path $script:profile 'AppData\Local\Cache'
        New-Item -ItemType Directory -Path $script:cache -Force | Out-Null
        $script:ctx = New-TestContext -ProfilePath $script:profile

        # The stand-in for C:\Windows\System32: content that must survive.
        $script:victim     = Join-Path $script:sandbox 'victim'
        New-Item -ItemType Directory -Path $script:victim -Force | Out-Null
        $script:victimFile = Join-Path $script:victim 'critical.txt'
        Set-Content -LiteralPath $script:victimFile -Value 'do not delete' -Encoding Ascii
    }
    AfterEach {
        if (Test-Path -LiteralPath $script:sandbox) {
            Remove-Item -LiteralPath $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'clears ordinary files and subdirectories inside the profile' {
        Set-Content -LiteralPath (Join-Path $script:cache 'a.tmp') -Value 'x' -Encoding Ascii
        New-Item -ItemType Directory -Path (Join-Path $script:cache 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:cache 'sub\b.tmp') -Value 'x' -Encoding Ascii

        Remove-UserPathContent -Context $script:ctx -Path $script:cache | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:cache -Force).Count | Should -Be 0
        # The directory itself is kept - callers rely on clearing, not removing.
        Test-Path -LiteralPath $script:cache | Should -BeTrue
    }

    It 'returns false and changes nothing when the context is unresolved' {
        Set-Content -LiteralPath (Join-Path $script:cache 'a.tmp') -Value 'x' -Encoding Ascii
        $bad = New-TestContext -ProfilePath $script:profile -Resolved $false
        Remove-UserPathContent -Context $bad -Path $script:cache | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:cache -Force).Count | Should -Be 1
    }

    It 'returns false for a target outside the profile' {
        Remove-UserPathContent -Context $script:ctx -Path $script:victim | Should -BeFalse
        Test-Path -LiteralPath $script:victimFile | Should -BeTrue
    }

    It 'refuses when the target directory is itself a junction, leaving the target intact' {
        $link = Join-Path $script:profile 'AppData\Local\Hijack'
        if (-not (New-TestJunction -Link $link -Target $script:victim)) {
            Set-ItResult -Skipped -Because 'this filesystem does not support junctions'
            return
        }
        Remove-UserPathContent -Context $script:ctx -Path $link | Should -BeFalse
        Test-Path -LiteralPath $script:victimFile | Should -BeTrue
    }

    It 'deletes a junction CHILD as a link without following it into the target' {
        # The parent is legitimately inside the profile, so the gate passes -
        # the danger is a child junction. This is the exact reproduction that
        # made the pre-fix code delete files outside the profile.
        $link = Join-Path $script:cache 'Hijack'
        if (-not (New-TestJunction -Link $link -Target $script:victim)) {
            Set-ItResult -Skipped -Because 'this filesystem does not support junctions'
            return
        }
        Remove-UserPathContent -Context $script:ctx -Path $script:cache | Should -BeTrue

        Test-Path -LiteralPath $link              | Should -BeFalse   # link removed
        Test-Path -LiteralPath $script:victimFile | Should -BeTrue    # target untouched
        Test-Path -LiteralPath $script:victim     | Should -BeTrue
    }

    It 'still clears legitimate siblings when a junction child is present' {
        $link = Join-Path $script:cache 'Hijack'
        if (-not (New-TestJunction -Link $link -Target $script:victim)) {
            Set-ItResult -Skipped -Because 'this filesystem does not support junctions'
            return
        }
        Set-Content -LiteralPath (Join-Path $script:cache 'a.tmp') -Value 'x' -Encoding Ascii

        Remove-UserPathContent -Context $script:ctx -Path $script:cache | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:cache -Force).Count | Should -Be 0
        Test-Path -LiteralPath $script:victimFile | Should -BeTrue
    }
}
