# Bun installer. Requires log.ps1 + platform.ps1.

function Install-Bun {
    if (Test-Command 'bun') { return $true }
    Log-Info 'Installing Bun...'
    switch ($script:OsType) {
        'windows' {
            # Bun's own Windows installer, pinned to a tag and digest-checked
            # before it runs. Running their script rather than reimplementing
            # the download keeps their CPU baseline detection, which picks
            # bun-windows-x64 vs -baseline; choosing wrong yields a binary that
            # dies on older hardware.
            #
            # Note this is the tagged src/cli/install.ps1, which is NOT
            # byte-identical to what bun.sh/install.ps1 serves — unlike the
            # shell installer, where the two match. The tagged copy is the one
            # belonging to this release, so it is the one worth pinning.
            #
            # Bump both lines together; required.yml re-checks the digest.
            $bunUrl = 'https://raw.githubusercontent.com/oven-sh/bun/bun-v1.3.14/src/cli/install.ps1'
            $bunSha = '54fd5c34e08d2e363e9ee4cc52f58eca72b3c307c170869eec1e394c16fb7744'
            $stage  = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            try {
                $installer = Join-Path $stage 'install.ps1'
                Invoke-WebRequest -Uri $bunUrl -OutFile $installer -UseBasicParsing -ErrorAction Stop
                $got = (Get-FileHash -Path $installer -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($got -ne $bunSha) {
                    Log-Error 'Bun installer checksum mismatch — refusing to run it.'
                    Log-Error "  expected $bunSha"
                    Log-Error "  got      $got"
                    return $false
                }
                & $installer
            }
            finally {
                Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
            }
        }
        { $_ -in 'linux','macos' } {
            if (-not (Test-Command 'bash')) {
                Log-Error 'bash required for Bun install.'
                return $false
            }
            # Same pinned installer scripts/lib/bun.sh uses, verified the same
            # way. Kept as one bash invocation so the digest check and the run
            # cannot be separated by a caller.
            $shUrl = 'https://raw.githubusercontent.com/oven-sh/bun/bun-v1.3.14/src/cli/install.sh'
            $shSha = 'bab8acfb046aac8c72407bdcce903957665d655d7acaa3e11c7c4616beae68dd'
            bash -c @"
set -e
tmp=`$(mktemp -d)
trap 'rm -rf "`$tmp"' EXIT
curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 '$shUrl' -o "`$tmp/install.sh"
got=`$(sha256sum "`$tmp/install.sh" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "`$tmp/install.sh" | cut -d' ' -f1)
if [ "`$got" != '$shSha' ]; then
  echo "Bun installer checksum mismatch: expected $shSha, got `$got" >&2
  exit 1
fi
bash "`$tmp/install.sh"
"@
            $env:BUN_INSTALL = "$HOME/.bun"
            $env:PATH        = "$env:BUN_INSTALL/bin:$env:PATH"
        }
        default {
            Log-Error "Bun install not supported for $($script:OsType)"
            return $false
        }
    }
    Log-Success 'Bun installed.'
    return $true
}
