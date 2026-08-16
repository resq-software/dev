# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
# Package-manager abstraction. Requires log.ps1 + platform.ps1.

function Get-PackageManager {
    switch ($script:OsType) {
        'linux' {
            if     (Test-Command 'apt-get') { return 'apt' }
            elseif (Test-Command 'dnf')     { return 'dnf' }
            elseif (Test-Command 'yum')     { return 'yum' }
            elseif (Test-Command 'pacman')  { return 'pacman' }
            elseif (Test-Command 'zypper')  { return 'zypper' }
            elseif (Test-Command 'apk')     { return 'apk' }
            return 'unknown'
        }
        'macos' {
            if (Test-Command 'brew') { return 'brew' } else { return 'none' }
        }
        'windows' {
            if     (Test-Command 'scoop')  { return 'scoop' }
            elseif (Test-Command 'winget') { return 'winget' }
            elseif (Test-Command 'choco')  { return 'choco' }
            return 'none'
        }
        default { return 'unknown' }
    }
}

# NOT named Install-Package. That is a real cmdlet shipped with PowerShell
# (PackageManagement), and these libraries are dot-sourced into the caller's
# session by shell-utils.ps1 — so defining it here silently replaced the
# built-in for the remainder of that session, for our code and for anything the
# user ran afterwards. Same class of hazard as nvm calling `command grep`:
# never let your own definition shadow the thing callers believe they invoke.
#
# Flagged by PSScriptAnalyzer's PSAvoidOverwritingBuiltInCmdlets.
function Install-SystemPackage {
    param([Parameter(Mandatory)][string]$Package)
    $pm = Get-PackageManager
    switch ($pm) {
        'apt'    { sudo apt-get update -y; sudo apt-get install -y $Package }
        'dnf'    { sudo dnf install -y $Package }
        'yum'    { sudo yum install -y $Package }
        'pacman' { sudo pacman -Sy --noconfirm $Package }
        'zypper' { sudo zypper install -y $Package }
        'apk'    { sudo apk add --no-cache $Package }
        'brew'   { brew install --quiet $Package }
        'scoop'  { scoop install $Package }
        'winget' { winget install --silent --accept-source-agreements --accept-package-agreements --id $Package }
        'choco'  { choco install -y $Package }
        default  { return $false }
    }
    return ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
}

function Install-OsvScanner {
    $pm = Get-PackageManager
    Log-Info "Attempting to install osv-scanner via $pm..."
    if ($pm -eq 'winget') { return (Install-SystemPackage 'Google.OSVScanner') }
    return (Install-SystemPackage 'osv-scanner')
}
