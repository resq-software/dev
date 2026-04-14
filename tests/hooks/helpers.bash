# shellcheck shell=bash
# Common helpers for bats tests over the canonical ResQ git hooks.
#
# Each test gets a fresh tempdir initialized as a git repo with the canonical
# hooks copied in. core.hooksPath is set so `git` invokes the hooks naturally.

# Absolute path to the canonical hook templates shipped by this repo.
HOOK_SRC="${BATS_TEST_DIRNAME}/../../scripts/git-hooks"

# Initialize a fresh git repo in $1 with canonical hooks installed.
init_repo_with_hooks() {
    local dir="$1"
    git -C "$dir" init -q
    git -C "$dir" -c user.email=t@t.io -c user.name=t commit --allow-empty -m "init" -q
    mkdir -p "$dir/.git-hooks"
    cp "$HOOK_SRC"/{pre-commit,commit-msg,prepare-commit-msg,pre-push,post-checkout,post-merge} "$dir/.git-hooks/"
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
