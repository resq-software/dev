# Miscellaneous helpers — GitHub API, port checks.
#
# Get-FileMd5 was here and is deliberately gone. It wrapped
# `Get-FileHash -Algorithm MD5` and had zero callers — dead code, but the
# dangerous kind: this repo verifies every distributed byte with SHA-256, and
# leaving an MD5 helper in the shared library invites the next person who needs
# "a hash" to reach for the collision-broken one. Everything that hashes here
# uses SHA-256 (install.ps1, scripts/install-hooks.ps1, scripts/install-resq.sh).
#
# Found by PSScriptAnalyzer's PSAvoidUsingBrokenHashAlgorithms on the first run
# it ever performed — the analyser had been failing silently in CI for months.

function Get-LatestGitHubRelease {
    param([Parameter(Mandatory)][string]$Repo)
    $r = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    return $r.tag_name
}

function Test-PortInUse {
    param([Parameter(Mandatory)][int]$Port)
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        return $null -ne (Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
    }
    # Fallback: probe by trying to listen
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start(); $listener.Stop()
        return $false
    } catch { return $true }
}
