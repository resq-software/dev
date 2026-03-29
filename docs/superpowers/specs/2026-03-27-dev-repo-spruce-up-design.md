# Dev Repo Spruce-Up — Design Spec

**Date:** 2026-03-27
**Scope:** Full repo — scripts, project files, README

## Context

The `dev` repo is ResQ Software's centralized developer onboarding tool. Two installer scripts (Bash + PowerShell) handle dependency installation, GitHub auth, Nix setup, and repo cloning via a curl-pipeable one-liner.

Current state: functional but lacking best practices (weak error handling, no version checks, inconsistent repo list, missing AGENTS.md/CLAUDE.md). The resQ monorepo has strong shell patterns worth adopting.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Script approach | Modular rewrite (B) | Clean function boundaries, testable steps, matches resQ patterns |
| Shell compat | Auto re-exec (C) | POSIX shebang for curl-pipe, re-exec under bash for pipefail if available |
| Utility pattern | Inline (A) | Must stay single-file for curl-pipe UX |
| PS1 scope | Full parity (A) | Same quality bar across platforms |
| Project files | Full AGENTS.md contract (B) | Follows the convention this repo documents |
| Repo list | Reconcile + new names (B) | Renames in-flight: cli→crates, mcp→pypi, ui→npm, new vcpkg |

## 1. install.sh — Modular Rewrite

### Structure

```
#!/bin/sh (POSIX header)
├── Bash re-exec block (re-exec as bash if available, else stay POSIX)
├── Strict mode (bash: set -euo pipefail | sh: set -eu)
├── Constants (colors, URLs, ORG, SCRIPT_VERSION)
├── Utility functions
│   ├── info(), ok(), warn(), fail() — stderr logging with color
│   ├── has() — command existence
│   ├── require_version() — semver minimum check
│   └── confirm() — y/n with YES=1 bypass
├── Step functions
│   ├── detect_platform()
│   ├── check_git()
│   ├── install_gh()
│   ├── authenticate_gh()
│   ├── install_nix()
│   ├── choose_repo()
│   ├── clone_repo()
│   └── post_clone_setup()
├── print_repo_info() — repo-specific output
└── main() — orchestrates
```

### Bash re-exec mechanism

```sh
#!/bin/sh
# Guard: if we've already re-execed, skip
if [ -z "${_RESQ_REEXEC:-}" ] && command -v bash >/dev/null 2>&1; then
  export _RESQ_REEXEC=1
  exec bash "$0" "$@"
fi
# Enhanced mode if under bash
if [ -n "${BASH_VERSION:-}" ]; then
  set -euo pipefail
else
  set -eu
fi
```

### Logging contract

All four log functions write to stderr (`>&2`) so curl-pipe stdout stays clean.
PowerShell: `Write-Host` already writes to the information stream (not stdout), so PS1 is safe by default.

### Version checks

- `require_version` compares dotted versions by splitting on `.` and comparing segments numerically
- Minimums: git >= 2.0, gh >= 2.0 (warn and continue, not hard fail — old versions usually work)
- On failure: `warn` with install/upgrade URL, do not block

### confirm() usage

Used before destructive/lengthy operations:
- Before installing Nix (significant system change)
- Before cloning into a directory that already exists (offers pull vs. fresh clone)
- Bypassed with `YES=1` for CI/scripted usage

### SCRIPT_VERSION

Printed in the banner header (`ResQ Developer Setup v0.2.0`). No telemetry, no update checking — purely informational for debugging "which version did you run?"

### Key changes

- Bash re-exec: shebang stays `#!/bin/sh`, script detects bash and re-execs for enhanced features
- All logging to stderr (curl-pipe safe)
- `|| true` replaced with explicit error handling
- `require_version` for git 2.x and gh 2.x minimums (warn, not block)
- Function documentation comments
- Repo menu expanded to 10 items with new names
- "What's included" blocks updated: pypi replaces mcp, crates replaces cli, npm replaces ui; minimal blocks added for vcpkg, cms, docs

## 2. install.ps1 — Full Parity Rewrite

### Structure

