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

# GENERATED — stamped from VERSION by bin/stamp.sh. Do not edit by hand: CI
# re-runs the stamper and fails if the committed value differs.
$ScriptVersion  = '0.4.3'
$Org            = 'resq-software'
# Pinned to a version rather than the rolling endpoint, and digest-checked
# before it runs — mirrors install.sh. required.yml re-checks the digest against
# the live URL, so a stale pin fails CI rather than every user's install.
$NixInstallUrl  = 'https://install.determinate.systems/nix/tag/v3.21.9'
$NixInstallerSha256 = 'ed6067b13423cfd36c50e5b156b9e08eb3a7bea4dde8cb1c8d997d757b37b7f6'

# Pinned, hash-verified distribution endpoint (see worker/src/index.ts). It
# serves one specific commit and refuses to serve anything whose SHA-256 does
# not match, which is why it beats raw.githubusercontent.com's mutable /main.
$DistBase       = 'https://get.resq.software'

# GENERATED — SHA-256 of scripts/install-hooks.ps1 at this version, checked
# before that file is ever executed. Stamped by bin/stamp.sh.
$HooksSha256    = '4327881e0b02448c7d8b1ae921691d654a46cb3ba99b82107b54ea6126effc85'

# Canonical repo table — one source of truth for the menu, validation and the
# post-install summary. Those used to be three separate lists that could
# disagree, and did: `landing` went private while still being offered as menu
# option 7, so choosing it failed at clone time.
#
# Scope is mechanical so CI can verify it: public, non-archived, non-fork
# repositories in the org, excluding `.github`. Archived is part of the rule
# rather than an oversight — an archived repo is read-only, so offering it to
# clone-and-hack would be a dead end.
# Keep in sync with install.sh and README.md.
$Repos = @(
    [pscustomobject]@{ Name = 'crates'    ; Desc = 'Rust workspace (CLI + DSA)'     ; Includes = @('Rust toolchain, clippy, cargo-deny', 'Workspace: 9+ crates including CLI tools and resq-dsa') }
    [pscustomobject]@{ Name = 'dev'       ; Desc = 'Developer setup + installers'   ; Includes = @('POSIX sh + PowerShell installers, Cloudflare Worker', 'shellcheck install.sh, node worker/test/index.test.mjs') }
    [pscustomobject]@{ Name = 'docs'      ; Desc = 'Documentation site'             ; Includes = @('Mintlify docs site', 'npx mint dev for local preview') }
    [pscustomobject]@{ Name = 'dotnet'    ; Desc = 'Clean architecture building blocks (.NET)'; Includes = @('.NET 9 SDK, pinned by global.json', 'Packages: ResQ.BuildingBlocks Domain, Application, Adapters, Testing', 'dotnet build -c Release, dotnet test -c Release') }
    [pscustomobject]@{ Name = 'dotnet-sdk'; Desc = '.NET client libraries'          ; Includes = @('.NET 9 SDK, Protobuf toolchain', 'dotnet build -c Release, dotnet test -c Release') }
    [pscustomobject]@{ Name = 'npm'       ; Desc = 'TypeScript packages (UI + DSA)' ; Includes = @('Bun, TypeScript, React 19, Storybook, Chromatic', 'Packages: @resq-sw/ui (55+ components), @resq-sw/dsa', 'Biome linter') }
    [pscustomobject]@{ Name = 'programs'  ; Desc = 'Solana/Anchor on-chain programs'; Includes = @('Solana CLI, Anchor framework, Rust toolchain', 'make anchor-build, make anchor-test') }
    [pscustomobject]@{ Name = 'pypi'      ; Desc = 'Python packages (MCP + DSA)'    ; Includes = @('Python 3.11-3.13, uv, ruff, mypy', 'Packages: resq-mcp, resq-dsa', '90% test coverage gate enforced') }
    [pscustomobject]@{ Name = 'vcpkg'     ; Desc = 'C++ libraries'                  ; Includes = @('C++ toolchain, CMake, clang-format', 'Header-only library: resq-common') }
    [pscustomobject]@{ Name = 'viz'       ; Desc = '3D visualization'               ; Includes = @('Three.js / Cesium web viewers (TypeScript)', 'Unity 3D viewer (.NET 9, ResQ.Viz.sln)') }
)

