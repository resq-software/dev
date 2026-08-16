# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
# Platform detection — OS and architecture normalization.

# $IsWindows/$IsLinux/$IsMacOS are PowerShell 6+ automatic variables and do not
# exist in Windows PowerShell 5.1. Callers of this library set
# `Set-StrictMode -Version Latest` (scripts/setup.ps1), which turns a read of an
# unset variable into a terminating error — so Get-OsType below aborted on 5.1
# instead of falling through to its OSVersion.Platform check.
#
# Defined once here, guarded, so every function in this file keeps reading them
# directly. Windows PowerShell only ever runs on Windows, so the values are not
# in doubt; the guard exists because these are read-only in 6+.
#
# install.ps1 carries the same block: it is a standalone curl-piped script and
# cannot source this file.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $IsWindows = $true
    $IsLinux   = $false
    $IsMacOS   = $false
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-OsType {
    if ($IsWindows -or
        (-not $IsLinux -and -not $IsMacOS -and
         [System.Environment]::OSVersion.Platform -eq 'Win32NT')) {
        return 'windows'
    }
    if ($IsMacOS) { return 'macos' }
    if ($IsLinux) { return 'linux' }
    return 'unknown'
}

function Get-ArchType {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
    switch ($arch) {
        'x64'   { return 'amd64' }
        'arm64' { return 'arm64' }
        'arm'   { return 'arm' }
        default { return $arch }
    }
}

if (-not (Get-Variable -Name OsType   -Scope Script -ErrorAction SilentlyContinue)) { $script:OsType   = Get-OsType }
if (-not (Get-Variable -Name ArchType -Scope Script -ErrorAction SilentlyContinue)) { $script:ArchType = Get-ArchType }
$env:OS_TYPE   = $script:OsType
$env:ARCH_TYPE = $script:ArchType
