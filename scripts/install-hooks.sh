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
if [ -n "$RESQ_BIN" ]; then
    printf 'info  Installing hooks via %s dev install-hooks\n' "$RESQ_BIN" >&2
    (cd "$TARGET_ROOT" && "$RESQ_BIN" dev install-hooks)
else
    # ── Path 2: fall back to raw fetch from crates templates ────────────────
    HOOKS="pre-commit commit-msg prepare-commit-msg pre-push post-checkout post-merge"
    RAW_BASE="https://raw.githubusercontent.com/resq-software/crates/$RESQ_CRATES_REF/crates/resq-cli/templates/git-hooks"
    printf 'info  Fetching hooks from %s\n' "$RAW_BASE" >&2
    for h in $HOOKS; do
        if ! curl -fsSL "$RAW_BASE/$h" -o "$HOOKS_DIR/$h"; then
            printf 'fail  Could not download %s/%s\n' "$RAW_BASE" "$h" >&2
            exit 1
        fi
        chmod +x "$HOOKS_DIR/$h"
    done
    git -C "$TARGET_ROOT" config core.hooksPath .git-hooks
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
        (cd "$TARGET_ROOT" && "$RESQ_BIN" dev scaffold-local-hook --kind auto) \
            || printf 'warn  scaffold-local-hook failed; run it manually with --kind <name>.\n' >&2
        ;;
esac
