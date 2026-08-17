# Copyright 2026 ResQ Systems, Inc.
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

# $IsWindows/$IsLinux/$IsMacOS are PowerShell 6+ automatic variables and do not
# exist in Windows PowerShell 5.1. StrictMode above turns a read of an unset
# variable into a terminating error, so the chmod branch below (`if ($IsLinux
# -or $IsMacOS)`) threw on 5.1 and hooks were never configured.
#
# Caught by windows-smoke on the run that verified the two OTHER fixes in this
# same file — the smoke job reported "The variable '$IsLinux' cannot be
# retrieved" while every step still passed, because the harness was logging the
# throw instead of failing on it. Both are fixed together.
#
# Same guarded block as install.ps1 and scripts/lib/platform.ps1. This file is
# distributed standalone (curl | sh, and as a ScriptBlock inside install.ps1),
# so it cannot source the library.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $IsWindows = $true
    $IsLinux   = $false
    $IsMacOS   = $false
}

$targetRoot = & git -C $TargetDir rev-parse --show-toplevel 2>$null
if (-not $targetRoot) {
    Write-Host "fail  Not a git repository: $TargetDir" -ForegroundColor Red
    # throw, not exit. Fourth and last instance in this file: under install.ps1
    # this runs as a ScriptBlock, where `exit 1` kills the installer outright
    # and, under `irm | iex`, the caller's session — bypassing install.ps1's own
    # error handling entirely. A throw is catchable by the caller and matches
    # this file's existing fatal idiom below.
    throw 'not a git repository'
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
    # ── Path 2: fetch from crates templates, pinned and verified ────────────
    #
    # These become executables git runs on every commit and push, so they get
    # the same treatment as the installer itself: a pinned commit, a digest
    # check, and failure closed.
    #
    # This previously fetched from a mutable branch with no verification, and it
    # is the DEFAULT path: install.ps1 installs the resq binary *after* calling
    # this script, so a fresh machine never has resq on PATH here.
    $hooks = @('pre-commit','commit-msg','prepare-commit-msg','pre-push','post-checkout','post-merge')

    # Pinned commit in resq-software/crates. Keep in step with the digests below
    # and with scripts/install-hooks.sh; required.yml re-checks all three
    # against the live endpoint, so drift fails CI rather than a user's install.
    $cratesCommit = 'd84cd9613da685ffb772a766673d6ba6a4acaf31'
    $hookDigests = @{
        'pre-commit'         = '540c19f96fe258df6d90a8357b27513657b380567650ce3aaed83efa216a64ee'
        'commit-msg'         = 'e7fa95d5d54f212ef145ae9d53cae08b24b0f9dbd5501fde1dae0aa4ddfeb2a6'
        'prepare-commit-msg' = '4fa2e7abf284adc93da750b9c4387de781dd552874290c81885c5dc19debe99b'
        'pre-push'           = '85677f87b30220a443e00191e8267998f62c83642127311c72efe841aab72c79'
        'post-checkout'      = '2a894cf301bd487494d57f39159de07b79f608beeece349de5a4bdc0b5a11480'
        'post-merge'         = 'b05e2ecacb5c342b3fc3525987ad73dc700079bfe7fd5bf7eac67461ea77cfbb'
    }

    # -Ref still works, but pinned digests cannot describe an arbitrary ref, so
    # overriding it means opting out of verification explicitly. Without this, a
    # parameter silently chose which executables got installed.
    $fetchRef = $cratesCommit
    $verify = $true
    if ($Ref -ne 'master') {
        if ($env:RESQ_ALLOW_UNVERIFIED -eq '1') {
            Write-Host "warn  Ref '$Ref' overrides the pinned commit; digests cannot be checked." -ForegroundColor Yellow
            $fetchRef = $Ref
            $verify = $false
        } else {
            Write-Host "fail  Ref '$Ref' cannot be verified against the pinned digests." -ForegroundColor Red
            Write-Host "fail  Set RESQ_ALLOW_UNVERIFIED=1 to install unverified hooks deliberately." -ForegroundColor Red
            throw 'refusing to install unverified git hooks'
        }
    }

    $rawBase = "https://raw.githubusercontent.com/resq-software/crates/$fetchRef/crates/resq-cli/templates/git-hooks"
    Write-Host "info  Fetching hooks from $rawBase" -ForegroundColor Cyan

    # Stage in a temp directory so a failed verification cannot leave a
    # half-installed or unverified hook where git is about to execute it.
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        foreach ($h in $hooks) {
            $dest = Join-Path $stage $h
            Invoke-WebRequest -Uri "$rawBase/$h" -OutFile $dest -UseBasicParsing -ErrorAction Stop
            if ($verify) {
                $want = $hookDigests[$h]
                $got  = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($got -ne $want) {
                    Write-Host "fail  Checksum mismatch for $h" -ForegroundColor Red
                    Write-Host "      expected $want" -ForegroundColor Red
                    Write-Host "      got      $got" -ForegroundColor Red
                    throw 'refusing to install unverified git hooks'
                }
            }
        }

        # Publish only once every hook verified, so a mismatch on the last file
        # cannot leave the earlier ones installed and already active.
        foreach ($h in $hooks) {
            Copy-Item -Path (Join-Path $stage $h) -Destination (Join-Path $hooksDir $h) -Force
        }
    }
    finally {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }

    if ($IsLinux -or $IsMacOS) {
        foreach ($h in $hooks) { & chmod +x (Join-Path $hooksDir $h) }
    }
    & git -C $targetRoot config core.hooksPath .git-hooks
    if ($verify) {
        Write-Host "  ok  hooks verified against pinned commit $cratesCommit" -ForegroundColor Green
    }
}

