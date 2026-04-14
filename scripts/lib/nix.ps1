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

    Log-Info 'Running official Nix multi-user installer...'
    bash -c 'curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes'

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
