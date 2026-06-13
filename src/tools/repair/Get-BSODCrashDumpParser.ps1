function Get-BSODCrashDumpParser {
    [CmdletBinding()]
    param([switch]$Silent)   # required by dispatcher even when unused

    $run = $null
    try {
        $run = New-ToolRun -Id 'bsod-crash-parser'

        $minidumpPath = Join-Path $env:SystemRoot 'Minidump'

        if (-not (Test-Path $minidumpPath)) {
            # No folder = no crashes ever recorded; this is good news
            Complete-ToolRun $run -Status Success -Summary 'No crash dumps found (Minidump folder absent - no BSODs recorded)'
            return
        }

        $dumpFiles = @(Get-ChildItem -Path $minidumpPath -Filter '*.dmp' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)

        if ($dumpFiles.Count -eq 0) {
            Complete-ToolRun $run -Status Success -Summary 'No crash dumps found'
            return
        }

        # Info headline: total dump count before per-file detail rows
        Write-ToolOutput ('{0} crash dump file(s) found in {1}' -f $dumpFiles.Count, $minidumpPath)

        # Known bug-check code table (matches v8 switch statement verbatim)
        $bugDesc = @{
            '0x0000007E' = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED - Driver issue, memory problem, or hardware failure'
            '0x0000007F' = 'UNEXPECTED_KERNEL_MODE_TRAP - Hardware or software compatibility issue'
            '0x00000050' = 'PAGE_FAULT_IN_NONPAGED_AREA - Faulty RAM, driver issue, or corrupted system files'
            '0x000000D1' = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL - Driver problem; check recently installed drivers'
            '0x0000000A' = 'IRQL_NOT_LESS_OR_EQUAL - Driver or hardware incompatibility'
            '0x0000001E' = 'KMODE_EXCEPTION_NOT_HANDLED - Driver or hardware error'
            '0x0000003B' = 'SYSTEM_SERVICE_EXCEPTION - Driver or system file issue'
            '0x000000C2' = 'BAD_POOL_CALLER - Driver bug (bad memory pool caller)'
            '0x00000124' = 'WHEA_UNCORRECTABLE_ERROR - Hardware error; check CPU, RAM, or motherboard'
            '0x00000101' = 'CLOCK_WATCHDOG_TIMEOUT - CPU issue; overheating or hardware problem'
            '0x000000EF' = 'CRITICAL_PROCESS_DIED - Critical system process terminated'
            '0x000000F4' = 'CRITICAL_OBJECT_TERMINATION - Critical system process or service failed'
        }

        $crashInfo  = @()
        $readErrors = 0

        # Per-dump detail rows; one line per file with date, code, and description
        foreach ($dumpFile in $dumpFiles) {
            $bugCheckCode = 'Unknown'
            $bugCheckDesc = 'Unknown bug check code'

            try {
                $fileStream = [System.IO.File]::OpenRead($dumpFile.FullName)
                $buffer     = New-Object byte[] 4096
                $null       = $fileStream.Read($buffer, 0, 4096)
                $fileStream.Close()

                # Scan ASCII bytes for 0x-prefixed uppercase hex strings (v8 regex pattern)
                $fileContent = [System.Text.Encoding]::ASCII.GetString($buffer)
                $bugCheckPattern = '0x[0-9A-F]{1,8}'
                $bugCheckMatches = [regex]::Matches($fileContent, $bugCheckPattern)

                foreach ($match in $bugCheckMatches) {
                    $raw  = $match.Value -replace '0x', ''
                    $norm = '0x' + $raw.PadLeft(8, '0')
                    if ($bugDesc.ContainsKey($norm)) {
                        $bugCheckCode = $norm
                        $bugCheckDesc = $bugDesc[$norm]
                        break
                    }
                }
            } catch {
                # Access-denied or read failure; note gracefully and continue
                $readErrors++
                $bugCheckCode = 'Read Error'
                $bugCheckDesc = ('Could not read file: {0}' -f $_.Exception.Message)
            }

            $crashData = [PSCustomObject]@{
                FileName     = $dumpFile.Name
                Date         = $dumpFile.LastWriteTime
                SizeKB       = [math]::Round($dumpFile.Length / 1KB, 1)
                BugCheckCode = $bugCheckCode
                Description  = $bugCheckDesc
            }
            $crashInfo += $crashData

            Write-ToolOutput ('{0:yyyy-MM-dd HH:mm}  {1}  {2}' -f $dumpFile.LastWriteTime, $bugCheckCode, $bugCheckDesc) -Level Detail
        }

        # Optional report export; default Skip keeps -Silent and unattended runs clean
        $exportChoice = Read-ToolChoice -Prompt 'Export crash dump report to Desktop?' `
            -Choices @('Export', 'Skip') -Default 'Skip' -Silent:$Silent

        if ($exportChoice -eq 'Export') {
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $reportFile  = Join-Path $desktopPath ('BSODCrashDumpReport_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add('BSOD Crash Dump Parser Report')
            $lines.Add(('Generated: {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)))
            $lines.Add('')
            $lines.Add(('Minidump Location : {0}' -f $minidumpPath))
            $lines.Add(('Total Crash Dumps : {0}' -f $dumpFiles.Count))
            $lines.Add('')
            $lines.Add('=== CRASH DUMP DETAILS ===')
            foreach ($c in $crashInfo) {
                $lines.Add(('{0}  {1:yyyy-MM-dd HH:mm}  {2} KB  {3}  {4}' -f
                    $c.FileName, $c.Date, $c.SizeKB, $c.BugCheckCode, $c.Description))
            }
            try {
                $lines | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction Stop
                Write-ToolOutput ('Report: {0}' -f $reportFile)
            } catch {
                Write-ToolOutput ('Report write failed: {0}' -f $_.Exception.Message) -Level Warning
            }
        }

        # Build summary; include latest crash code if known
        $latest = $crashInfo | Where-Object { $_.BugCheckCode -ne 'Unknown' -and $_.BugCheckCode -ne 'Read Error' } |
            Sort-Object Date -Descending | Select-Object -First 1
        $latestNote = if ($latest) { '; latest: {0}' -f $latest.BugCheckCode } else { '' }
        $readNote   = if ($readErrors -gt 0) { '; {0} file(s) unreadable (access denied?)' -f $readErrors } else { '' }

        Complete-ToolRun $run -Status Warning -Summary (
            '{0} crash dump(s) found{1}{2}' -f $dumpFiles.Count, $latestNote, $readNote)
    }
    catch {
        Complete-ToolRun $run -Status Failed -Summary $_.Exception.Message
    }
}
