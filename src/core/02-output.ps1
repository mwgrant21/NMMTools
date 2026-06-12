# Output layer. Tools never call Write-Host/Read-Host directly; they use
# Write-ToolOutput and Read-ToolChoice so console, log, and silent modes
# are one code path. (Replaces the v8 GUI's Write-Host-override hack.)

$script:OutputSink = 'Console'
$script:LogFilePath = $null

function Set-OutputSink {
    param(
        [Parameter(Mandatory)][ValidateSet('Console','Silent')][string]$Sink,
        [string]$LogDirectory
    )
    $script:OutputSink = $Sink
    if ($LogDirectory) {
        if (-not (Test-Path $LogDirectory)) {
            New-Item -ItemType Directory -Force $LogDirectory | Out-Null
        }
        $name = 'NMMTools-{0}-{1:yyyyMMdd-HHmmss}.log' -f $env:COMPUTERNAME, (Get-Date)
        $script:LogFilePath = Join-Path $LogDirectory $name
    } else {
        $script:LogFilePath = $null
    }
}

function Write-ToolOutput {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info','Success','Warning','Error','Detail')][string]$Level = 'Info'
    )
    if ($script:LogFilePath) {
        $line = '[{0:HH:mm:ss}] [{1,-7}] {2}' -f (Get-Date), $Level, $Message
        Add-Content -Path $script:LogFilePath -Value $line
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
    }
}

function Read-ToolChoice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string[]]$Choices = @('Yes','No'),
        [Parameter(Mandatory)][string]$Default,
        [switch]$Silent
    )
    if ($Silent -or $script:OutputSink -eq 'Silent') {
        Write-ToolOutput "$Prompt -> $Default (auto-selected, silent mode)" -Level Detail
        return $Default
    }
    $choiceText = $Choices -join '/'
    while ($true) {
        $answer = Read-Host "$Prompt [$choiceText] (default: $Default)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $hit = $Choices | Where-Object { $_ -like "$answer*" } | Select-Object -First 1
        if ($hit) { return $hit }
        Write-ToolOutput "Invalid choice. Enter one of: $choiceText" -Level Warning
    }
}
