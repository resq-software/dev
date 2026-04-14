# Platform detection — OS and architecture normalization.

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-OsType {
    if ($IsWindows -or
        (-not $IsLinux -and -not $IsMacOS -and
         [System.Environment]::OSVersion.Platform -eq 'Win32NT')) {
        return 'windows'
    }
    if ($IsMacOS) { return 'macos' }
    if ($IsLinux) { return 'linux' }
    return 'unknown'
}

function Get-ArchType {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
    switch ($arch) {
        'x64'   { return 'amd64' }
        'arm64' { return 'arm64' }
        'arm'   { return 'arm' }
        default { return $arch }
    }
}

if (-not (Get-Variable -Name OsType   -Scope Script -ErrorAction SilentlyContinue)) { $script:OsType   = Get-OsType }
if (-not (Get-Variable -Name ArchType -Scope Script -ErrorAction SilentlyContinue)) { $script:ArchType = Get-ArchType }
$env:OS_TYPE   = $script:OsType
$env:ARCH_TYPE = $script:ArchType
