# Docker installer. Requires log.ps1 + platform.ps1 + packages.ps1 + prompt.ps1.

function Install-Docker {
    if (Test-Command 'docker') { return $true }

    Log-Info 'Attempting to install Docker...'

    switch ($script:OsType) {
        'windows' {
            if (Test-Command 'winget') {
                winget install --silent --accept-source-agreements --accept-package-agreements --id Docker.DockerDesktop
            }
            elseif (Test-Command 'choco') {
                choco install -y docker-desktop
            }
            else {
                Log-Error 'winget or choco required to install Docker Desktop.'
                return $false
            }
            Log-Success 'Docker Desktop installed. Launch it from the Start Menu.'
            return $true
        }
        'macos' {
            if (Test-Command 'brew') {
                brew install --cask docker
            } else {
                Log-Error 'Homebrew not found. Install Docker Desktop manually.'
                return $false
            }
        }
        'linux' {
            if (-not (Test-Command 'bash')) {
                Log-Error 'bash required for Linux Docker install.'
                return $false
            }
            # Docker's own apt repository, which apt verifies by GPG signature
            # on every package — genuine verification, not merely a pinned
            # transport. scripts/lib/docker.sh already installs this way; this
            # branch still piped get.docker.com to sh, so the two halves of the
            # repo disagreed about how Docker gets installed, and only one of
            # them was verified.
            #
            # get.docker.com is rolling, unsigned and unversioned. There is
            # nothing to pin it against, so the fix is to stop using it rather
            # than to constrain how it is fetched.
            if (Test-Command 'apt-get') {
                # Debian and Ubuntu have separate suites, and the codename must
                # come from the matching one — `lsb_release -cs` on Debian gives
                # e.g. "bookworm", which the ubuntu suite does not publish.
                # Mirrors the detection in scripts/lib/docker.sh.
                $repo = @'
set -e
distro="$(. /etc/os-release && echo "${ID:-}")"
like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
case "$distro" in
  ubuntu) repo=ubuntu; codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")" ;;
  debian) repo=debian; codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")" ;;
  *) case "$like" in
       *ubuntu*) repo=ubuntu; codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-}")" ;;
       *debian*) repo=debian; codename="$(. /etc/os-release && echo "${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}")" ;;
       *) echo "Unrecognised apt distribution '$distro'" >&2; exit 1 ;;
     esac ;;
esac
[ -n "$codename" ] || { echo "Could not determine the codename for '$distro'" >&2; exit 1; }

sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /usr/share/keyrings
curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "https://download.docker.com/linux/$repo/gpg" \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/docker.gpg
sudo chmod a+r /usr/share/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/$repo $codename stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
'@
                bash -c $repo
                # Native command failure does not throw, so without this the
                # function continued to `return $true` and setup.ps1 carried on
                # as though Docker were installed.
                if ($LASTEXITCODE -ne 0) {
                    Log-Error "Docker repository setup failed (exit $LASTEXITCODE)."
                    return $false
                }
            }
            else {
                # Non-apt Linux under PowerShell is rare enough that pointing at
                # the shell installer beats maintaining a second copy of the
                # dnf/pacman logic, which would drift from docker.sh.
                Log-Error 'Automatic Docker install here supports apt only.'
                Log-Error 'Run scripts/setup.sh, or follow https://docs.docker.com/engine/install/'
                return $false
            }
            if (Test-Command 'sudo') { sudo usermod -aG docker $env:USER }
        }
        default {
            Log-Error "Docker install not supported for $($script:OsType)"
            return $false
        }
    }
    Log-Success 'Docker installed.'
    return $true
}
