# Interactive prompts and admin guards. Requires log.ps1 + platform.ps1.

function Test-Interactive {
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

function Confirm-Prompt {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('y','n','')] [string]$Default = ''
    )
    if ($env:YES -eq '1') {
        Log-Info "$Message (auto-yes)"
        return $true
    }
    if (-not (Test-Interactive)) { return $false }

    $suffix = '(y/n)'
    if     ($Default -eq 'y') { $suffix = '([y]/n)' }
    elseif ($Default -eq 'n') { $suffix = '(y/[n])' }

    $reply = Read-Host "$Message $suffix"
    if (-not $reply -and $Default) { $reply = $Default }
    return ($reply -match '^[yY]$')
}

function Test-Admin {
    if ($script:OsType -eq 'windows') {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    try { return ([int](& id -u) -eq 0) } catch { return $false }
}

function Assert-Admin {
    if (Test-Admin) { return }
    if ($script:OsType -eq 'windows') {
        Log-Warning 'Some operations require Administrator. Re-launch PowerShell as Administrator.'
    } else {
        Log-Warning 'Some operations require root. You may be prompted for your password.'
    }
}
