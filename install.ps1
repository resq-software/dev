# Copyright 2026 ResQ Software
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
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

$ScriptVersion  = '0.2.0'
$Org            = 'resq-software'
$NixInstallUrl  = 'https://install.determinate.systems/nix'

# ── Platform flag ────────────────────────────────────────────────────────────

$IsNativeWindows = $IsWindows -or (-not $IsLinux -and -not $IsMacOS -and
    [System.Environment]::OSVersion.Platform -eq 'Win32NT')

# ── Utility functions ────────────────────────────────────────────────────────

function Write-Info { param([string]$Msg) Write-Host "info  $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  ok  $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "warn  $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "fail  $Msg" -ForegroundColor Red; exit 1 }

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-MinVersion {
    param(
        [string]$Tool,
        [string]$Actual,
        [string]$Minimum,
        [string]$Url
    )
    $cleanActual  = ($Actual  -replace '[^0-9.]', '').Trim('.')
    $cleanMinimum = ($Minimum -replace '[^0-9.]', '').Trim('.')

    $aParts = $cleanActual.Split('.')
    $mParts = $cleanMinimum.Split('.')

    $len = [Math]::Max($aParts.Length, $mParts.Length)
    for ($i = 0; $i -lt $len; $i++) {
        $a = if ($i -lt $aParts.Length) { [int]$aParts[$i] } else { 0 }
        $m = if ($i -lt $mParts.Length) { [int]$mParts[$i] } else { 0 }
        if ($a -gt $m) { return }
        if ($a -lt $m) {
            Write-Warn "$Tool $Actual is below recommended minimum $Minimum — upgrade: $Url"
            return
        }
    }
}

function Confirm-Action {
    param([string]$Message)
    if ($env:YES -eq '1') { return $true }
    $answer = Read-Host "$Message [y/N]"
    return ($answer -match '^[yY]([eE][sS])?$')
}

# ── Step functions ───────────────────────────────────────────────────────────

