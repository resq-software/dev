# Canonical ResQ Git Hooks

Thin shims that dispatch heavy lifting to the `resq` CLI binary from
[`resq-software/crates`](https://github.com/resq-software/crates) and expose a
per-repo escape hatch via `local-<hook>` files.

## Files

| Hook                  | What it does                                                                 |
|-----------------------|------------------------------------------------------------------------------|
| `pre-commit`          | Delegates to `resq pre-commit` (copyright, secrets, audit, format)           |
| `commit-msg`          | Conventional Commits; blocks fixup/squash/WIP on main/master                 |
| `prepare-commit-msg`  | Prepends `[TICKET-123]` from branch name                                     |
| `pre-push`            | Force-push guard, branch naming convention                                   |
| `post-checkout`       | Notifies on lock-file changes (Cargo, bun, uv, flake)                        |
| `post-merge`          | Same, post-merge                                                             |

## Install into a repo

From `dev/`:

```sh
scripts/install-hooks.sh /path/to/repo
```

Curl-piped from anywhere:

```sh
cd /path/to/repo
curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-hooks.sh | sh
```

## Per-repo escape hatch

Each hook invokes `.git-hooks/local-<hook>` (if executable) after its canonical
checks pass. Put repo-specific logic there:

```sh
# Example: .git-hooks/local-pre-push in a Rust repo
#!/usr/bin/env bash
set -e
cargo check --workspace --quiet
```

Commit `local-*` files; the canonical hooks are managed by `install-hooks.sh`.

## Bypass

| Scope                         | How                                    |
|-------------------------------|----------------------------------------|
| Single commit/push            | `git commit --no-verify` / `git push --no-verify` |
| All hooks in this shell       | `export GIT_HOOKS_SKIP=1`              |
| Whole repo                    | `git config --unset core.hooksPath`    |
