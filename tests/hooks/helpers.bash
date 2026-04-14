# shellcheck shell=bash
# Common helpers for bats tests over the canonical ResQ git hooks.
#
# Canonical hook content is owned by resq-software/crates (resq-cli embeds
# the same templates). This helper fetches them once per bats session from
# the crates repo via raw, caches them under /tmp, and copies them into
# each test's fresh repo.
#
# Override the source with RESQ_HOOK_SRC_DIR=/path/to/local/templates to
# test a local change before pushing it to crates.

HOOK_SRC_CACHE="${RESQ_HOOK_SRC_DIR:-/tmp/resq-canonical-hooks}"
HOOK_RAW_BASE="${RESQ_HOOK_RAW_BASE:-https://raw.githubusercontent.com/resq-software/crates/master/crates/resq-cli/templates/git-hooks}"

_ensure_hook_cache() {
    [ -d "$HOOK_SRC_CACHE" ] && [ -e "$HOOK_SRC_CACHE/pre-commit" ] && return 0
    mkdir -p "$HOOK_SRC_CACHE"
    for h in pre-commit commit-msg prepare-commit-msg pre-push post-checkout post-merge; do
        curl -fsSL "$HOOK_RAW_BASE/$h" -o "$HOOK_SRC_CACHE/$h"
    done
}

# Initialize a fresh git repo in $1 with canonical hooks installed.
init_repo_with_hooks() {
    local dir="$1"
    _ensure_hook_cache
    git -C "$dir" init -q
    git -C "$dir" -c user.email=t@t.io -c user.name=t commit --allow-empty -m "init" -q
    mkdir -p "$dir/.git-hooks"
    cp "$HOOK_SRC_CACHE"/{pre-commit,commit-msg,prepare-commit-msg,pre-push,post-checkout,post-merge} "$dir/.git-hooks/"
    chmod +x "$dir/.git-hooks"/*
    git -C "$dir" config core.hooksPath .git-hooks
    git -C "$dir" config user.email t@t.io
    git -C "$dir" config user.name t
}

# Run a hook directly against a repo: run_hook <repo-dir> <hook-name> [args...]
run_hook() {
    local dir="$1" hook="$2"
    shift 2
    (cd "$dir" && bash ".git-hooks/$hook" "$@")
}

# Force-switch to branch <name> (creates if missing). Avoids the fragile
# `branch -m` || `checkout -b` dance in tests.
checkout_branch() {
    local dir="$1" name="$2"
    git -C "$dir" checkout -q -B "$name"
    git -C "$dir" symbolic-ref HEAD "refs/heads/$name"
}

# Make a setup commit without firing the installed hooks.
# Args: <dir> <message> [extra git-commit args...]
commit_no_hooks() {
    local dir="$1" msg="$2"
    shift 2
    git -C "$dir" -c "core.hooksPath=" commit --allow-empty -q -m "$msg" "$@"
}
