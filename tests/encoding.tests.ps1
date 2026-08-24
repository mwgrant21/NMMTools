Describe 'Source encoding' {
    It 'every source .ps1 is ASCII-only (BOM excepted)' {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $offenders = @()
        foreach ($f in (Get-ChildItem (Join-Path $repoRoot 'src') -Recurse -Filter *.ps1)) {
            $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $bad = ($text.ToCharArray() | Where-Object { [int][char]$_ -gt 127 })
            if ($bad.Count -gt 0) { $offenders += ('{0} ({1} non-ASCII)' -f $f.Name, $bad.Count) }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty -Because 'source must be ASCII-only; use - not em-dash. If non-ASCII is truly required, the file must have a UTF-8 BOM and this test updated deliberately.'
    }

    It 'no source file carries a UTF-8 BOM' {
        # The ASCII test above reads with [Text.Encoding]::UTF8, which SILENTLY
        # CONSUMES a leading BOM - so it can never see one. 48 files had drifted
        # to BOM-prefixed before anyone noticed. This check reads raw bytes.
        #
        # build.ps1 strips BOMs when concatenating, so a BOM here does not reach
        # the artifact; the reason to keep source clean is that the standard is
        # UTF-8 without BOM, and a BOM is one build-path change away from
        # becoming a real defect (a stray ZWNBSP mid-artifact).
        $repoRoot  = Split-Path $PSScriptRoot -Parent
        $scanRoots = @('src', 'tests', 'tools') |
            ForEach-Object { Join-Path $repoRoot $_ } |
            Where-Object   { Test-Path -LiteralPath $_ }

        $offenders = @()
        foreach ($f in (Get-ChildItem $scanRoots -Recurse -Include *.ps1, *.psd1 -File)) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($bytes.Length -ge 3 -and
                $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $offenders += $f.FullName.Substring($repoRoot.Length).TrimStart('\')
            }
        }
        $offenders -join '; ' | Should -BeNullOrEmpty -Because 'scripts must be saved as UTF-8 without BOM'
    }
}
