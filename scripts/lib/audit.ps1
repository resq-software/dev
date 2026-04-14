# Audit-tool bootstrap (osv-scanner, audit-ci).
# Requires log.ps1 + platform.ps1 + packages.ps1 + prompt.ps1.

function Initialize-AuditTools {
    $missing = @()
    $projectRoot = & git rev-parse --show-toplevel 2>$null
    if (-not $projectRoot) { $projectRoot = '.' }

    if (-not (Test-Command 'osv-scanner')) { $missing += 'osv-scanner' }
    if ((-not (Test-Command 'audit-ci')) -and
        (-not (Test-Path (Join-Path $projectRoot 'node_modules/.bin/audit-ci')))) {
        $missing += 'audit-ci'
    }
    if ($missing.Count -eq 0) { return $true }

    Log-Warning "Missing auditing tools: $($missing -join ', ')"
    if ($env:YES -ne '1' -and -not (Confirm-Prompt 'Install missing auditing tools?')) {
        Log-Error 'Auditing tools required. Install manually.'
        return $false
    }

    foreach ($tool in $missing) {
        switch ($tool) {
            'osv-scanner' {
                if (-not (Install-OsvScanner)) {
                    if (Test-Command 'go') {
                        go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest
                    } else {
                        Log-Error 'Go not found. Cannot install osv-scanner.'
                        return $false
                    }
                }
            }
            'audit-ci' {
                Log-Info 'Installing audit-ci via Bun...'
                Push-Location $projectRoot
                try { bun install } finally { Pop-Location }
            }
        }
    }
    return $true
}
