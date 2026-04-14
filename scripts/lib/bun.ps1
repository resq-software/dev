# Bun installer. Requires log.ps1 + platform.ps1.

function Install-Bun {
    if (Test-Command 'bun') { return $true }
    Log-Info 'Installing Bun...'
    switch ($script:OsType) {
        'windows' {
            Invoke-RestMethod 'https://bun.sh/install.ps1' | Invoke-Expression
        }
        { $_ -in 'linux','macos' } {
            if (-not (Test-Command 'bash')) {
                Log-Error 'bash required for Bun install.'
                return $false
            }
            bash -c 'curl -fsSL https://bun.sh/install | bash'
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
