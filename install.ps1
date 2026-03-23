# Copyright 2026 ResQ Software
# Licensed under the Apache License, Version 2.0
#
# Usage:
#   irm https://raw.githubusercontent.com/resq-software/dev/main/install.ps1 | iex
#
# Or inspect first:
#   irm https://raw.githubusercontent.com/resq-software/dev/main/install.ps1 -OutFile install.ps1
#   Get-Content install.ps1
#   .\install.ps1

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ────────────────────────────────────────────────────────────────

$Org = 'resq-software'
$NixInstallUrl = 'https://install.determinate.systems/nix'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info  { param([string]$Msg) Write-Host "info  $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "  ok  $Msg" -ForegroundColor Green }
function Write-Warn  { param([string]$Msg) Write-Host "warn  $Msg" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Msg) Write-Host "fail  $Msg" -ForegroundColor Red; exit 1 }

function Test-Command { param([string]$Name) $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }

# ── Main ─────────────────────────────────────────────────────────────────────

function Main {
    Write-Host ''
    Write-Host '  ResQ Developer Setup' -ForegroundColor White -NoNewline
    Write-Host ''
    Write-Host '  ─────────────────────'
    Write-Host ''

    # ── Detect OS ────────────────────────────────────────────────────────────

    $IsWSL = $false
    if ($IsLinux) {
        if (Test-Path /proc/version) {
            $ProcVersion = Get-Content /proc/version -Raw
            if ($ProcVersion -match 'microsoft|WSL') { $IsWSL = $true }
        }
    }

    if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS -and [System.Environment]::OSVersion.Platform -eq 'Win32NT')) {
        $Platform = "Windows $([System.Environment]::OSVersion.Version)"
        $Arch = if ([System.Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    }
    elseif ($IsMacOS) {
        $Platform = "macOS"
        $Arch = (uname -m)
    }
    elseif ($IsLinux) {
        $Platform = if ($IsWSL) { "WSL/Linux" } else { "Linux" }
        $Arch = (uname -m)
    }
    else {
        Write-Fail "Unsupported platform. ResQ requires Windows, Linux, or macOS."
    }
    Write-Info "Detected $Platform ($Arch)"

    # ── Git ──────────────────────────────────────────────────────────────────

    if (-not (Test-Command 'git')) {
        if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
            Write-Warn 'git not found — attempting install via winget...'
            winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
            $env:PATH = "$env:PATH;$env:ProgramFiles\Git\cmd"
            if (-not (Test-Command 'git')) {
                Write-Fail 'git install failed. Install manually: https://git-scm.com/downloads'
            }
        }
        else {
            Write-Fail 'git is required. Install it first: https://git-scm.com/downloads'
        }
    }
    $GitVersion = (git --version) -replace 'git version ', ''
    Write-Ok "git $GitVersion"

    # ── GitHub CLI ───────────────────────────────────────────────────────────

    if (-not (Test-Command 'gh')) {
        Write-Warn 'gh (GitHub CLI) not found — installing...'
        if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
            winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                         [System.Environment]::GetEnvironmentVariable('PATH', 'User')
            if (-not (Test-Command 'gh')) {
                Write-Fail 'gh install failed. Install manually: https://cli.github.com'
            }
        }
        elseif ($IsMacOS) {
            if (Test-Command 'brew') {
                brew install gh
            }
            else {
                Write-Fail 'Install Homebrew first (https://brew.sh) or install gh manually'
            }
        }
        elseif ($IsLinux) {
            if (Test-Command 'apt-get') {
                bash -c 'curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && sudo apt-get update && sudo apt-get install -y gh'
            }
            elseif (Test-Command 'dnf') { sudo dnf install -y gh }
            elseif (Test-Command 'pacman') { sudo pacman -S --noconfirm github-cli }
            else { Write-Fail 'Cannot auto-install gh. Install manually: https://cli.github.com' }
        }
    }
    $GhVersion = ((gh --version | Select-Object -First 1) -replace '[^0-9.]', '').Trim('.')
    Write-Ok "gh $GhVersion"

    # ── GitHub Auth ──────────────────────────────────────────────────────────

    $AuthOk = $false
    try { gh auth status 2>&1 | Out-Null; $AuthOk = $true } catch {}
    if (-not $AuthOk) {
        Write-Info 'Not logged in to GitHub — starting auth...'
        gh auth login
    }
    $GhUser = try { gh api user --jq '.login' 2>$null } catch { 'unknown' }
    Write-Ok "GitHub authenticated as $GhUser"

    # ── Nix ──────────────────────────────────────────────────────────────────

    if (-not (Test-Command 'nix')) {
        if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
            Write-Warn 'Nix is not natively supported on Windows.'
            Write-Info 'If you are using WSL, run this script inside your WSL distribution.'
            Write-Info 'Skipping Nix installation — you can still clone repos below.'
        }
        else {
            Write-Info 'Installing Nix via Determinate Systems installer...'
            bash -c "curl --proto '=https' --tlsv1.2 -sSf -L '$NixInstallUrl' | sh -s -- install"
            # Source nix in current shell
            if (Test-Path '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh') {
                bash -c '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && echo $PATH' |
                    ForEach-Object { $env:PATH = $_ }
            }
        }
    }

    if (Test-Command 'nix') {
        $NixVer = ((nix --version 2>$null) -replace '[^0-9.]', '').Trim('.')
        Write-Ok "nix $NixVer"
    }
    elseif (-not ($IsWindows -or (-not $IsLinux -and -not $IsMacOS))) {
        Write-Warn 'Nix installed but not in PATH. Restart your shell and re-run this script.'
        exit 0
    }

    # ── Choose repo ──────────────────────────────────────────────────────────

    Write-Host ''
    Write-Host '  Which repo do you want to work on?' -ForegroundColor White
    Write-Host ''
    Write-Host '  ' -NoNewline; Write-Host '1' -ForegroundColor Cyan -NoNewline; Write-Host '  resQ          Full platform monorepo (private)'
    Write-Host '  ' -NoNewline; Write-Host '2' -ForegroundColor Cyan -NoNewline; Write-Host '  programs      Solana/Anchor on-chain programs'
    Write-Host '  ' -NoNewline; Write-Host '3' -ForegroundColor Cyan -NoNewline; Write-Host '  dotnet-sdk    .NET client libraries'
    Write-Host '  ' -NoNewline; Write-Host '4' -ForegroundColor Cyan -NoNewline; Write-Host '  mcp           MCP server for AI clients'
    Write-Host '  ' -NoNewline; Write-Host '5' -ForegroundColor Cyan -NoNewline; Write-Host '  cli           Rust CLI/TUI tools'
    Write-Host '  ' -NoNewline; Write-Host '6' -ForegroundColor Cyan -NoNewline; Write-Host '  ui            React component library'
    Write-Host '  ' -NoNewline; Write-Host '7' -ForegroundColor Cyan -NoNewline; Write-Host '  landing       Marketing site'
    Write-Host ''
    $Choice = Read-Host '  Choice [1-7]'

    $Repo = switch ($Choice) {
        '1' { 'resQ' }
        '2' { 'programs' }
        '3' { 'dotnet-sdk' }
        '4' { 'mcp' }
        '5' { 'cli' }
        '6' { 'ui' }
        '7' { 'landing' }
        default { Write-Fail "Invalid choice: $Choice" }
    }

    # ── Clone ────────────────────────────────────────────────────────────────

    $BaseDir = if ($env:RESQ_DIR) { $env:RESQ_DIR } else { Join-Path $HOME 'resq' }
    $TargetDir = Join-Path $BaseDir $Repo

    if (Test-Path (Join-Path $TargetDir '.git')) {
        Write-Info "$TargetDir already exists — pulling latest..."
        git -C $TargetDir pull --ff-only 2>$null
    }
    else {
        Write-Info "Cloning $Org/$Repo into $TargetDir"
        $ParentDir = Split-Path $TargetDir -Parent
        if (-not (Test-Path $ParentDir)) { New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null }
        gh repo clone "$Org/$Repo" $TargetDir
    }

    Write-Ok "Repository ready at $TargetDir"

    # ── Post-clone setup ───────────────────────────────────────────────────

    if (Test-Path (Join-Path $TargetDir 'flake.nix')) {
        if (Test-Command 'nix') {
            Write-Info 'Nix flake detected — building dev environment (first run may take a few minutes)...'
            nix develop $TargetDir --command echo 'Environment ready' 2>$null
        }
    }

    # Git hooks
    $HookScript = Join-Path $TargetDir 'tools/scripts/setup-hooks.sh'
    if (Test-Path $HookScript) {
        Write-Info 'Setting up git hooks...'
        Push-Location $TargetDir
        try { bash tools/scripts/setup-hooks.sh 2>$null } catch {}
        Pop-Location
        Write-Ok 'Git hooks configured (pre-commit, pre-push, commit-msg)'
    }
    elseif ((Test-Path (Join-Path $TargetDir 'package.json')) -and
            ((Get-Content (Join-Path $TargetDir 'package.json') -Raw) -match 'setup-hooks')) {
        Write-Info 'Git hooks will be configured on first install'
    }

    # ── Print what you get ─────────────────────────────────────────────────

    Write-Host ''
    Write-Host '  Ready!' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Get started:' -ForegroundColor White
    Write-Host ''
    Write-Host "    cd $TargetDir"

    if (Test-Path (Join-Path $TargetDir 'flake.nix')) {
        Write-Host '    nix develop'
    }

    if (Test-Path (Join-Path $TargetDir 'Makefile')) {
        Write-Host '    make help'
    }

    Write-Host ''

    # Show what's included based on repo
    switch ($Repo) {
        'resQ' {
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '  Toolchain (via Nix)' -ForegroundColor DarkGray
            Write-Host '    Rust, Node/Bun, Python, .NET, C++, CMake, Protobuf'
            Write-Host ''
            Write-Host '  Quality gates (automatic on commit)' -ForegroundColor DarkGray
            Write-Host '    Copyright headers, secret scanning, formatting (Rust/TS/Python/C++/C#)'
            Write-Host '    OSV vulnerability scan, debug statement detection, file size limits'
            Write-Host ''
            Write-Host '  Security workflows (CI)' -ForegroundColor DarkGray
            Write-Host '    OSV scan, dependency review, CodeQL, secret scanning'
            Write-Host '    AI-powered: secrets analysis, security compliance audits'
            Write-Host ''
            Write-Host '  Developer tools' -ForegroundColor DarkGray
            Write-Host '    resq CLI     — audit, health checks, log viewer, perf monitor'
            Write-Host '    make test     — run all tests across all languages'
            Write-Host '    make build    — build all services'
            Write-Host '    make dev      — start dev servers'
            Write-Host '    make lint     — lint everything'
            Write-Host ''
        }
        'programs' {
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Solana CLI, Anchor framework, Rust toolchain'
            Write-Host '    make anchor-build, make anchor-test'
            Write-Host ''
        }
        'mcp' {
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Python 3.11-3.13, uv, ruff, mypy'
            Write-Host '    Pre-commit hooks for formatting + security'
            Write-Host '    90% test coverage threshold enforced'
            Write-Host ''
        }
        'cli' {
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Rust toolchain, clippy, cargo-deny'
            Write-Host '    9 crates: audit, cleanup, deploy, explore, health, logs, tui'
            Write-Host ''
        }
        'ui' {
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Bun, TypeScript, React 19, Storybook, Chromatic'
            Write-Host '    55+ components, Biome linter'
            Write-Host ''
        }
    }
}

Main
