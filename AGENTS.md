# dev — Agent Guide

## Mission

Centralized developer onboarding for ResQ Software. One curl command installs tooling, authenticates with GitHub, and clones any repo into a ready-to-hack dev environment.

## Workspace Layout

```
install.sh    — Bash installer (Linux/macOS), curl-pipeable
install.ps1   — PowerShell installer (Windows/WSL/macOS/Linux)
CODEOWNERS    — Ownership rules
AGENTS.md     — Canonical dev guide (this file)
CLAUDE.md     — Claude-specific extensions
```

## Commands

```bash
sh install.sh          # Run installer locally
pwsh install.ps1       # Run PowerShell installer locally
shellcheck install.sh  # Lint the bash script
```

## Architecture

- Scripts are self-contained single files (no lib/ extraction) because the primary UX is curl-pipe
- install.sh starts as `#!/bin/sh`, re-execs under bash if available for pipefail + better error traps, falls back to POSIX sh
- Repo list is inline data, not external config
- All logging goes to stderr so curl-pipe stdout stays clean

## Standards

- POSIX sh compatibility required for the initial shebang + re-exec block
- Functions use verb_noun naming (detect_platform, install_gh)
- Every user-visible action gets a log line (info/ok/warn/fail)
- No `|| true` — handle errors explicitly or explain why ignoring
- Apache 2.0 license header on all scripts
