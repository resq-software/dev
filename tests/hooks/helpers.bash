# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
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

#
# By default the suite tests the crates commit scripts/install-hooks.sh pins,
# because that is what a user without resq on PATH gets installed. Testing
# `master` instead let this suite pass for behaviour the installer did not ship
# (the granular GIT_HOOKS_SKIP fix sat on master for weeks behind a pin that
# predated it). Set RESQ_HOOK_REF=master to test upstream ahead of a pin bump;
# hooks-tests.yml does that weekly.
_hooks_helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_REF="${RESQ_HOOK_REF:-$(sed -n 's/^ *CRATES_COMMIT="\(.*\)"$/\1/p' "$_hooks_helpers_dir/../../scripts/install-hooks.sh")}"
[ -n "$HOOK_REF" ] || { echo "helpers.bash: could not read CRATES_COMMIT from scripts/install-hooks.sh" >&2; exit 1; }
HOOK_RAW_BASE="${RESQ_HOOK_RAW_BASE:-https://raw.githubusercontent.com/resq-software/crates/$HOOK_REF/crates/resq-cli/templates/git-hooks}"
HOOK_NAMES="pre-commit commit-msg prepare-commit-msg pre-push post-checkout post-merge"
_hooks_pinned_commit="$(sed -n 's/^ *CRATES_COMMIT="\(.*\)"$/\1/p' "$_hooks_helpers_dir/../../scripts/install-hooks.sh")"

# Where the templates come from, most specific first:
#   RESQ_HOOK_SRC_DIR  a local template dir (e.g. an unpushed crates change),
#                      used as-is: never fetched into, never digest-checked.
#   the pinned commit  cached across runs under /tmp, and every file checked
#                      against the digest install-hooks.sh enforces, so a stale,
#                      half-written or tampered cache is refetched, not trusted.
#   anything else      a moving branch such as `master`, or a custom
#                      RESQ_HOOK_RAW_BASE — fetched fresh into this run's own
#                      tmpdir, because a cache keyed on it could go stale.
HOOK_VERIFY=0
if [ -n "${RESQ_HOOK_SRC_DIR:-}" ]; then
    HOOK_SRC_CACHE="$RESQ_HOOK_SRC_DIR"
elif [ "$HOOK_REF" = "$_hooks_pinned_commit" ] && [ -z "${RESQ_HOOK_RAW_BASE:-}" ]; then
    HOOK_SRC_CACHE="/tmp/resq-canonical-hooks-$HOOK_REF"
    HOOK_VERIFY=1
else
    # BATS_RUN_TMPDIR is unique per bats invocation and shared by its tests.
    HOOK_SRC_CACHE="${BATS_RUN_TMPDIR:-$(mktemp -d)}/resq-canonical-hooks"
fi

_hook_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
    else shasum -a 256 < "$1" | cut -d' ' -f1; fi
}

# The digest install-hooks.sh pins for hook $1.
_pinned_hook_digest() {
    sed -n "s/^ *$1) *echo \"\([0-9a-f]\{64\}\)\" ;;\$/\1/p" "$_hooks_helpers_dir/../../scripts/install-hooks.sh"
}

_hook_cache_valid() {
    local h
    for h in $HOOK_NAMES; do
        [ -s "$HOOK_SRC_CACHE/$h" ] || return 1
        [ "$HOOK_VERIFY" = 1 ] || continue
        [ "$(_hook_sha256 "$HOOK_SRC_CACHE/$h")" = "$(_pinned_hook_digest "$h")" ] || return 1
    done
}

_ensure_hook_cache() {
    _hook_cache_valid && return 0
    if [ -n "${RESQ_HOOK_SRC_DIR:-}" ] && [ -e "$RESQ_HOOK_SRC_DIR/pre-commit" ]; then
        echo "helpers.bash: RESQ_HOOK_SRC_DIR=$RESQ_HOOK_SRC_DIR is missing some of: $HOOK_NAMES" >&2
        return 1
    fi
    mkdir -p "$HOOK_SRC_CACHE"
    for h in $HOOK_NAMES; do
        curl -fsSL "$HOOK_RAW_BASE/$h" -o "$HOOK_SRC_CACHE/$h" || return 1
    done
    _hook_cache_valid || {
        echo "helpers.bash: hooks fetched from $HOOK_RAW_BASE do not match the digests pinned in scripts/install-hooks.sh" >&2
        return 1
    }
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

# ── Fake `resq` backend ──────────────────────────────────────────────────────
# The canonical pre-commit hook delegates its actual checks to `resq
# pre-commit`. To assert *which checks the hook asks for* without depending on
# a real resq install (CI has none), install a stub on PATH that reproduces the
# plain, non-TUI step output a developer actually sees.
#
# Source of truth for these strings: resq-software/crates
#   crates/resq-cli/src/commands/pre_commit.rs :: run_plain()
# Keep the step names and the --skip-* branching in sync with that function.
# run_plain has no versioning step and does not take skip_versioning, so the
# stub prints none either; tests see --skip-versioning through the
# "resq-args:" line, which records exactly what the hook passed.
#
# The "✅ " prefix matters. A hook that announces a skip has to name the checks
# it disabled ("SKIPPED: ... Secrets scan"), so a bare step name appears in the
# output whether the step ran or not. Only the pass marker distinguishes "this
# check actually ran" from "this check was mentioned in the announcement", so
# tests assert on "✅ Secrets", never on "Secrets".
#
# Sets two variables for the caller:
#   FAKE_BIN   dir to put first on PATH (contains the stub)
#   FAKE_HOME  clean HOME, so the hook's $HOME/.cargo/bin/resq fallback cannot
#              reach a real binary on a developer machine
install_fake_resq() {
    FAKE_BIN="$(mktemp -d)"
    FAKE_HOME="$(mktemp -d)"
    cat > "$FAKE_BIN/resq" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "pre-commit" ] || exit 0
echo "resq-args: $*"
skip_audit=0
skip_format=0
for a in "$@"; do
    case "$a" in
        --skip-audit)      skip_audit=1 ;;
        --skip-format)     skip_format=1 ;;
    esac
done
echo "  ✅ Copyright"
echo "  ✅ Large Files"
echo "  ✅ Debug Stmts"
echo "  ✅ Secrets"
[ "$skip_audit"      -eq 1 ] || echo "  ✅ Audit"
[ "$skip_format"     -eq 1 ] || echo "  ✅ Format Rust"
STUB
    chmod +x "$FAKE_BIN/resq"
}

remove_fake_resq() {
    rm -rf "${FAKE_BIN:-/nonexistent}" "${FAKE_HOME:-/nonexistent}"
}

# Run a hook with the fake resq backend resolvable and nothing else.
#   run_hook_with_resq <repo-dir> <hook-name> [args...]
run_hook_with_resq() {
    local dir="$1" hook="$2"
    shift 2
    (cd "$dir" && PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$FAKE_HOME" \
        bash ".git-hooks/$hook" "$@")
}
