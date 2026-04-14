# Logging helpers — Log-Info/Success/Warning/Error.
# Safe to dot-source multiple times.

function Write-LogLine {
    param(
        [Parameter(Mandatory)][System.ConsoleColor]$Color,
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    Write-Host "[$Level]" -ForegroundColor $Color -NoNewline
    Write-Host " $Message"
}

function Log-Info    { param([string]$Msg) Write-LogLine -Color Blue   -Level 'INFO'    -Message $Msg }
function Log-Success { param([string]$Msg) Write-LogLine -Color Green  -Level 'SUCCESS' -Message $Msg }
function Log-Warning { param([string]$Msg) Write-LogLine -Color Yellow -Level 'WARNING' -Message $Msg }
function Log-Error   { param([string]$Msg) Write-LogLine -Color Red    -Level 'ERROR'   -Message $Msg }
