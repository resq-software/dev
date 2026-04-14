# Miscellaneous helpers — hashing, GitHub API, port checks.

function Get-FileMd5 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -Algorithm MD5 -Path $Path).Hash.ToLower()
}

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
