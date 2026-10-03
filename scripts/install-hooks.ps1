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

# ── Is that resq new enough to supply the hooks? ────────────────────────────
# Path 1 installs the templates EMBEDDED in the binary, so an old resq installs
# old hooks. Before resq-cli 0.4.3 (resq-software/crates#206) they carried the
# blanket GIT_HOOKS_SKIP guard, under which a granular-looking
# GIT_HOOKS_SKIP=audit also disabled the secret scan. A binary below this
# floor, or one whose version cannot be read, gets the pinned, digest-verified
# templates from path 2 instead. Keep in step with install-hooks.sh.
$resqMinHooksVersion = [version]'0.4.3'
$resqTemplatesOk = $false
if ($resqBin) {
    $resqVersion = $null
    $versionLine = (& $resqBin --version 2>$null | Select-Object -First 1)
    if ("$versionLine" -match '^resq\S* v?(\d+\.\d+\.\d+)') { $resqVersion = [version]$Matches[1] }
    if ($resqVersion -and $resqVersion -ge $resqMinHooksVersion) {
        $resqTemplatesOk = $true
    } else {
        $shown = if ($resqVersion) { "$resqVersion" } else { '<unreadable>' }
        Write-Host "warn  $resqBin reports version $shown; its embedded hooks predate the granular" -ForegroundColor Yellow
        Write-Host "      GIT_HOOKS_SKIP fix (needs >= $resqMinHooksVersion). Installing the pinned, verified hooks" -ForegroundColor Yellow
        Write-Host "      instead. Upgrade resq too - the new hooks may pass it flags it lacks." -ForegroundColor Yellow
    }
}

# ── Path 1: use resq when present (preferred — offline, no raw fetch) ───────
# Prefer the new `hooks install` path; fall back to `dev install-hooks`
# for binaries built before resq-software/crates#60.
if ($resqTemplatesOk) {
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
    $cratesCommit = '72e0ae4952624ccd5cf39adc632e15b3d91b86c9'
    $hookDigests = @{
        'pre-commit'         = 'fd2d275571d431a8cb897a047176f0da9a096ef76a111a0ef0147bb10ba83ffc'
        'commit-msg'         = 'd33ecc52661d43aabaeae1d789df04c709ece41e37fd224b6940c7639ac2a6ef'
        'prepare-commit-msg' = '4fa2e7abf284adc93da750b9c4387de781dd552874290c81885c5dc19debe99b'
        'pre-push'           = '84f1d08fa54baa592d5cc3519ac85cba69d59bc1d502ca8d821cb8f30dde53ce'
        'post-checkout'      = 'aeacd20d8d42d75586f147f8cf92d5ae68eb0e7c9fbe99f7cd1838904f943180'
        'post-merge'         = '32d3e73e5b894b7a42c21075192262997e7a953b84a18f89901cf579a431ab2c'
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
Write-Host "      Skip one check:     `$env:GIT_HOOKS_SKIP = 'audit'   (or format, versioning,"
Write-Host "                          msg-format, wip-guard, force-push, branch-name, notify,"
Write-Host "                          local - comma-separate to combine)"
Write-Host "      Disable ALL checks: `$env:GIT_HOOKS_SKIP = 'all'"
Write-Host "                          GIT_HOOKS_SKIP is a list of check names, not a boolean."
Write-Host "                          An unrecognised value fails closed, and every skip is"
Write-Host "                          announced - if you saw no banner, nothing was skipped."
Write-Host "                          The secret scan has no token; only the all-off value"
Write-Host "                          (all/1/true/yes/on) or --no-verify disables it."
Write-Host "                          prepare-commit-msg ignores GIT_HOOKS_SKIP entirely."
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
    # The installed pre-commit fails closed without resq (see install-hooks.sh).
    Write-Host "warn  resq backend not found. Until it is installed, pre-commit REFUSES every" -ForegroundColor Yellow
    Write-Host "      commit (no checks can run, so none are waived). Install it:" -ForegroundColor Yellow
    Write-Host "      irm https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-resq.sh | sh"
    Write-Host "      (or) cargo install --git https://github.com/resq-software/crates resq-cli"
    Write-Host "      To commit without it on purpose: `$env:GIT_HOOKS_SKIP = 'all', or git commit --no-verify."
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
