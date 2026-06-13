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
}
