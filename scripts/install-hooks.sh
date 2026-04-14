#!/bin/sh
# Copyright 2026 ResQ Software
# SPDX-License-Identifier: Apache-2.0
#
# Install canonical ResQ git hooks into a repository.
#
# Usage (local — from dev/):
#     scripts/install-hooks.sh [target_dir]
#
# Usage (curl-piped — from any repo):
#     cd /path/to/repo
#     curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-hooks.sh | sh
#
# Env:
#     RESQ_DEV_REF             — git ref for raw hook fetch (default: main)
#     GIT_HOOKS_SKIP           — set to skip installation entirely
#     YES=1                    — auto-accept the local-hook scaffold prompt
#     RESQ_SKIP_LOCAL_SCAFFOLD — set to opt out of the local-hook prompt

set -eu

TARGET_DIR="${1:-$PWD}"
RESQ_DEV_REF="${RESQ_DEV_REF:-main}"

if ! git -C "$TARGET_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    printf 'fail  Not a git repository: %s\n' "$TARGET_DIR" >&2
    exit 1
fi
TARGET_ROOT="$(git -C "$TARGET_DIR" rev-parse --show-toplevel)"
HOOKS_DIR="$TARGET_ROOT/.git-hooks"
mkdir -p "$HOOKS_DIR"

# Detect whether we're running alongside the source tree (local dev/) or curl-piped.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE:-}" ] && [ -f "${BASH_SOURCE:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
elif [ -f "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

HOOKS="pre-commit commit-msg prepare-commit-msg pre-push post-checkout post-merge"

if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/git-hooks" ]; then
    printf 'info  Installing hooks from %s\n' "$SCRIPT_DIR/git-hooks" >&2
    for h in $HOOKS; do
        cp "$SCRIPT_DIR/git-hooks/$h" "$HOOKS_DIR/$h"
        chmod +x "$HOOKS_DIR/$h"
    done
else
    RAW_BASE="https://raw.githubusercontent.com/resq-software/dev/$RESQ_DEV_REF/scripts/git-hooks"
    printf 'info  Fetching hooks from %s\n' "$RAW_BASE" >&2
    for h in $HOOKS; do
        if ! curl -fsSL "$RAW_BASE/$h" -o "$HOOKS_DIR/$h"; then
            printf 'fail  Could not download %s/%s\n' "$RAW_BASE" "$h" >&2
            exit 1
        fi
        chmod +x "$HOOKS_DIR/$h"
    done
fi

git -C "$TARGET_ROOT" config core.hooksPath .git-hooks

printf '  ok  ResQ hooks installed in %s\n' "$HOOKS_DIR" >&2
printf '      Bypass once:        git commit --no-verify\n' >&2
printf '      Disable all hooks:  export GIT_HOOKS_SKIP=1\n' >&2
printf '      Add repo logic:     %s/local-<hook-name>\n' "$HOOKS_DIR" >&2

RESQ_BIN=""
if command -v resq >/dev/null 2>&1; then
    RESQ_BIN="resq"
elif [ -x "$HOME/.cargo/bin/resq" ]; then
    RESQ_BIN="$HOME/.cargo/bin/resq"
fi

if [ -z "$RESQ_BIN" ]; then
    printf 'warn  resq backend not found. Hooks will soft-skip until you install it:\n' >&2
    printf '      nix develop    (if your flake provides it)\n' >&2
    printf '      cargo install --git https://github.com/resq-software/crates resq-cli\n' >&2
    exit 0
fi

# Offer to scaffold a per-repo local-pre-push if none exists yet and resq
# supports the scaffold subcommand. Skipped silently when the resq binary
# pre-dates the subcommand or the user opts out.
if [ -f "$HOOKS_DIR/local-pre-push" ] || [ -n "${RESQ_SKIP_LOCAL_SCAFFOLD:-}" ]; then
    exit 0
fi
if ! "$RESQ_BIN" dev scaffold-local-hook --help >/dev/null 2>&1; then
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
        if (cd "$TARGET_ROOT" && "$RESQ_BIN" dev scaffold-local-hook --kind auto); then
            :
        else
            printf 'warn  scaffold-local-hook failed; run it manually with --kind <name>.\n' >&2
        fi
        ;;
esac
