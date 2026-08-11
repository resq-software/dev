#!/bin/sh
# Copyright 2026 ResQ Software
# SPDX-License-Identifier: Apache-2.0
#
# Install canonical ResQ git hooks into a repository.
#
# Usage (curl-piped):
#     cd /path/to/repo
#     curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-hooks.sh | sh
#
# Usage (local):
#     scripts/install-hooks.sh [target_dir]
#
# Canonical hook content is owned by resq-software/crates (the resq-cli crate
# that also powers `resq pre-commit`). This installer picks the best path:
#
#   1. `resq` on PATH   → `resq dev install-hooks` scaffolds from the embedded
#                         templates in the binary (offline, versioned with the
#                         user's installed resq).
#   2. Fallback          → fetch templates from
#                         resq-software/crates/master/crates/resq-cli/templates/git-hooks
#                         via raw.githubusercontent.com.
#
# Env:
#     RESQ_CRATES_REF          — git ref for raw fallback (default: master)
#     GIT_HOOKS_SKIP           — set to skip installation entirely
#     YES=1                    — auto-accept the local-hook scaffold prompt
#     RESQ_SKIP_LOCAL_SCAFFOLD — set to opt out of the local-hook prompt

set -eu

TARGET_DIR="${1:-$PWD}"
RESQ_CRATES_REF="${RESQ_CRATES_REF:-master}"

if ! git -C "$TARGET_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    printf 'fail  Not a git repository: %s\n' "$TARGET_DIR" >&2
    exit 1
fi
TARGET_ROOT="$(git -C "$TARGET_DIR" rev-parse --show-toplevel)"
HOOKS_DIR="$TARGET_ROOT/.git-hooks"
mkdir -p "$HOOKS_DIR"

# ── Resolve resq binary ─────────────────────────────────────────────────────
RESQ_BIN=""
if command -v resq >/dev/null 2>&1; then
    RESQ_BIN="resq"
elif [ -x "$HOME/.cargo/bin/resq" ]; then
    RESQ_BIN="$HOME/.cargo/bin/resq"
fi

# ── Path 1: use resq when present (preferred — offline, no raw fetch) ───────
# Prefer the new `hooks install` path; fall back to `dev install-hooks` for
# binaries built before resq-software/crates#60.
if [ -n "$RESQ_BIN" ]; then
    if "$RESQ_BIN" hooks install --help >/dev/null 2>&1; then
        install_cmd="hooks install"
    else
        install_cmd="dev install-hooks"
    fi
    printf 'info  Installing hooks via %s %s\n' "$RESQ_BIN" "$install_cmd" >&2
    # shellcheck disable=SC2086
    (cd "$TARGET_ROOT" && "$RESQ_BIN" $install_cmd)
