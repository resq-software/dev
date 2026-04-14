# dev — Agent Guide

## Mission

Centralized developer onboarding for ResQ Software. One curl command installs tooling, authenticates with GitHub, and clones any repo into a ready-to-hack dev environment.

## Workspace Layout

```
install.sh        — Bash installer (Linux/macOS), curl-pipeable
install.ps1       — PowerShell installer (Windows/WSL/macOS/Linux)
flake.nix         — Skeleton dev shell each repo extends
CODEOWNERS        — Ownership rules
AGENTS.md         — Canonical dev guide (this file)
CLAUDE.md         — Claude-specific extensions
scripts/
  setup.sh        — Post-clone environment bootstrap (bash)
  setup.ps1       — Post-clone environment bootstrap (powershell, mirrors setup.sh)
  install-hooks.sh — Installs canonical git hooks into a repo (local or curl-piped)
  install-hooks.ps1 — PowerShell mirror
  install-resq.sh — Installs the `resq` CLI binary from GitHub Releases (SHA-verified)
  git-hooks/      — Canonical hook shims (pre-commit, commit-msg, pre-push, …)
  lib/
    log.{sh,ps1}        — Colored log helpers
    platform.{sh,ps1}   — OS / arch detection, command_exists
    prompt.{sh,ps1}     — Interactive prompts, sudo/admin guards
    packages.{sh,ps1}   — Cross-platform package manager (apt/dnf/pacman/zypper/apk/brew/winget/choco/scoop)
    nix.{sh,ps1}        — Nix install + flake re-exec
    docker.{sh,ps1}     — Docker / Docker Desktop install
    bun.{sh,ps1}        — Bun install
    audit.{sh,ps1}      — osv-scanner / audit-ci bootstrap
    misc.{sh,ps1}       — md5, GitHub releases, port checks
    shell-utils.{sh,ps1} — Aggregator that sources every module above
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

## Git hooks

Canonical hooks live in `scripts/git-hooks/` and are installed into any ResQ
repo by `scripts/install-hooks.sh` (or `.ps1`). The hooks are thin shims that
delegate heavy lifting to the `resq` CLI binary from
[`resq-software/crates`](https://github.com/resq-software/crates):

- `pre-commit` → `resq pre-commit` (copyright, secrets, audit, polyglot format)
- `commit-msg` → Conventional Commits + fixup/WIP guard on main/master
- `prepare-commit-msg` → ticket prefix from branch name
- `pre-push` → force-push guard + branch naming convention
- `post-checkout` / `post-merge` → lock-file change notices

**Per-repo customization**: each hook invokes `.git-hooks/local-<hook>` after
its canonical checks. Commit `local-*` files in the repo needing extras (e.g.
`local-pre-push` running `cargo check`). The canonical hooks themselves are
managed by `install-hooks.sh` and should not be hand-edited.

**`resq` backend**: hooks soft-skip with an informative warning if `resq` is
not on PATH. Provide it either via your repo's `flake.nix` (recommended — add
`resq-software/crates` as an input and include the `resq` package in
`devPackages`) or globally:

```sh
cargo install --git https://github.com/resq-software/crates resq-cli
```

**Bypass**: `git commit --no-verify`, `git push --no-verify`, or
`GIT_HOOKS_SKIP=1` in the environment to disable all hooks for a session.

Sibling repos' `AGENTS.md` should link this section rather than duplicating it.