# Derived, so it can never drift from the table above.
$ValidRepos = $Repos.Name

# ── Platform flag ────────────────────────────────────────────────────────────

# $IsWindows/$IsLinux/$IsMacOS are PowerShell 6+ automatic variables. They do
# not exist in Windows PowerShell 5.1, and `Set-StrictMode -Version Latest`
# above turns a read of an unset variable into a terminating error — so on 5.1
# this line aborted the installer before it printed anything at all.
#
# 5.1 is not an edge case here. `#Requires -Version 5.1` at the top of this file
# admits it, and it is exactly what `irm ... | iex` runs on a stock Windows box
# with no pwsh installed. The OSVersion.Platform fallback below shows 5.1 was
# meant to work; StrictMode made that branch unreachable.
#
# Defining them when absent, rather than guarding all twelve downstream reads:
# Windows PowerShell only ever runs on Windows, so the values are not in doubt,
# and every `if ($IsLinux)` further down keeps working untouched. The
# assignment is guarded because these are read-only in 6+.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $IsWindows = $true
    $IsLinux   = $false
    $IsMacOS   = $false
}

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
        # Download and verify before executing, rather than piping to sh —
        # mirrors install.sh. The installer runs with sudo and touches /nix, so
        # it warrants at least the treatment the hook installer gets.
        #
        # Still a third-party artifact: Determinate publishes no digest of their
        # own, so this pins *what we execute*, not what they wrote.
        $nixStage = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $nixStage -Force | Out-Null
        try {
            $nixInstaller = Join-Path $nixStage 'nix-installer.sh'
            Invoke-WebRequest -Uri $NixInstallUrl -OutFile $nixInstaller -UseBasicParsing -ErrorAction Stop
            $nixGot = (Get-FileHash -Path $nixInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($nixGot -ne $NixInstallerSha256) {
                Write-Warn 'Nix installer checksum mismatch — skipping Nix setup.'
                Write-Warn "  expected $NixInstallerSha256"
                Write-Warn "  got      $nixGot"
                return
            }
            bash -c "sh '$nixInstaller' install --no-confirm"
            # A native command's failure does not throw in PowerShell, so
            # without this the run continues and reports success. Verifying the
            # download says the script is authentic, not that it worked.
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "The Nix installer exited $LASTEXITCODE — continuing without Nix."
                Write-Warn '  Retry manually: https://determinate.systems/nix'
                return
            }
        }
        finally {
            Remove-Item -Recurse -Force $nixStage -ErrorAction SilentlyContinue
        }
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

    # Loop rather than abort. A typo here used to end the whole run — after gh,
    # Nix and a package-manager pass had already completed — forcing the user to
    # start over for a mistyped digit.
    while ($true) {
        Write-Host ''
        Write-Host '  Which repo do you want to work on?' -ForegroundColor White
        Write-Host ''

        # Numbered from the table itself, so the list can grow past 9 entries
        # without the prompt and the mapping drifting apart.
        for ($i = 0; $i -lt $Repos.Count; $i++) {
            Write-Host '  ' -NoNewline
            Write-Host ('{0,2}' -f ($i + 1)) -ForegroundColor Cyan -NoNewline
            Write-Host ('  {0,-12} {1}' -f $Repos[$i].Name, $Repos[$i].Desc)
        }

        Write-Host ''
        $choice = (Read-Host "  Choice [1-$($Repos.Count), or a name]").Trim()

        # Exact name match first, then a positional index. -eq on strings is a
        # literal comparison, so a typed value can never act as a wildcard the
        # way it could with -like or -match.
        $picked = $Repos | Where-Object { $_.Name -eq $choice } | Select-Object -First 1
        if (-not $picked -and $choice -match '^[0-9]+$') {
            $idx = [int]$choice
            if ($idx -ge 1 -and $idx -le $Repos.Count) { $picked = $Repos[$idx - 1] }
        }

        if ($picked) {
            $script:Repo = $picked.Name
            return
        }

        Write-Warn "Not a valid choice: $choice"
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
    # Prefer the hooks script already in the freshly-cloned tree (fetched over
    # authenticated HTTPS by `gh repo clone`). Re-fetching from a mutable raw
    # main ref and iex-ing it is a TOFU/RCE path.
    $hooksLocal = Join-Path $script:TargetDir 'scripts/install-hooks.ps1'
    $reRun = '.\scripts\install-hooks.ps1'
    try {
        if (Test-Path $hooksLocal) {
            # Execute as an in-memory script block (like the remote path) so it
            # runs even under a Restricted execution policy without persisting a
            # bypass — & on a .ps1 path would be blocked by default on clients.
            $sb = [ScriptBlock]::Create((Get-Content -Raw -Path $hooksLocal))
            Push-Location $script:TargetDir
            try { & $sb -TargetDir $script:TargetDir } finally { Pop-Location }
            Write-Ok 'Git hooks configured'
        } else {
            # No local copy (the cloned repo isn't `dev`), so fetch one.
            #
            # This was `irm .../dev/main/scripts/install-hooks.ps1 | iex` — a
            # plain remote code execution path: /main is mutable, nothing was
            # verified, and the response was turned straight into a ScriptBlock.
            # Now the download is pinned to this script's own version and its
            # SHA-256 checked before anything is executed.
            #
            # /v$ScriptVersion/ rather than bare /hooks.ps1 on purpose: an
            # install.ps1 from an older release must verify against the digest it
            # shipped with, not against whatever the newest release publishes.
            $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
            try {
                $dest = Join-Path $tmpDir 'install-hooks.ps1'

                # The endpoint may simply be down; the digest check is what
                # provides safety here, not the choice of host, and v* tags
                # cannot be moved or deleted under the `release-tags` ruleset.
                $sources = @(
                    "$DistBase/v$ScriptVersion/hooks.ps1"
                    "https://raw.githubusercontent.com/$Org/dev/v$ScriptVersion/scripts/install-hooks.ps1"
                )

                $verified = $false
                foreach ($url in $sources) {
                    try {
                        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
                    } catch {
                        continue
                    }
                    $got = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($got -eq $HooksSha256) {
                        $verified = $true
                        # Deliberately NOT "irm $url | iex". That is the
                        # unverified pipe-to-execute path this whole block
                        # exists to remove, and printing it as the recovery
                        # hint would hand the guarantee straight back for
                        # anyone who follows it. Point at verified routes.
                        $reRun = 'resq hooks install   # or re-run this installer'
                        break
                    }
                    Write-Warn "checksum mismatch for $url"
                    Write-Warn "  expected $HooksSha256"
                    Write-Warn "  got      $got"
                    Remove-Item -Force $dest -ErrorAction SilentlyContinue
                }

                if (-not $verified) {
                    Write-Warn 'Could not obtain a verified install-hooks.ps1 - skipping hook setup'
                    Write-Warn "  Set them up later with: cd $($script:TargetDir); resq hooks install"
                    return
                }

                $sb = [ScriptBlock]::Create((Get-Content -Raw -Path $dest))
                Push-Location $script:TargetDir
                try { & $sb -TargetDir $script:TargetDir } finally { Pop-Location }
                Write-Ok "Git hooks configured (verified $($HooksSha256.Substring(0, 12))...)"
            }
            finally {
                Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warn "Hook install failed - re-run:  cd $($script:TargetDir); $reRun"
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
    $entry = $Repos | Where-Object { $_.Name -eq $script:Repo } | Select-Object -First 1
    if (-not $entry) { return }

    Write-Host ''
    Write-Host '  What''s included:' -ForegroundColor White
    Write-Host ''
    foreach ($line in $entry.Includes) {
        Write-Host "    $line"
    }
    Write-Host ''
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
