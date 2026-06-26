# Output layer. Tools never call Write-Host/Read-Host directly; they use
# Write-ToolOutput and Read-ToolChoice so console, log, and silent modes
# are one code path. (Replaces the v8 GUI's Write-Host-override hack.)

$script:OutputSink = 'Console'
$script:LogFilePath = $null
$script:GuiSync     = $null

function Set-OutputSink {
    param(
        [Parameter(Mandatory)][ValidateSet('Console','Silent','GUI')][string]$Sink,
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
    } elseif ($script:OutputSink -eq 'GUI') {
        $capturedTs    = Get-Date -Format 'HH:mm:ss'
        $capturedMsg   = $Message
        $capturedLevel = $Level
        $capturedSync  = $script:GuiSync

        $appendSb = {
            $para = [System.Windows.Documents.Paragraph]::new()
            $para.Margin = [System.Windows.Thickness]::new(0, 0, 0, 1)

            if ($capturedMsg -match '^\={3}') {
                $run = [System.Windows.Documents.Run]::new(('[{0}] {1}' -f $capturedTs, $capturedMsg))
                $run.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.Color]::FromRgb(0x4F, 0xC3, 0xF7))
                $run.FontWeight = [System.Windows.FontWeights]::Bold
                $run.FontSize   = 13
                $para.Inlines.Add($run)
            } else {
                $tsRun = [System.Windows.Documents.Run]::new(('[{0}] ' -f $capturedTs))
                $tsRun.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.Color]::FromRgb(0x50, 0x50, 0x50))

                $msgColor = switch ($capturedLevel) {
                    'Success' { [System.Windows.Media.Color]::FromRgb(0x4E, 0xC9, 0x4E) }
                    'Warning' { [System.Windows.Media.Color]::FromRgb(0xFF, 0xCA, 0x28) }
                    'Error'   { [System.Windows.Media.Color]::FromRgb(0xF4, 0x47, 0x47) }
                    'Detail'  { [System.Windows.Media.Color]::FromRgb(0x80, 0x80, 0x80) }
                    default   { [System.Windows.Media.Color]::FromRgb(0xDC, 0xDC, 0xDC) }
                }
                $msgRun = [System.Windows.Documents.Run]::new($capturedMsg)
                $msgRun.Foreground = [System.Windows.Media.SolidColorBrush]::new($msgColor)
                $para.Inlines.Add($tsRun)
                $para.Inlines.Add($msgRun)
            }

            if ($capturedSync.OutputBox.Document.Blocks.Count -gt 3000) {
                $oldest = $capturedSync.OutputBox.Document.Blocks.FirstBlock
                if ($oldest) { [void]$capturedSync.OutputBox.Document.Blocks.Remove($oldest) }
            }

            [void]$capturedSync.OutputBox.Document.Blocks.Add($para)

            if ($capturedSync.AutoScrollEnabled) {
                $capturedSync.OutputBox.ScrollToEnd()
            } else {
                $capturedSync.ScrollToBottomButton.Visibility = [System.Windows.Visibility]::Visible
            }
        }.GetNewClosure()

        [void]$capturedSync.Dispatcher.InvokeAsync(
            [System.Action]$appendSb,
            [System.Windows.Threading.DispatcherPriority]::Background)
    }
}

function Read-ToolChoice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [ValidateCount(1,100)][string[]]$Choices = @('Yes','No'),
        [Parameter(Mandatory)][string]$Default,
        [switch]$Silent
    )
    if ($Choices -notcontains $Default) {
        throw "Read-ToolChoice: Default '$Default' is not one of the choices ($($Choices -join '/'))."
    }
    if ($Silent -or $script:OutputSink -eq 'Silent') {
        Write-ToolOutput "$Prompt -> $Default (auto-selected, silent mode)" -Level Detail
        return $Default
    }
    if ($script:OutputSink -eq 'GUI') {
        $capturedSync    = $script:GuiSync
        $capturedPrompt  = $Prompt
        $capturedChoices = $Choices
        $capturedDefault = $Default

        $showSb = {
            $capturedSync.PromptTextBlock.Text    = $capturedPrompt
            $capturedSync.PromptDefaultLabel.Text = "(default: $capturedDefault)"
            [void]$capturedSync.ChoiceButtonsPanel.Children.Clear()
            foreach ($choice in $capturedChoices) {
                $btn        = [System.Windows.Controls.Button]::new()
                $btn.Content = $choice
                $btn.Margin  = [System.Windows.Thickness]::new(4, 2, 4, 2)
                $btn.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
                if ($choice -eq $capturedDefault) {
                    $btn.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(0x4F, 0xC3, 0xF7))
                    $btn.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(0x0C, 0x0C, 0x0C))
                } else {
                    $btn.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(0x3E, 0x3E, 0x42))
                    $btn.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xCC))
                }
                $capturedChoice = $choice
                $btn.Add_Click({
                    $capturedSync.PromptResponse = $capturedChoice
                    $capturedSync.PromptArea.Visibility = [System.Windows.Visibility]::Collapsed
                    [void]$capturedSync.PromptSemaphore.Release()
                }.GetNewClosure())
                [void]$capturedSync.ChoiceButtonsPanel.Children.Add($btn)
            }
            $capturedSync.PromptArea.Visibility = [System.Windows.Visibility]::Visible
        }.GetNewClosure()

        [void]$capturedSync.Dispatcher.InvokeAsync([System.Action]$showSb,
            [System.Windows.Threading.DispatcherPriority]::Normal)

        [void]$capturedSync.PromptSemaphore.Wait()
        $response = $capturedSync.PromptResponse
        $capturedSync.PromptResponse = $null
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
