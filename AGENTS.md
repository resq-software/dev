# dev — Agent Guide

## Mission

Centralized developer onboarding for ResQ Software. One curl command installs tooling, authenticates with GitHub, and clones any repo into a ready-to-hack dev environment.

## Workspace Layout

```
VERSION           — The single authored version. Everything else is stamped.
install.sh        — Bash installer (Linux/macOS), curl-pipeable
install.ps1       — PowerShell installer (Windows/WSL/macOS/Linux)
flake.nix         — Skeleton dev shell each repo extends
AGENTS.md         — Canonical dev guide (this file)
CLAUDE.md         — Claude-specific extensions
.github/CODEOWNERS — Ownership rules. THE ACTIVE ONE: GitHub reads the first
                    CODEOWNERS it finds (.github/ -> root -> docs/), so rules
                    written in the root copy are silently ignored.
CODEOWNERS        — Inert signpost pointing at .github/CODEOWNERS
bin/              — Maintainer tools. Deliberately NOT scripts/: everything in
                    scripts/ is an artifact the Worker serves to users, and
                    nothing in bin/ ever should be.
  gen-pins.sh     — Derives the Worker pin set from every v* tag
  stamp.sh        — Propagates VERSION + hook digests into both installers
worker/           — get.resq.software: pinned, hash-verified distribution
  src/index.js    — The Worker. PINS decides which bytes users receive.
  wrangler.jsonc  — Deploy manifest; `name` must match the live Worker
  test/           — node worker/test/index.test.mjs
scripts/
  setup.sh        — Post-clone environment bootstrap (bash)
  setup.ps1       — Post-clone environment bootstrap (powershell, mirrors setup.sh)
  install-hooks.sh — Installs canonical git hooks into a repo (local or curl-piped)
  install-hooks.ps1 — PowerShell mirror
  install-resq.sh — Installs the `resq` CLI binary from GitHub Releases (SHA-verified)
  # Canonical hook templates are owned by resq-software/crates
  # (crates/resq-cli/templates/git-hooks/). install-hooks.sh fetches them
  # from there (or lets `resq hooks install` scaffold offline). No copy
  # lives in this repo.
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

## Distribution and releases

`curl -fsSL https://get.resq.software | sh` is a remote code execution
primitive by design. The only question that matters is *whose* code, so:

- The Worker fetches by **40-char commit SHA**, never a branch or tag. Branches
  move on every push; tags can be force-moved.
- It **SHA-256 verifies every byte** against digests baked in at deploy. On
  mismatch it returns 502 and serves no installer bytes — the body is a short
  shell snippet that prints an error and exits 1, so a `curl | sh` that omitted
  `-f` still fails loudly instead of executing prose. There is no degraded mode
  that serves unverified content.
- Therefore **merging to `main` ships nothing.** What users receive is decided
  by the `PINS` block in `worker/src/index.js`, which changes only via a
  reviewed PR. That is the gate — not the deploy trigger.

Cutting a release:

```sh
echo 0.5.0 > VERSION
sh bin/stamp.sh              # propagates into install.sh + install.ps1
# open a PR, merge it — that is the whole release
```

**Do not tag by hand.** Merging a `VERSION` change to `main` *is* the release:
`release.yml` validates it, creates `v0.5.0` itself, publishes the Release plus
`SHA256SUMS`, and opens the pin-bump PR. No Cloudflare credential is involved
anywhere; Workers Builds deploys `worker/` when that PR merges, and
`worker-live` then checks the endpoint agrees with `main`.

Tagging is deliberately an *output* rather than a trigger. Two things make the
obvious alternative — a workflow that pushes a tag — not work, and both are
easy to rediscover painfully:

- the `release-tags` ruleset rejects tag creation by anyone outside
  `@resq-software/installer-maintainers`, bots included, unless the GitHub
  Actions app is a bypass actor;
- a tag pushed with `GITHUB_TOKEN` starts no workflow run at all, because
  GitHub suppresses run-triggering events originating from that token.

Nothing here waits on a tag, so the second rule cannot bite.

Order still matters: **stamp, then merge.** The commit being released has to
declare its own version, or artifacts published at `v0.5.0` would claim to be
`v0.4.0`. `bin/stamp.sh --check` runs on every PR and again before the tag is
created, so an unstamped commit never gets one.

Never hand-edit a value marked `GENERATED`. `bin/stamp.sh --check` runs on
every PR and verifies by regeneration, so a stamped value cannot be forgotten —
forgetting it is a diff.

## Standards

- POSIX sh compatibility required for the initial shebang + re-exec block
- Functions use verb_noun naming (detect_platform, install_gh)
- Every user-visible action gets a log line (info/ok/warn/fail)
- No `|| true` — handle errors explicitly or explain why ignoring
- Apache 2.0 license header on all scripts

## Git hooks

Canonical hook templates live in
[`resq-software/crates`](https://github.com/resq-software/crates/tree/master/crates/resq-cli/templates/git-hooks)
and are installed into any ResQ repo by `scripts/install-hooks.sh` (or
`.ps1`). When the `resq` binary is on PATH, the installer calls
`resq hooks install` which scaffolds from the embedded templates —
offline, no network round-trip. Without `resq`, it falls back to fetching
the templates from the crates repo via raw.githubusercontent.com.

The hooks are thin shims that delegate heavy lifting back to the `resq`
binary:

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
