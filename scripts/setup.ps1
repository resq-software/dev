# Copyright 2026 ResQ Systems, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# PowerShell mirror of setup.sh — sets up a ResQ project's local dev environment.
#
# Usage:
#   .\scripts\setup.ps1 [-Check] [-Yes]
#
# Options:
#   -Check   Verify the environment without making changes.
#   -Yes     Auto-confirm all prompts (CI mode).

#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir   = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptDir

. (Join-Path $ScriptDir 'lib/shell-utils.ps1')

if ($Yes) { $env:YES = '1' }

# ── Check mode ───────────────────────────────────────────────────────────────
if ($Check) {
    Log-Info 'Checking ResQ environment...'
    $errors = 0
    if (-not (Test-Command 'nix'))    { Log-Error   'nix not found';                            $errors++ }
    if (-not (Test-Command 'node'))   { Log-Warning 'node not found (run: nix develop)' }
    if (-not (Test-Command 'bun'))    { Log-Warning 'bun not found (run: nix develop)' }
    if (-not (Test-Command 'docker')) { Log-Warning 'docker not found' }

    if (Test-Path (Join-Path $ProjectRoot 'node_modules')) {
        Log-Success 'node_modules present'
    } else {
        Log-Warning 'node_modules missing — run: bun install'
    }

    if ($errors -eq 0) { Log-Success 'Environment looks good.'; exit 0 }
    exit 1
}

# ── Main setup ───────────────────────────────────────────────────────────────
Write-Host '╔══════════════════════════════════════╗'
Write-Host '║  ResQ — Environment Setup            ║'
Write-Host '╚══════════════════════════════════════╝'
Write-Host ''

Install-Nix      | Out-Null
Enter-NixEnv
Install-Docker   | Out-Null

if (Test-Command 'bun') {
    Log-Info 'Installing dependencies...'
    Push-Location $ProjectRoot
    try { bun install } finally { Pop-Location }
    Log-Success 'Dependencies installed.'
} else {
    Log-Warning 'bun not found — run nix develop then bun install (or call Install-Bun).'
}

$installHooks = Join-Path $ScriptDir 'install-hooks.ps1'
if (Test-Path $installHooks) {
    Log-Info 'Installing canonical ResQ git hooks...'
    & $installHooks -TargetDir $ProjectRoot
} else {
    Log-Warning 'install-hooks.ps1 not found — skipping hook setup.'
}

Write-Host ''
Write-Host '╔══════════════════════════════════════════╗'
Write-Host '║  ✓ ResQ setup complete                   ║'
Write-Host '╚══════════════════════════════════════════╝'
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  nix develop                              # Enter dev shell'
Write-Host '  bun dev                                  # Start dev server (port 3000)'
Write-Host '  bun build                                # Production build'
Write-Host '  docker build -t resq-landing .           # Build Docker image'
Write-Host '  docker run -p 3000:3000 resq-landing     # Run container'
