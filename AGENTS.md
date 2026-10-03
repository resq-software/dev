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
  src/index.ts    — The Worker. PINS decides which bytes users receive.
                    TypeScript; Wrangler transpiles on deploy, tsc only checks.
  wrangler.jsonc  — Deploy manifest; `name` must match the live Worker
  tsconfig.json   — Type checking only (noEmit); no build output is committed
  package.json    — devDependencies only; the Worker ships zero runtime deps
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
  by the `PINS` block in `worker/src/index.ts`, which changes only via a
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

- a tag pushed with `GITHUB_TOKEN` starts no workflow run at all, because
  GitHub suppresses run-triggering events originating from that token;
- and there is no way to exempt Actions from a tag ruleset. GitHub Actions is a
  first-party integration, not an installable app, so it cannot be named as a
  bypass actor — the API rejects it outright.

Nothing here waits on a tag, so the first rule cannot bite.

Because of the second, `release-tags` enforces `update` and `deletion` but
**not** `creation`. Those two are the ones that matter: pins resolve a tag to a
commit, so a moved or deleted tag would silently repoint a published version.
An extra tag publishes nothing by itself, since the trigger is a `VERSION`
change.

The consequence is that a `v*` ref is no longer inherently privileged, so
`release.yml` checks that the commit is an ancestor of `main` rather than
trusting the ref it was reached by. Review is what makes a commit releasable;
the ref is incidental.

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

**`resq` backend**: `pre-commit` **fails closed** if `resq` is not on PATH —
it refuses the commit and lists every check that could not run, because an
unscanned change must not pass by default. (Hooks before
resq-software/crates#206 soft-skipped instead.) To commit without it on purpose,
use `GIT_HOOKS_SKIP=all` or `--no-verify`. Provide it either via your repo's `flake.nix` (recommended — add
`resq-software/crates` as an input and include the `resq` package in
`devPackages`) or globally:

```sh
cargo install --git https://github.com/resq-software/crates resq-cli
```

**Bypass**: `git commit --no-verify` / `git push --no-verify` skips one
invocation. `GIT_HOOKS_SKIP` skips named checks for a session.

`GIT_HOOKS_SKIP` is a **list of check names, not a boolean**. Separate with
commas, colons or spaces; case-insensitive.

| Token | Skips |
|---|---|
| `all`, `1`, `true`, `yes`, `on` | **every check in every hook** except `prepare-commit-msg` |
| `0`, `false`, `no`, `off`, `none` | nothing — explicit no-op |
| `audit` / `format` / `versioning` | `pre-commit` steps |
| `msg-format` / `wip-guard` | `commit-msg` checks |
| `force-push` / `branch-name` | `pre-push` guards |
| `notify` | `post-checkout`, `post-merge` lock-file notices |
| `local` | the repo's `local-<hook>` override (not `local-prepare-commit-msg`) |

**Exception:** `prepare-commit-msg` has no `GIT_HOOKS_SKIP` handling at the
pinned crates commit, so no token changes what it does. It exits first, doing
nothing, for message sources `message` (`-m`/`-F`), `merge`, `squash` and
`commit` (`-c`/`-C`/`--amend`), and on a detached HEAD. Otherwise it adds a
`[TICKET-123]` prefix when the branch name carries one and dispatches to
`local-prepare-commit-msg`. It prints no banner and gates nothing.

```sh
GIT_HOOKS_SKIP=audit git commit -m "..."       # audit off; secret scan still runs
GIT_HOOKS_SKIP=audit,format git commit -m "..."
```

Three rules matter more than the token list:

1. **A skip is announced, never silent.** Before running anything the hook
   prints to stderr what it SKIPPED and what it is still RUNNING. Treat that
   banner as the source of truth for what actually executed — if a check isn't
   listed under `RUNNING`, do not report it as passed. When the value disables
   nothing in that hook, the banner is a single line instead (`… is set but
   disables nothing in <hook> — all checks ran`), and every check ran.
2. **An unrecognized value fails closed.** `GIT_HOOKS_SKIP=asdf` does not mean
   "skip everything"; gating hooks refuse to run and print the valid tokens.
   The old guard was `[ -n "${GIT_HOOKS_SKIP:-}" ] && exit 0`, so any non-empty
   value disabled the whole hook — a granular-looking `GIT_HOOKS_SKIP=audit`
   silently turned off the secret scan as well. That is the bug this replaces.
3. **The secret scan has no token.** It is the compensating control for
   unlicensed GitHub Secret Protection, so it can only be disabled by the
   all-off value (which says so loudly) or `--no-verify`. `GIT_HOOKS_SKIP=secrets`
   is refused by name.

The token vocabulary is global and byte-identical in every hook that parses it
(all but `prepare-commit-msg`), so a value
exported once for a shell session cannot mean different things in different
hooks. A token owned by another hook is inert, not an error. Behaviour is
pinned by `tests/hooks/git-hooks-skip.bats`.

Sibling repos' `AGENTS.md` should link this section rather than duplicating it.
