# Nix installer — Windows native is unsupported; warn + WSL hint.
# Requires log.ps1 + platform.ps1.

function Install-Nix {
    if (Test-Command 'nix') { return $true }

    if ($script:OsType -eq 'windows') {
        Log-Warning 'Nix is not natively supported on Windows.'
        Log-Info 'Run this script inside a WSL distribution (wsl --install).'
        return $false
    }

    if (-not (Test-Command 'bash')) {
        Log-Error 'bash is required to run the Nix installer.'
        return $false
    }

    # Mirrors scripts/lib/nix.sh: pinned version, digest-checked before it runs.
    # Bump both files together; required.yml re-checks the digest.
    $nixUrl = 'https://install.determinate.systems/nix/tag/v3.21.9'
    $nixSha = 'ed6067b13423cfd36c50e5b156b9e08eb3a7bea4dde8cb1c8d997d757b37b7f6'
    $stage  = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        $installer = Join-Path $stage 'nix-installer.sh'
        Log-Info 'Downloading pinned Nix installer...'
        Invoke-WebRequest -Uri $nixUrl -OutFile $installer -UseBasicParsing -ErrorAction Stop
        $got = (Get-FileHash -Path $installer -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($got -ne $nixSha) {
            Log-Error 'Nix installer checksum mismatch — refusing to run it.'
            Log-Error "  expected $nixSha"
            Log-Error "  got      $got"
            return $false
        }
        Log-Info 'Running official Nix multi-user installer...'
        bash -c "sh '$installer' install --no-confirm"
    }
    finally {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }

    foreach ($p in @(
        '/etc/profile.d/nix.sh',
        "$HOME/.nix-profile/etc/profile.d/nix.sh",
        '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh')) {
        if (Test-Path $p) {
            Log-Info "Activate Nix in a new shell:  source $p"
            break
        }
    }

    if (Test-Command 'nix') { Log-Success 'Nix installed.'; return $true }
    Log-Warning 'Nix installed but not in this session PATH. Open a new shell.'
    return $true
}

# Sources nix profile or hints for re-exec via `nix develop`.
function Enter-NixEnv {
    if ($script:OsType -eq 'windows') { return }
    if ($env:IN_NIX_SHELL -or $env:RESQ_NIX_RECURSION) { return }
    if (-not (Test-Command 'nix')) { return }

    $projectRoot = & git rev-parse --show-toplevel 2>$null
    if (-not $projectRoot) { $projectRoot = '.' }
    if (-not (Test-Path (Join-Path $projectRoot 'flake.nix'))) { return }

    Log-Info "Nix flake detected at $projectRoot."
    Log-Info "Run 'nix develop' to enter the dev shell (PowerShell can't re-exec into it cleanly)."
}