Write-Host "  ok  ResQ hooks installed in $hooksDir" -ForegroundColor Green
Write-Host "      Bypass once:        git commit --no-verify"
Write-Host "      Disable all hooks:  `$env:GIT_HOOKS_SKIP = '1'"
Write-Host "      Add repo logic:     $hooksDir/local-<hook-name>"

# `return`, not `exit`. install.ps1 runs this file as a ScriptBlock
# ([ScriptBlock]::Create over its contents), and `exit` is not scoped to a
# script block — it terminates the ENCLOSING script, and under `irm ... | iex`
# it terminates the caller's session outright.
#
# This branch is the DEFAULT on a fresh machine: install.ps1 installs the resq
# binary *after* running the hook installer, so $resqBin is null on every first
# install. The common path therefore truncated the installer here — no resq
# CLI, no completions, no "Ready!" banner, no next steps — and exited 0.
if (-not $resqBin) {
    Write-Host "warn  resq backend not found. Hooks will soft-skip until you install it:" -ForegroundColor Yellow
    Write-Host "      irm https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-resq.sh | sh"
    Write-Host "      (or) cargo install --git https://github.com/resq-software/crates resq-cli"
    return
}

# ── Local-hook scaffold prompt ──────────────────────────────────────────────
# return, not exit — same reason as above: this file runs as a ScriptBlock
# inside install.ps1, and exit would end the installer rather than this script.
if ((Test-Path (Join-Path $hooksDir 'local-pre-push')) -or $env:RESQ_SKIP_LOCAL_SCAFFOLD) { return }

# Probe for subcommand support; prefer the new path.
& $resqBin hooks scaffold-local --help *> $null
if ($LASTEXITCODE -eq 0) {
    $scaffoldArgs = @('hooks', 'scaffold-local')
} else {
    & $resqBin dev scaffold-local-hook --help *> $null
    # return, not exit — third instance of the same hazard in this file. Under
    # install.ps1 this runs as a ScriptBlock, where exit ends the installer.
    if ($LASTEXITCODE -ne 0) { return }
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
