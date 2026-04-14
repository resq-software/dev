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
            bash -c 'curl -fsSL https://get.docker.com | sh'
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