function Get-Platform {
    $script:IsWSL = $false
    if ($IsLinux) {
        if (Test-Path /proc/version) {
            $procVersion = Get-Content /proc/version -Raw
            if ($procVersion -match 'microsoft|WSL') { $script:IsWSL = $true }
        }
    }

    if ($IsNativeWindows) {
        $script:Platform = "Windows $([System.Environment]::OSVersion.Version)"
        $script:Arch = if ([System.Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    }
    elseif ($IsMacOS) {
        $script:Platform = 'macOS'
        $script:Arch = (uname -m)
    }
    elseif ($IsLinux) {
        $script:Platform = if ($script:IsWSL) { 'WSL/Linux' } else { 'Linux' }
        $script:Arch = (uname -m)
    }
    else {
        Write-Fail 'Unsupported platform. ResQ requires Windows, Linux, or macOS.'
    }

    Write-Info "Detected $script:Platform ($script:Arch)"
}

function Assert-Git {
    if (-not (Test-Command 'git')) {
        if ($IsNativeWindows) {
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
    $gitVersion = (git --version) -replace 'git version ', ''
    Write-Ok "git $gitVersion"
    Test-MinVersion 'git' $gitVersion '2.0' 'https://git-scm.com/downloads'
}

function Install-GitHubCLI {
    if (-not (Test-Command 'gh')) {
        Write-Warn 'gh (GitHub CLI) not found — installing...'
        if ($IsNativeWindows) {
            winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements
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
    $ghVersion = ((gh --version | Select-Object -First 1) -replace '[^0-9.]', '').Trim('.')
    Write-Ok "gh $ghVersion"
    Test-MinVersion 'gh' $ghVersion '2.0' 'https://cli.github.com'
}

function Connect-GitHub {
    $authOk = $false
    try {
        gh auth status 2>&1 | Out-Null
        $authOk = $true
    }
    catch { }

    if (-not $authOk) {
        Write-Info 'Not logged in to GitHub — starting auth...'
        gh auth login
    }
    $ghUser = try { gh api user --jq '.login' 2>$null } catch { 'unknown' }
    Write-Ok "GitHub authenticated as $ghUser"
}

function Install-Nix {
    if (-not (Test-Command 'nix')) {
        if ($IsNativeWindows) {
            Write-Info 'Nix is not natively supported on Windows.'
            Write-Info 'If you are using WSL, run this script inside your WSL distribution.'
            Write-Info 'Skipping Nix installation — you can still clone repos below.'
            return
        }

        if (-not (Confirm-Action 'Install Nix package manager?')) {
            Write-Warn 'Skipping Nix install — some repos require Nix for their dev environment.'
            return
        }

        Write-Info 'Installing Nix via Determinate Systems installer...'
        bash -c "curl --proto '=https' --tlsv1.2 -sSf -L '$NixInstallUrl' | sh -s -- install"

        # Source nix in current shell
        if (Test-Path '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh') {
            bash -c '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && echo $PATH' |
                ForEach-Object { $env:PATH = $_ }
        }
        elseif (Test-Path "$HOME/.nix-profile/etc/profile.d/nix.sh") {
            bash -c ". $HOME/.nix-profile/etc/profile.d/nix.sh && echo \$PATH" |
                ForEach-Object { $env:PATH = $_ }
        }
    }

    if (Test-Command 'nix') {
        $nixVer = ((nix --version 2>$null) -replace '[^0-9.]', '').Trim('.')
        Write-Ok "nix $nixVer"
    }
    elseif (-not $IsNativeWindows) {
        Write-Warn 'Nix installed but not in PATH. Restart your shell and re-run this script.'
        exit 0
    }
}

function Select-Repo {
    Write-Host ''
    Write-Host '  Which repo do you want to work on?' -ForegroundColor White
    Write-Host ''
    Write-Host '  ' -NoNewline; Write-Host ' 1' -ForegroundColor Cyan -NoNewline; Write-Host '  resQ          Platform monorepo (private)'
    Write-Host '  ' -NoNewline; Write-Host ' 2' -ForegroundColor Cyan -NoNewline; Write-Host '  programs      Solana/Anchor on-chain programs'
    Write-Host '  ' -NoNewline; Write-Host ' 3' -ForegroundColor Cyan -NoNewline; Write-Host '  dotnet-sdk    .NET client libraries'
    Write-Host '  ' -NoNewline; Write-Host ' 4' -ForegroundColor Cyan -NoNewline; Write-Host '  pypi          Python packages (MCP + DSA)'
    Write-Host '  ' -NoNewline; Write-Host ' 5' -ForegroundColor Cyan -NoNewline; Write-Host '  crates        Rust workspace (CLI + DSA)'
    Write-Host '  ' -NoNewline; Write-Host ' 6' -ForegroundColor Cyan -NoNewline; Write-Host '  npm           TypeScript packages (UI + DSA)'
    Write-Host '  ' -NoNewline; Write-Host ' 7' -ForegroundColor Cyan -NoNewline; Write-Host '  vcpkg         C++ libraries'
    Write-Host '  ' -NoNewline; Write-Host ' 8' -ForegroundColor Cyan -NoNewline; Write-Host '  landing       Marketing site'
    Write-Host '  ' -NoNewline; Write-Host ' 9' -ForegroundColor Cyan -NoNewline; Write-Host '  cms           Content management'
    Write-Host '  ' -NoNewline; Write-Host '10' -ForegroundColor Cyan -NoNewline; Write-Host '  docs          Documentation site'
    Write-Host ''
    $choice = Read-Host '  Choice [1-10]'

    $script:Repo = switch ($choice) {
        '1'  { 'resQ' }
        '2'  { 'programs' }
        '3'  { 'dotnet-sdk' }
        '4'  { 'pypi' }
        '5'  { 'crates' }
        '6'  { 'npm' }
        '7'  { 'vcpkg' }
        '8'  { 'landing' }
        '9'  { 'cms' }
        '10' { 'docs' }
        default { Write-Fail "Invalid choice: $choice" }
    }
}

function Clone-Repo {
    $script:BaseDir   = if ($env:RESQ_DIR) { $env:RESQ_DIR } else { Join-Path $HOME 'resq' }
    $script:TargetDir = Join-Path $script:BaseDir $script:Repo

    if (Test-Path (Join-Path $script:TargetDir '.git')) {
        if (Confirm-Action "$($script:TargetDir) already exists — pull latest?") {
            Write-Info 'Pulling latest changes...'
            git -C $script:TargetDir pull --ff-only 2>$null
        }
    }
    else {
        Write-Info "Cloning $Org/$($script:Repo) into $($script:TargetDir)"
        $parentDir = Split-Path $script:TargetDir -Parent
        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
        gh repo clone "$Org/$($script:Repo)" $script:TargetDir
    }

    Write-Ok "Repository ready at $($script:TargetDir)"
}

function Initialize-Repo {
    if (Test-Path (Join-Path $script:TargetDir 'flake.nix')) {
        if (Test-Command 'nix') {
            Write-Info 'Nix flake detected — building dev environment (first run may take a few minutes)...'
            nix develop $script:TargetDir --command echo 'Environment ready' 2>$null
        }
    }

    $hookScript = Join-Path $script:TargetDir 'tools/scripts/setup-hooks.sh'
    if (Test-Path $hookScript) {
        Write-Info 'Setting up git hooks...'
        Push-Location $script:TargetDir
        try { bash tools/scripts/setup-hooks.sh 2>$null } catch { }
        Pop-Location
        Write-Ok 'Git hooks configured'
    }
}

function Show-RepoInfo {
    switch ($script:Repo) {
        'resQ' {
            Write-Host ''
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
            Write-Host '    resq CLI      — audit, health checks, log viewer, perf monitor'
            Write-Host '    make test     — run all tests across all languages'
            Write-Host '    make build    — build all services'
            Write-Host '    make dev      — start dev servers'
            Write-Host '    make lint     — lint everything'
            Write-Host ''
        }
        'programs' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Solana CLI, Anchor framework, Rust toolchain'
            Write-Host '    make anchor-build, make anchor-test'
            Write-Host ''
        }
        'pypi' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Python 3.11-3.13, uv, ruff, mypy'
            Write-Host '    Packages: resq-mcp, resq-dsa'
            Write-Host '    90% test coverage gate enforced'
            Write-Host ''
        }
        'crates' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Rust toolchain, clippy, cargo-deny'
            Write-Host '    Workspace: 9+ crates including CLI tools and resq-dsa'
            Write-Host ''
        }
        'npm' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Bun, TypeScript, React 19, Storybook, Chromatic'
            Write-Host '    Packages: @resq-sw/ui (55+ components), @resq-sw/dsa'
            Write-Host '    Biome linter'
            Write-Host ''
        }
        'vcpkg' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    C++ toolchain, CMake, clang-format'
            Write-Host '    Header-only library: resq-common'
            Write-Host ''
        }
        'cms' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    TypeScript, pnpm, Wrangler'
            Write-Host '    Deploys to Cloudflare Workers'
            Write-Host ''
        }
        'docs' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Mintlify docs site'
            Write-Host '    npx mint dev for local preview'
            Write-Host ''
        }
    }
}

# ── Main ─────────────────────────────────────────────────────────────────────

function Main {
    Write-Host ''
    Write-Host "  ResQ Developer Setup v$ScriptVersion" -ForegroundColor White
    Write-Host '  ─────────────────────────────'
    Write-Host ''

    Get-Platform
    Assert-Git
    Install-GitHubCLI
    Connect-GitHub
    Install-Nix
    Select-Repo
    Clone-Repo
    Initialize-Repo
    Show-RepoInfo

    Write-Host '  Ready!' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Get started:' -ForegroundColor White
    Write-Host ''
    Write-Host "    cd $($script:TargetDir)"

    if (Test-Path (Join-Path $script:TargetDir 'flake.nix')) {
        Write-Host '    nix develop'
    }
    if (Test-Path (Join-Path $script:TargetDir 'Makefile')) {
        Write-Host '    make help'
    }

    Write-Host ''
}

Main
