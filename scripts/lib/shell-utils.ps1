# Aggregator — dot-sources every lib module in dependency order.
# Back-compat shim. Prefer dot-sourcing only what you need.

$_libDir = Split-Path -Parent $PSCommandPath

. (Join-Path $_libDir 'log.ps1')
. (Join-Path $_libDir 'platform.ps1')
. (Join-Path $_libDir 'prompt.ps1')
. (Join-Path $_libDir 'packages.ps1')
. (Join-Path $_libDir 'misc.ps1')
. (Join-Path $_libDir 'nix.ps1')
. (Join-Path $_libDir 'docker.ps1')
. (Join-Path $_libDir 'bun.ps1')
. (Join-Path $_libDir 'audit.ps1')
