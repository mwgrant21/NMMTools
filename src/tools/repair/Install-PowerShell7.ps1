function Install-PowerShell7 {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'powershell7-install'

        $psVer = $PSVersionTable.PSVersion
        Write-ToolOutput ('Current PowerShell version: {0}.{1}.{2}' -f $psVer.Major, $psVer.Minor, $psVer.Build)

        if ($psVer.Major -ge 7) {
            Write-ToolOutput ('PowerShell 7+ is already installed (v{0}.{1}.{2}).' -f $psVer.Major, $psVer.Minor, $psVer.Build)
            Complete-ToolRun $run -Status Success `
                -Summary ('PowerShell {0}.{1}.{2} already installed; no action taken' -f $psVer.Major, $psVer.Minor, $psVer.Build)
            return
        }

        Write-ToolOutput 'PowerShell 7 is not installed on this machine.' -Level Warning
        Write-ToolOutput 'Note: installation also enables PS Remoting (WinRM) on this machine.' -Level Warning

        $choice = Read-ToolChoice `
            -Prompt 'Install/upgrade PowerShell 7? (downloads ~100MB; also enables PS Remoting)' `
            -Choices @('Yes', 'No') `
            -Default 'No' `
            -Silent:$Silent

        if ($choice -ne 'Yes') {
            Complete-ToolRun $run -Status Skipped -Summary 'User declined PowerShell 7 install'
            return
        }

        $installed = $false
        $method    = ''

        # Method 1: winget (preferred)
        Write-ToolOutput 'Attempting install via winget...' -Level Info
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            try {
                $wgProc = Start-Process -FilePath 'winget.exe' `
                    -ArgumentList 'install --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements' `
                    -Wait -PassThru -ErrorAction Stop
                if ($wgProc.ExitCode -eq 0) {
                    $installed = $true
                    $method    = 'winget'
                    Write-ToolOutput 'winget install succeeded (exit 0).' -Level Info
                } else {
                    Write-ToolOutput ('winget exited {0}; trying MSI fallback...' -f $wgProc.ExitCode) -Level Warning
                }
            } catch {
                Write-ToolOutput ('winget failed: {0}; trying MSI fallback...' -f $_.Exception.Message) -Level Warning
            }
        } else {
            Write-ToolOutput 'winget not available; using MSI fallback...' -Level Info
        }

        # Method 2: GitHub MSI fallback
        if (-not $installed) {
            Write-ToolOutput 'Downloading PowerShell 7 MSI from GitHub releases...' -Level Info
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                $apiUrl  = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
                $headers = @{ 'User-Agent' = 'NMMToolkit/9.0' }
                $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop

                $asset = $release.assets | Where-Object {
                    $_.name -match 'win-x64\.msi$' -and $_.name -notmatch 'preview'
                } | Select-Object -First 1

                if (-not $asset) {
                    throw 'Could not locate a win-x64 MSI asset in the latest GitHub release.'
                }

                # Stage under a freshly created, randomly-named, admin-only-ACL'd directory
                # rather than a fixed filename in $env:TEMP (= C:\Windows\Temp under
                # SYSTEM/PDQ, world-writable) - a predictable path lets a standard user
                # pre-create the file and keep DACL control of it even after the download
                # overwrites its contents, opening a swap window before the elevated install.
                $stageDir = Join-Path $env:ProgramData ('NMMTools\stage\{0}' -f ([guid]::NewGuid().ToString('N')))
                New-Item -Path $stageDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                & icacls "$stageDir" /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' /grant:r 'BUILTIN\Administrators:(OI)(CI)F' | Out-Null
                $msiPath = Join-Path $stageDir 'PowerShell7-latest-win-x64.msi'
                Write-ToolOutput ('Downloading: {0}' -f $asset.name) -Level Info

                try {
                    try {
                        Import-Module BitsTransfer -ErrorAction Stop
                        Start-BitsTransfer -Source $asset.browser_download_url -Destination $msiPath `
                            -TransferType Download -ErrorAction Stop
                        Write-ToolOutput 'Download complete via BITS.' -Level Info
                    } catch {
                        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath `
                            -UseBasicParsing -ErrorAction Stop
                        Write-ToolOutput 'Download complete via WebRequest.' -Level Info
                    }

                    $fileSize = (Get-Item $msiPath -ErrorAction SilentlyContinue).Length
                    if (-not $fileSize -or $fileSize -lt 50MB) {
                        throw ('Downloaded MSI appears invalid (size: {0} bytes).' -f $fileSize)
                    }
                    Write-ToolOutput ('File size: {0} MB' -f [math]::Round($fileSize / 1MB, 1)) -Level Detail

                    # A size floor is not an integrity check - verify the file is
                    # Authenticode-signed and actually signed by Microsoft before running it
                    # elevated.
                    $sig = Get-AuthenticodeSignature -FilePath $msiPath
                    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
                        throw ('Downloaded MSI failed signature verification (status: {0}, signer: {1}).' -f $sig.Status, $sig.SignerCertificate.Subject)
                    }
                    Write-ToolOutput 'Authenticode signature verified (Microsoft Corporation).' -Level Detail

                    Write-ToolOutput 'Running silent MSI install...' -Level Info
                    # ENABLE_PSREMOTING=1 previously opened a WinRM listener as an undocumented
                    # side effect of this install path only (the winget path does not enable
                    # it), leaving posture dependent on which branch happened to run. Dropped so
                    # both install paths converge on the same (remoting-off) default.
                    $msiArgs = '/i "{0}" /qn ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 REGISTER_MANIFEST=1' -f $msiPath
                    $proc    = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -ErrorAction Stop
                } finally {
                    Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
                }

                if ($proc.ExitCode -eq 0) {
                    $installed = $true
                    $method    = 'MSI (GitHub)'
                    Write-ToolOutput 'MSI install succeeded (exit 0).' -Level Info
                } else {
                    throw ('msiexec exited {0}.' -f $proc.ExitCode)
                }
            } catch {
                throw ('MSI install failed: {0}' -f $_.Exception.Message)
            }
        }

        if ($installed) {
            Write-ToolOutput ('PowerShell 7 installed via {0}.' -f $method)
            Write-ToolOutput 'Open a new terminal window to use pwsh.exe; this session is still PS 5.1.' -Level Warning
            Write-ToolOutput 'PS Remoting (WinRM) was enabled as part of this installation.' -Level Warning
            Complete-ToolRun $run -Status Success `
                -Summary ('PowerShell 7 installed via {0}; PS Remoting enabled; open a new terminal to use pwsh.exe' -f $method)
        }
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