else
    # ── Path 2: fetch from crates templates, pinned and verified ────────────
    #
    # These become executables git runs on every commit and push, so they get
    # the same treatment as the installer itself: a pinned commit, a digest
    # check, and failure closed.
    #
    # This previously fetched from `master` — a mutable branch — with no
    # verification, and it is the DEFAULT path: install.sh installs the resq
    # binary *after* calling this script, so a fresh machine never has resq on
    # PATH here and always landed in this branch. install.sh verifies this file
    # before running it, which meant little while this file then pulled
    # unverified executables one link further down.
    HOOKS="pre-commit commit-msg prepare-commit-msg pre-push post-checkout post-merge"

    # Pinned commit in resq-software/crates. Update this and the digests below
    # together; .github/workflows/required.yml re-checks them against the live
    # endpoint, so a stale or mistyped pin fails CI rather than a user's install.
    CRATES_COMMIT="e8e723d941673e32c0c5e3cc782c07262ad9dc2e"

    hook_digest() {
        case "$1" in
            pre-commit)         echo "540c19f96fe258df6d90a8357b27513657b380567650ce3aaed83efa216a64ee" ;;
            commit-msg)         echo "74eb3a46ed60a34bafc044e9800811afd684756be7cb32384a551f0c5cf73019" ;;
            prepare-commit-msg) echo "8c5092d5206647be93dc25deb02b4068531b48b7bc916ddadaca49b60f94d620" ;;
            pre-push)           echo "9627f0ad867d9e031f0bb756aaa8480533093bc7917798c6c617d85cc6ddfed8" ;;
            post-checkout)      echo "05d9be133a6edfd177a04a3a32c822896160a73c2a7d363d3136943f20ddd2cb" ;;
            post-merge)         echo "292fd2eeaae8243fd3c73512f41e7b88f7c83d67c78601dd66c3ce8e4a2dad83" ;;
            *)                  echo "" ;;
        esac
    }

    # macOS ships shasum but not sha256sum.
    if command -v sha256sum >/dev/null 2>&1; then
        hook_sha256() { sha256sum < "$1" | cut -d' ' -f1; }
    elif command -v shasum >/dev/null 2>&1; then
        hook_sha256() { shasum -a 256 < "$1" | cut -d' ' -f1; }
    else
        printf 'fail  Neither sha256sum nor shasum available — refusing to install unverifiable hooks.\n' >&2
        exit 1
    fi

    # RESQ_CRATES_REF still works, but pinned digests cannot describe an
    # arbitrary ref, so overriding it means opting out of verification
    # explicitly — the same contract as RESQ_ALLOW_UNVERIFIED in
    # install-resq.sh. Without this, an environment variable silently chose
    # which executables got installed.
    FETCH_REF="$CRATES_COMMIT"
    verify=1
    if [ "$RESQ_CRATES_REF" != "master" ]; then
        if [ "${RESQ_ALLOW_UNVERIFIED:-0}" = "1" ]; then
            printf 'warn  RESQ_CRATES_REF=%s overrides the pinned commit; digests cannot be checked.\n' "$RESQ_CRATES_REF" >&2
            FETCH_REF="$RESQ_CRATES_REF"
            verify=0
        else
            printf 'fail  RESQ_CRATES_REF=%s cannot be verified against the pinned digests.\n' "$RESQ_CRATES_REF" >&2
            printf 'fail  Re-run with RESQ_ALLOW_UNVERIFIED=1 to install unverified hooks deliberately.\n' >&2
            exit 1
        fi
    fi

    RAW_BASE="https://raw.githubusercontent.com/resq-software/crates/$FETCH_REF/crates/resq-cli/templates/git-hooks"
    printf 'info  Fetching hooks from %s\n' "$RAW_BASE" >&2

    # Stage in a temp dir so a failed verification cannot leave a half-installed
    # or unverified hook in a directory git is about to execute from.
    umask 077
    _hk_tmp="$(mktemp -d)" || { printf 'fail  Could not create a temporary directory.\n' >&2; exit 1; }
    trap 'rm -rf "$_hk_tmp"' EXIT HUP INT QUIT TERM

    for h in $HOOKS; do
        if ! curl -fsSL --proto '=https' --tlsv1.2 "$RAW_BASE/$h" -o "$_hk_tmp/$h"; then
            printf 'fail  Could not download %s/%s\n' "$RAW_BASE" "$h" >&2
            exit 1
        fi
        if [ "$verify" = "1" ]; then
            _hk_want="$(hook_digest "$h")"
            _hk_got="$(hook_sha256 "$_hk_tmp/$h")"
            if [ "$_hk_want" != "$_hk_got" ]; then
                printf 'fail  Checksum mismatch for %s\n      expected %s\n      got      %s\n' \
                    "$h" "$_hk_want" "$_hk_got" >&2
                printf 'fail  Refusing to install unverified git hooks.\n' >&2
                exit 1
            fi
        fi
    done

    # Publish only once every hook has verified, so a mismatch on the last file
    # cannot leave the first five installed and already active.
    for h in $HOOKS; do
        cat "$_hk_tmp/$h" > "$HOOKS_DIR/$h"
        chmod +x "$HOOKS_DIR/$h"
    done
    git -C "$TARGET_ROOT" config core.hooksPath .git-hooks
    if [ "$verify" = "1" ]; then
        printf '  ok  hooks verified against pinned commit %s\n' "$CRATES_COMMIT" >&2
    fi
fi

printf '  ok  ResQ hooks installed in %s\n' "$HOOKS_DIR" >&2
printf '      Bypass once:        git commit --no-verify\n' >&2
printf '      Disable all hooks:  export GIT_HOOKS_SKIP=1\n' >&2
printf '      Add repo logic:     %s/local-<hook-name>\n' "$HOOKS_DIR" >&2

if [ -z "$RESQ_BIN" ]; then
    printf 'warn  resq backend not found. Hooks will soft-skip until you install it:\n' >&2
    printf '      curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-resq.sh | sh\n' >&2
    exit 0
fi

# ── Local-hook scaffold prompt (only when resq supports it) ─────────────────
if [ -f "$HOOKS_DIR/local-pre-push" ] || [ -n "${RESQ_SKIP_LOCAL_SCAFFOLD:-}" ]; then
    exit 0
fi
# Probe for the new `hooks scaffold-local` path first; fall back to the
# legacy `dev scaffold-local-hook` for older binaries. Skip entirely if
# neither is available (very old resq).
if "$RESQ_BIN" hooks scaffold-local --help >/dev/null 2>&1; then
    scaffold_cmd="hooks scaffold-local"
elif "$RESQ_BIN" dev scaffold-local-hook --help >/dev/null 2>&1; then
    scaffold_cmd="dev scaffold-local-hook"
else
    exit 0
fi

answer=""
if [ "${YES:-0}" = "1" ]; then
    answer="y"
elif [ -e /dev/tty ]; then
    printf 'info  Scaffold a repo-specific local-pre-push (auto-detect kind)? [y/N] ' >&2
    read -r answer < /dev/tty
fi

case "$answer" in
    [yY]|[yY][eE][sS])
        # shellcheck disable=SC2086
        (cd "$TARGET_ROOT" && "$RESQ_BIN" $scaffold_cmd --kind auto) \
            || printf 'warn  scaffold-local failed; run it manually with --kind <name>.\n' >&2
        ;;
esac
