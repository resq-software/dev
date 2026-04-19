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
[CmdletBinding()]
param(
    # Pre-select a repo for unattended runs. Also honours $env:REPO.
    [string]$Repo = $env:REPO
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ────────────────────────────────────────────────────────────────

$ScriptVersion  = '0.3.0'
$Org            = 'resq-software'
$NixInstallUrl  = 'https://install.determinate.systems/nix'

# Canonical repo list — keep in sync with install.sh and README.md.
$ValidRepos = @('programs','dotnet-sdk','pypi','crates','npm','vcpkg','landing','docs')

# ── Platform flag ────────────────────────────────────────────────────────────

$IsNativeWindows = $IsWindows -or (-not $IsLinux -and -not $IsMacOS -and
    [System.Environment]::OSVersion.Platform -eq 'Win32NT')

# ── Utility functions ────────────────────────────────────────────────────────

function Write-Info { param([string]$Msg) Write-Host "info  $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  ok  $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "warn  $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "fail  $Msg" -ForegroundColor Red; throw $Msg }

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

function Test-Interactive {
    # User-interactive AND a real input stream — rules out CI, piped iex, etc.
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

function Confirm-Action {
    param([string]$Message)
    if ($env:YES -eq '1') { return $true }
    if (-not (Test-Interactive)) { return $false }
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
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Info 'Not logged in to GitHub — starting auth...'
        gh auth login
    }
    $ghUser = try { gh api user --jq '.login' 2>$null } catch { 'unknown' }
    Write-Ok "GitHub authenticated as $ghUser"
}

function Install-Nix {
    # Track whether we installed Nix this run so Main can warn the user
    # afterwards that `nix` won't be on PATH in new terminals until they
    # restart the shell (env mutations from the installer don't propagate
    # back to the parent process that curl|pwsh'd this script).
    $script:NixJustInstalled = $false
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
        $script:NixJustInstalled = $true

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
        Test-NixFlakes
    }
    elseif (-not $IsNativeWindows) {
        Write-Warn 'Nix installed but not in PATH. Restart your shell and re-run this script.'
        exit 0
    }
}

function Test-NixFlakes {
    # `nix develop` requires nix-command + flakes. Determinate enables both;
    # pre-existing nix installs often don't.
    & nix --extra-experimental-features 'nix-command flakes' flake --help *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Nix flakes not enabled — 'nix develop' will fail."
        Write-Warn "  Add to ~/.config/nix/nix.conf:  experimental-features = nix-command flakes"
    }
}

