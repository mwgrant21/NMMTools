# Output layer. Tools never call Write-Host/Read-Host directly; they use
# Write-ToolOutput and Read-ToolChoice so console, log, and silent modes
# are one code path. (Replaces the v8 GUI's Write-Host-override hack.)

$script:OutputSink      = 'Console'
$script:LogFilePath     = $null
$script:GuiSync         = $null
$script:CaptureBuffer   = $null
$script:CapturePrevSink = $null
$script:CapturePrevLog  = $null

function Set-OutputSink {
    param(
        [Parameter(Mandatory)][ValidateSet('Console','Silent','GUI','Pdq')][string]$Sink,
        [string]$LogDirectory
    )
    if ($LogDirectory) {
        if (-not (Test-Path $LogDirectory -PathType Container)) {
            New-Item -ItemType Directory -Force $LogDirectory | Out-Null
        }
        $name = 'NMMTools-{0}-{1:yyyyMMdd-HHmmss}.log' -f $env:COMPUTERNAME, (Get-Date)
        $script:LogFilePath = Join-Path $LogDirectory $name
    } else {
        $script:LogFilePath = $null
    }
    $script:OutputSink = $Sink
}

function Write-ToolOutput {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info','Success','Warning','Error','Detail')][string]$Level = 'Info'
    )
    if ($script:LogFilePath) {
        $line = '[{0:HH:mm:ss}] [{1,-7}] {2}' -f (Get-Date), $Level, $Message
        try {
            Add-Content -Path $script:LogFilePath -Value $line -ErrorAction Stop
        } catch {
            # Logging must never take down a tool run on a broken machine;
            # drop the log line and keep going.
        }
    }
    if ($script:OutputSink -eq 'Console') {
        $color = switch ($Level) {
            'Success' { 'Green' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            'Detail'  { 'Gray' }
            default   { 'White' }
        }
        Write-Host $Message -ForegroundColor $color
    } elseif ($script:OutputSink -eq 'Pdq') {
        # PDQ Deploy captures the step's stdout. [Console]::Out writes to process
        # stdout directly, which is redirect-safe in every host - including hosts
        # with no console UI, where Write-Host has nowhere to go. It also never
        # touches the pipeline: Invoke-NmmTool ends with 'return $run.Status', so
        # emitting log lines on the success stream (Write-Output) would fold them
        # into that return value and corrupt any status-to-exit-code mapping.
        # The fixed-width level prefix also makes captured lines greppable.
        [Console]::Out.WriteLine(('[{0,-7}] {1}' -f $Level, $Message))
    } elseif ($script:OutputSink -eq 'GUI') {
        # Marshal DATA, never a scriptblock. A scriptblock built here would carry
        # this (tool) Runspace's affinity; when the UI thread tried to run it,
        # PowerShell would route it back to the busy tool Runspace and drop it -
        # which is why early GUI output never rendered. Instead we enqueue a plain
        # record; a DispatcherTimer on the UI thread drains the queue and builds
        # the WPF elements there (see Start-GuiMenuSTA / Add-GuiOutputRecord).
        $script:GuiSync.OutputQueue.Enqueue([PSCustomObject]@{
            Ts      = Get-Date -Format 'HH:mm:ss'
            Message = $Message
            Level   = $Level
        })
    } elseif ($script:OutputSink -eq 'Capture') {
        [void]$script:CaptureBuffer.AppendLine($Message)
    }
}

function Start-ToolOutputCapture {
    # Redirects Write-ToolOutput into an in-memory buffer instead of the
    # console/log/GUI sink, so a caller (e.g. the diagnostic bundle) can run
    # another tool and collect its raw text without touching the console.
    $script:CapturePrevSink = $script:OutputSink
    $script:CapturePrevLog  = $script:LogFilePath
    $script:CaptureBuffer   = New-Object System.Text.StringBuilder
    $script:OutputSink      = 'Capture'
    $script:LogFilePath     = $null
}

function Stop-ToolOutputCapture {
    # Returns the buffered text and restores the sink/log path that were
    # active before Start-ToolOutputCapture was called.
    $text = ''
    if ($script:CaptureBuffer) { $text = $script:CaptureBuffer.ToString() }
    $script:OutputSink    = $script:CapturePrevSink
    $script:LogFilePath   = $script:CapturePrevLog
    $script:CaptureBuffer = $null
    return $text
}

function Read-ToolChoice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [ValidateCount(1,100)][string[]]$Choices = @('Yes','No'),
        [Parameter(Mandatory)][string]$Default,
        [switch]$Silent,
        # Console path only: require an exact, case-sensitive match against a
        # choice name instead of the default prefix-match. Use for destructive
        # confirms where a single leading letter must not select the action
        # (e.g. typing 'R' must not select 'RESET'). GUI and Silent paths are
        # unaffected - a GUI button click is already an explicit selection, and
        # Silent always auto-selects -Default.
        [switch]$ExactMatch
    )
    if ($Choices -notcontains $Default) {
        throw "Read-ToolChoice: Default '$Default' is not one of the choices ($($Choices -join '/'))."
    }
    if ($Silent -or $script:OutputSink -eq 'Silent') {
        Write-ToolOutput "$Prompt -> $Default (auto-selected, silent mode)" -Level Detail
        return $Default
    }
    if ($script:OutputSink -eq 'GUI') {
        # Same affinity rule as Write-ToolOutput: hand the UI thread DATA, not a
        # scriptblock. We publish a pending-prompt record and block on the
        # semaphore; the UI drain timer (Start-GuiMenuSTA) sees the record, builds
        # the choice buttons on the UI thread, and a button click sets the
        # response + releases the semaphore so this Runspace thread resumes.
        $sync = $script:GuiSync
        $sync.PromptResponse = $null
        $sync.PromptRequest  = [PSCustomObject]@{
            Prompt  = $Prompt
            Choices = $Choices
            Default = $Default
        }
        [void]$sync.PromptSemaphore.Wait()
        $response = $sync.PromptResponse
        $sync.PromptResponse = $null
        return $response
    }
    $choiceText = $Choices -join '/'
    while ($true) {
        try {
            $answer = Read-Host "$Prompt [$choiceText] (default: $Default)"
        } catch {
            # Non-interactive host (PDQ, scheduled task): Read-Host throws.
            # Fall back to the declared default instead of crashing the tool.
            Write-ToolOutput "$Prompt -> $Default (auto-selected, non-interactive host)" -Level Detail
            return $Default
        }
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($ExactMatch) {
            $typed = $answer.Trim()
            $hits = @($Choices | Where-Object { $_ -ceq $typed })
            if ($hits.Count -eq 1) { return $hits[0] }
            Write-ToolOutput "Invalid choice. Enter one of: $choiceText (exact match, case-sensitive)" -Level Warning
            continue
        }
        $needle = $answer.Trim().ToLower()
        $hits = @($Choices | Where-Object { $_.ToLower().StartsWith($needle) })
        if ($hits.Count -eq 1) { return $hits[0] }
        if ($hits.Count -gt 1) {
            Write-ToolOutput ('Ambiguous - did you mean: {0}? Type more letters.' -f ($hits -join ' or ')) -Level Warning
        } else {
            Write-ToolOutput "Invalid choice. Enter one of: $choiceText" -Level Warning
        }
    }
}
