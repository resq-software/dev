# Copyright 2026 ResQ Software
# SPDX-License-Identifier: Apache-2.0
#
# Install canonical ResQ git hooks into a repository (PowerShell mirror).
#
# Usage (local — from dev/):
#     .\scripts\install-hooks.ps1 [-TargetDir <path>]
#
# Usage (curl-piped):
#     cd <repo>
#     irm https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-hooks.ps1 | iex

[CmdletBinding()]
param(
    [string]$TargetDir = $PWD,
    [string]$Ref       = $(if ($env:RESQ_DEV_REF) { $env:RESQ_DEV_REF } else { 'main' })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetRoot = & git -C $TargetDir rev-parse --show-toplevel 2>$null
if (-not $targetRoot) {
    Write-Host "fail  Not a git repository: $TargetDir" -ForegroundColor Red
    exit 1
}
$hooksDir = Join-Path $targetRoot '.git-hooks'
if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null }

$hooks = @('pre-commit','commit-msg','prepare-commit-msg','pre-push','post-checkout','post-merge')

$scriptDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $null }
$localSource = if ($scriptDir) { Join-Path $scriptDir 'git-hooks' } else { $null }

if ($localSource -and (Test-Path $localSource)) {
    Write-Host "info  Installing hooks from $localSource" -ForegroundColor Cyan
    foreach ($h in $hooks) {
        Copy-Item (Join-Path $localSource $h) (Join-Path $hooksDir $h) -Force
    }
} else {
    $rawBase = "https://raw.githubusercontent.com/resq-software/dev/$Ref/scripts/git-hooks"
    Write-Host "info  Fetching hooks from $rawBase" -ForegroundColor Cyan
    foreach ($h in $hooks) {
        Invoke-WebRequest -Uri "$rawBase/$h" -OutFile (Join-Path $hooksDir $h) -UseBasicParsing
    }
}

# chmod +x on non-Windows.
if ($IsLinux -or $IsMacOS) {
    foreach ($h in $hooks) { & chmod +x (Join-Path $hooksDir $h) }
}

& git -C $targetRoot config core.hooksPath .git-hooks

Write-Host "  ok  ResQ hooks installed in $hooksDir" -ForegroundColor Green
Write-Host "      Bypass once:        git commit --no-verify"
Write-Host "      Disable all hooks:  `$env:GIT_HOOKS_SKIP = '1'"
Write-Host "      Add repo logic:     $hooksDir/local-<hook-name>"

$hasResq = ($null -ne (Get-Command resq -ErrorAction SilentlyContinue)) -or
           (Test-Path (Join-Path $HOME '.cargo/bin/resq'))
if (-not $hasResq) {
    Write-Host "warn  resq backend not found. Hooks will soft-skip until you install it:" -ForegroundColor Yellow
    Write-Host "      nix develop    (if your flake provides it)"
    Write-Host "      cargo install --git https://github.com/resq-software/crates resq-cli"
}
