# Copyright 2026 ResQ Software
# SPDX-License-Identifier: Apache-2.0
#
# Install canonical ResQ git hooks into a repository (PowerShell mirror).
#
# Canonical hook content is owned by resq-software/crates. This installer:
#   1. Prefers `resq dev install-hooks` when the binary is on PATH (offline,
#      scaffolds from embedded templates, versioned with the user's resq).
#   2. Falls back to fetching templates from crates raw.
#
# Usage (local):
#     .\scripts\install-hooks.ps1 [-TargetDir <path>]
#
# Usage (curl-piped):
#     cd <repo>
#     irm https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-hooks.ps1 | iex

[CmdletBinding()]
param(
    [string]$TargetDir = $PWD,
    [string]$Ref       = $(if ($env:RESQ_CRATES_REF) { $env:RESQ_CRATES_REF } else { 'master' })
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

# ── Resolve resq binary ─────────────────────────────────────────────────────
$resqBin = $null
$onPath = Get-Command resq -ErrorAction SilentlyContinue
if ($onPath) {
    $resqBin = 'resq'
} elseif (Test-Path (Join-Path $HOME '.cargo/bin/resq')) {
    $resqBin = Join-Path $HOME '.cargo/bin/resq'
} elseif (Test-Path (Join-Path $HOME '.cargo/bin/resq.exe')) {
    $resqBin = Join-Path $HOME '.cargo/bin/resq.exe'
}

# ── Path 1: use resq when present (preferred — offline, no raw fetch) ───────
# Prefer the new `hooks install` path; fall back to `dev install-hooks`
# for binaries built before resq-software/crates#60.
if ($resqBin) {
    & $resqBin hooks install --help *> $null
    $installArgs = if ($LASTEXITCODE -eq 0) { @('hooks', 'install') } else { @('dev', 'install-hooks') }
    Write-Host "info  Installing hooks via $resqBin $($installArgs -join ' ')" -ForegroundColor Cyan
    Push-Location $targetRoot
    try { & $resqBin @installArgs } finally { Pop-Location }
} else {
    # ── Path 2: fall back to raw fetch from crates templates ────────────────
    $hooks = @('pre-commit','commit-msg','prepare-commit-msg','pre-push','post-checkout','post-merge')
    $rawBase = "https://raw.githubusercontent.com/resq-software/crates/$Ref/crates/resq-cli/templates/git-hooks"
    Write-Host "info  Fetching hooks from $rawBase" -ForegroundColor Cyan
    foreach ($h in $hooks) {
        Invoke-WebRequest -Uri "$rawBase/$h" -OutFile (Join-Path $hooksDir $h) -UseBasicParsing
    }
    if ($IsLinux -or $IsMacOS) {
        foreach ($h in $hooks) { & chmod +x (Join-Path $hooksDir $h) }
    }
    & git -C $targetRoot config core.hooksPath .git-hooks
}

Write-Host "  ok  ResQ hooks installed in $hooksDir" -ForegroundColor Green
Write-Host "      Bypass once:        git commit --no-verify"
Write-Host "      Disable all hooks:  `$env:GIT_HOOKS_SKIP = '1'"
Write-Host "      Add repo logic:     $hooksDir/local-<hook-name>"

if (-not $resqBin) {
    Write-Host "warn  resq backend not found. Hooks will soft-skip until you install it:" -ForegroundColor Yellow
    Write-Host "      irm https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-resq.sh | sh"
    Write-Host "      (or) cargo install --git https://github.com/resq-software/crates resq-cli"
    exit 0
}

# ── Local-hook scaffold prompt ──────────────────────────────────────────────
if ((Test-Path (Join-Path $hooksDir 'local-pre-push')) -or $env:RESQ_SKIP_LOCAL_SCAFFOLD) { exit 0 }

# Probe for subcommand support; prefer the new path.
& $resqBin hooks scaffold-local --help *> $null
if ($LASTEXITCODE -eq 0) {
    $scaffoldArgs = @('hooks', 'scaffold-local')
} else {
    & $resqBin dev scaffold-local-hook --help *> $null
    if ($LASTEXITCODE -ne 0) { exit 0 }
    $scaffoldArgs = @('dev', 'scaffold-local-hook')
}

$answer = ''
if ($env:YES -eq '1') {
    $answer = 'y'
} elseif ([Environment]::UserInteractive) {
    $answer = Read-Host 'info  Scaffold a repo-specific local-pre-push (auto-detect kind)? [y/N]'
}

if ($answer -match '^[yY]') {
    Push-Location $targetRoot
    try {
        & $resqBin @scaffoldArgs --kind auto
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'warn  scaffold-local failed; run it manually with --kind <name>.' -ForegroundColor Yellow
        }
    } finally { Pop-Location }
}