function Select-Repo {
    # Honour -Repo / $env:REPO for unattended runs.
    if ($Repo) {
        if ($ValidRepos -notcontains $Repo) {
            Write-Fail "Invalid -Repo '$Repo'. Valid: $($ValidRepos -join ', ')"
        }
        $script:Repo = $Repo
        Write-Info "Using Repo=$Repo from parameter/env"
        return
    }

    if (-not (Test-Interactive)) {
        Write-Fail "No interactive host for prompt. Use -Repo <name> or `$env:REPO to run unattended. Valid: $($ValidRepos -join ', ')"
    }

    Write-Host ''
    Write-Host '  Which repo do you want to work on?' -ForegroundColor White
    Write-Host ''
    Write-Host '  ' -NoNewline; Write-Host ' 1' -ForegroundColor Cyan -NoNewline; Write-Host '  programs      Solana/Anchor on-chain programs'
    Write-Host '  ' -NoNewline; Write-Host ' 2' -ForegroundColor Cyan -NoNewline; Write-Host '  dotnet-sdk    .NET client libraries'
    Write-Host '  ' -NoNewline; Write-Host ' 3' -ForegroundColor Cyan -NoNewline; Write-Host '  pypi          Python packages (MCP + DSA)'
    Write-Host '  ' -NoNewline; Write-Host ' 4' -ForegroundColor Cyan -NoNewline; Write-Host '  crates        Rust workspace (CLI + DSA)'
    Write-Host '  ' -NoNewline; Write-Host ' 5' -ForegroundColor Cyan -NoNewline; Write-Host '  npm           TypeScript packages (UI + DSA)'
    Write-Host '  ' -NoNewline; Write-Host ' 6' -ForegroundColor Cyan -NoNewline; Write-Host '  vcpkg         C++ libraries'
    Write-Host '  ' -NoNewline; Write-Host ' 7' -ForegroundColor Cyan -NoNewline; Write-Host '  landing       Marketing site'
    Write-Host '  ' -NoNewline; Write-Host ' 8' -ForegroundColor Cyan -NoNewline; Write-Host '  docs          Documentation site'
    Write-Host ''
    $choice = Read-Host '  Choice [1-8]'

    $script:Repo = switch ($choice) {
        '1' { 'programs' }
        '2' { 'dotnet-sdk' }
        '3' { 'pypi' }
        '4' { 'crates' }
        '5' { 'npm' }
        '6' { 'vcpkg' }
        '7' { 'landing' }
        '8' { 'docs' }
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
    if ((Test-Path (Join-Path $script:TargetDir 'flake.nix')) -and (Test-Command 'nix')) {
        Write-Info "Building Nix dev environment at $($script:TargetDir)"
        Write-Info '  (first run downloads ~500 MB - 2 GB; expect 2-5 minutes, no progress bar)'
        $nixStart = Get-Date
        & nix develop $script:TargetDir --command true
        if ($LASTEXITCODE -eq 0) {
            $elapsed = [int](New-TimeSpan -Start $nixStart -End (Get-Date)).TotalSeconds
            Write-Ok "Nix dev environment ready (${elapsed}s)"
        } else {
            Write-Warn "nix develop failed - cd into $($script:TargetDir) and run 'nix develop' to see errors"
        }
    }

    Write-Info 'Installing canonical ResQ git hooks...'
    $hooksUrl = "https://raw.githubusercontent.com/$Org/dev/main/scripts/install-hooks.ps1"
    try {
        $script = Invoke-RestMethod -Uri $hooksUrl -UseBasicParsing
        $sb = [ScriptBlock]::Create($script)
        Push-Location $script:TargetDir
        try { & $sb -TargetDir $script:TargetDir } finally { Pop-Location }
        Write-Ok 'Git hooks configured'
    } catch {
        Write-Warn "Hook install failed - re-run:  cd $($script:TargetDir); irm $hooksUrl | iex"
    }
}

# Install the `resq` binary from resq-software/crates GitHub Releases. Chooses
# the archive for the current platform, verifies SHA256 against the release's
# SHA256SUMS, and drops the binary into $env:RESQ_BIN_DIR (default:
# %LOCALAPPDATA%\Programs\resq\bin on Windows, ~/.local/bin on Unix).
#
# Idempotent: skips when the currently-installed `resq --version` matches the
# latest release. Skip entirely with $env:SKIP_RESQ_CLI=1.
function Install-ResqCli {
    if ($env:SKIP_RESQ_CLI -eq '1') {
        Write-Info 'SKIP_RESQ_CLI=1 - skipping resq binary install'
        return
    }

    # Map platform to Rust target triple and archive kind.
    if ($IsNativeWindows) {
        # release.yml only publishes x86_64 Windows; bail fast on 32-bit rather
        # than chasing a SHA256SUMS miss later.
        if ($script:Arch -ne 'x64') {
            Write-Warn "No resq-cli binary for Windows $($script:Arch) - skipping"
            return
        }
        $triple  = 'x86_64-pc-windows-msvc'
        $ext     = 'zip'
        $binName = 'resq.exe'
        $defaultBinDir = Join-Path $env:LOCALAPPDATA 'Programs\resq\bin'
    }
    elseif ($IsMacOS) {
        $triple  = if ($script:Arch -eq 'arm64') { 'aarch64-apple-darwin' } else { 'x86_64-apple-darwin' }
        $ext     = 'tar.gz'
        $binName = 'resq'
        $defaultBinDir = Join-Path $HOME '.local/bin'
    }
    elseif ($IsLinux) {
        $triple  = if ($script:Arch -in @('aarch64','arm64')) { 'aarch64-unknown-linux-gnu' } else { 'x86_64-unknown-linux-gnu' }
        $ext     = 'tar.gz'
        $binName = 'resq'
        $defaultBinDir = Join-Path $HOME '.local/bin'
    }
    else {
        Write-Warn "No resq-cli binary for $($script:Platform) - skipping"
        return
    }

    # Find latest resq-cli-v* tag.
    $tag = gh release list --repo "$Org/crates" --limit 40 --json tagName --jq '.[] | .tagName' 2>$null |
           Where-Object { $_ -like 'resq-cli-v*' } |
           Select-Object -First 1
    if (-not $tag) {
        Write-Warn "No resq-cli release found in $Org/crates - skipping binary install"
        return
    }
    $expectedVer = $tag -replace '^resq-cli-v', ''

    $binDir  = if ($env:RESQ_BIN_DIR) { $env:RESQ_BIN_DIR } else { $defaultBinDir }
    $binPath = Join-Path $binDir $binName

    if (Test-Path $binPath) {
        try {
            $installedVer = (& $binPath --version 2>$null) -split '\s+' | Select-Object -Last 1
        } catch { $installedVer = '' }
        if ($installedVer -eq $expectedVer) {
            Write-Ok "resq $expectedVer already installed at $binPath"
            Install-ResqCompletions -BinPath $binPath
            return
        }
    }

    Write-Info "Installing resq $expectedVer for $triple..."
    $tmp = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())) -Force
    try {
        $asset = "resq-cli-${tag}-${triple}.${ext}"
        gh release download $tag --repo "$Org/crates" --pattern $asset --pattern 'SHA256SUMS' --dir $tmp.FullName --clobber 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to download $asset from $tag - skipping"
            return
        }

        # Verify SHA256. SHA256SUMS has "<hash>  <filename>" lines; find ours.
        $sumsFile  = Join-Path $tmp.FullName 'SHA256SUMS'
        $assetPath = Join-Path $tmp.FullName $asset
        $expectedRow = (Get-Content $sumsFile) | Where-Object { $_ -match [regex]::Escape($asset) + '$' }
        if (-not $expectedRow) {
            Write-Warn "SHA256SUMS missing entry for $asset - not installing"
            return
        }
        $expectedHash = (($expectedRow -split '\s+')[0]).ToLower()
        $actualHash = (Get-FileHash -Path $assetPath -Algorithm SHA256).Hash.ToLower()
        if ($expectedHash -ne $actualHash) {
            Write-Warn "SHA256 verification failed for $asset - not installing"
            return
        }

        # Extract. PowerShell ships Expand-Archive for .zip; tar.exe for .tar.gz
        # is native on Win10+ and on all Unix hosts.
        if ($ext -eq 'zip') {
            Expand-Archive -Path $assetPath -DestinationPath $tmp.FullName -Force
        } else {
            & tar -xzf $assetPath -C $tmp.FullName
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Failed to extract $asset - skipping"
                return
            }
        }

        # Locate the binary inside the extracted tree (matches install.sh's find).
        $stagedBin = Get-ChildItem -Path $tmp.FullName -Recurse -Filter $binName | Select-Object -First 1
        if (-not $stagedBin) {
            Write-Warn "Archive layout unexpected ($binName missing) - skipping"
            return
        }

        if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
        Copy-Item -Path $stagedBin.FullName -Destination $binPath -Force
        if (-not $IsNativeWindows -and (Test-Command 'chmod')) {
            & chmod 0755 $binPath
        }
        Write-Ok "Installed $binPath"

        # PATH hint.
        $pathSep = if ($IsNativeWindows) { ';' } else { ':' }
        if (-not (($env:PATH -split $pathSep) -contains $binDir)) {
            if ($IsNativeWindows) {
                Write-Warn "$binDir is not in PATH. Add via Settings > Environment Variables."
            } else {
                Write-Warn "$binDir is not in PATH. Add to your shell rc:  export PATH=`"$binDir`:`$PATH`""
            }
        }

        Install-ResqCompletions -BinPath $binPath
    }
    finally {
        Remove-Item -Recurse -Force $tmp.FullName -ErrorAction SilentlyContinue
    }
}

# Generate PowerShell completions for the freshly-installed resq binary and
# write them next to $PROFILE. User sources the file from their $PROFILE to
# enable tab-completion across new sessions.
function Install-ResqCompletions {
    param([string]$BinPath)
    if (-not (Test-Path $BinPath)) { return }

    $profileDir = Split-Path $PROFILE -Parent
    $complDir   = Join-Path $profileDir 'Completions'
    $complFile  = Join-Path $complDir   'resq.ps1'

    if (-not (Test-Path $complDir)) { New-Item -ItemType Directory -Path $complDir -Force | Out-Null }

    try {
        # Native exec doesn't throw on non-zero exit even with
        # ErrorActionPreference='Stop' — check $LASTEXITCODE explicitly so a
        # corrupt / incompatible binary can't leave an empty completions file.
        & $BinPath completions powershell | Set-Content -Path $complFile -Encoding UTF8
        if ($LASTEXITCODE -ne 0) { throw "completions generation exited $LASTEXITCODE" }
        Write-Ok "Installed PowerShell completions to $complFile"
        $sourceLine = ". `"$complFile`""
        $profileSourcesIt = (Test-Path $PROFILE) -and ((Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($complFile))
        if (-not $profileSourcesIt) {
            Write-Info "  Add to your `$PROFILE to enable completions in new sessions:  $sourceLine"
        }
    } catch {
        Write-Warn "Failed to generate PowerShell completions - skip ($_)"
        Remove-Item -Path $complFile -ErrorAction SilentlyContinue
    }
}

function Show-RepoInfo {
    switch ($script:Repo) {
        'programs' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Solana CLI, Anchor framework, Rust toolchain'
            Write-Host '    make anchor-build, make anchor-test'
            Write-Host ''
        }
        'dotnet-sdk' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    .NET 9 SDK, Protobuf toolchain'
            Write-Host '    dotnet build -c Release, dotnet test -c Release'
            Write-Host ''
        }
        'landing' {
            Write-Host ''
            Write-Host '  What''s included:' -ForegroundColor White
            Write-Host ''
            Write-Host '    Bun, Next.js 15, Tailwind CSS, TypeScript'
            Write-Host '    bun dev, bun run build'
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
    Install-ResqCli
    Show-RepoInfo

    Write-Host '  Ready!' -ForegroundColor Green
    Write-Host ''

    if ($script:NixJustInstalled) {
        Write-Host '  Note:' -ForegroundColor Yellow -NoNewline
        Write-Host ' Nix was just installed. For `nix` to be on PATH, either:'
        Write-Host '    - open a new terminal, or'
        Write-Host '    - run:  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        Write-Host '  (fish users: set -x PATH /nix/var/nix/profiles/default/bin $PATH)'
        Write-Host ''
    }

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