```
#Requires -Version 5.1
├── Constants ($Org, $NixInstallUrl, $ScriptVersion)
├── Utility functions
│   ├── Write-Info, Write-Ok, Write-Warn, Write-Fail
│   ├── Test-Command, Test-MinVersion, Confirm-Action
├── Step functions
│   ├── Get-Platform (cleaned up WSL detection)
│   ├── Assert-Git
│   ├── Install-GitHubCLI
│   ├── Connect-GitHub
│   ├── Install-Nix
│   ├── Select-Repo
│   ├── Clone-Repo
│   └── Initialize-Repo
├── Show-RepoInfo
└── Main
```

### Key changes

- `$IsNativeWindows` extracted once (eliminates repeated triple-negative pattern)
- Proper try/catch around gh auth
- `Test-MinVersion` for parity with bash
- Same 10-repo menu
- Simplified WSL detection

## 3. Repo List (Reconciled)

| # | Menu | Slug | Description | Status |
|---|------|------|-------------|--------|
| 1 | resQ | resQ | Platform monorepo (private) | unchanged |
| 2 | programs | programs | Solana/Anchor on-chain | unchanged |
| 3 | dotnet-sdk | dotnet-sdk | .NET client libraries | unchanged |
| 4 | pypi | pypi | Python packages (MCP + DSA) | renamed from mcp |
| 5 | crates | crates | Rust workspace (CLI + DSA) | renamed from cli |
| 6 | npm | npm | TS packages (UI + DSA) | renamed from ui |
| 7 | vcpkg | vcpkg | C++ libraries | new |
| 8 | landing | landing | Marketing site | unchanged |
| 9 | cms | cms | Content management | added to menu |
| 10 | docs | docs | Documentation site | added to menu |

README table also includes `resq-proto` and `dev` (not in menu).

## 4. AGENTS.md

New file following the contract format from the README:

```markdown
# dev — Agent Guide

## Mission
Centralized developer onboarding for ResQ Software. One curl command installs
tooling, authenticates with GitHub, and clones any repo into a ready-to-hack
dev environment.

## Workspace Layout
install.sh    — Bash installer (Linux/macOS), curl-pipeable
install.ps1   — PowerShell installer (Windows/WSL/macOS/Linux)
CODEOWNERS    — Ownership rules
AGENTS.md     — Canonical dev guide (this file)
CLAUDE.md     — Claude-specific extensions

## Commands
sh install.sh          — Run installer locally
pwsh install.ps1       — Run PowerShell installer locally
shellcheck install.sh  — Lint the bash script

## Architecture
- Scripts are self-contained single files (no lib/) for curl-pipe UX
- install.sh starts as #!/bin/sh, re-execs under bash if available
- Repo list is inline data, not external config
- All logging to stderr so curl-pipe stdout stays clean

## Standards
- POSIX sh compat required for shebang + re-exec block
- Functions use verb_noun naming (detect_platform, install_gh)
- Every user-visible action gets a log line (info/ok/warn/fail)
- No || true — handle errors explicitly or explain why ignoring
- Apache 2.0 license header on all scripts
```

## 5. CLAUDE.md

```markdown
# CLAUDE.md

See AGENTS.md for the canonical guide. This file adds Claude-specific context.

## Tool permissions
- Shell commands: sh, bash, pwsh, shellcheck, git, gh
- No destructive operations without confirmation

## Working conventions
- This repo is two scripts — prefer editing over creating new files
- Test changes by running install.sh in a clean environment
- The install scripts are curl-piped, so stdout must stay clean (log to stderr)
```

## 6. README Updates

Targeted edits only:
- Repo table: reflect renames, add vcpkg, fix docs org slug (`resq-sw/docs` → `resq-software/docs`)
- Quick start per repo: update paths and headers for renamed repos (cli→crates, mcp→pypi, ui→npm), add vcpkg quick start
- No changes to AI-assisted development sections, toolchain, quality gates, or license

## 7. CODEOWNERS

Add new line `install.ps1 @WomB0ComB0` (explicit ownership, same as install.sh).
The wildcard `* @WomB0ComB0` already covers all files; the explicit lines signal stricter review requirements for the installer scripts.

## Repo rename timing

The renames (mcp→pypi, cli→crates, ui→npm) are in-flight. This spec uses the new names. If a repo hasn't been renamed on GitHub yet when someone runs the script, `gh repo clone` will fail with a clear "not found" error. No fallback logic needed — the renames should land before or alongside this work.
