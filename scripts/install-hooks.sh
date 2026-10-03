#!/bin/sh
# Copyright 2026 ResQ Systems, Inc.
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

# ── Is that resq new enough to supply the hooks? ────────────────────────────
# Path 1 installs the templates EMBEDDED in the binary, so an old resq installs
# old hooks. Before resq-cli 0.4.3 (resq-software/crates#206) they carried the
# blanket `[ -n "$GIT_HOOKS_SKIP" ] && exit 0` guard, under which a
# granular-looking GIT_HOOKS_SKIP=audit also disabled the secret scan. A binary
# below this floor, or one whose version cannot be read, gets the pinned,
# digest-verified templates from path 2 instead. 0.4.3 through the pinned
# 0.5.2 embed templates byte-identical to the pinned ones.
RESQ_MIN_HOOKS_VERSION="0.4.3"

# version_at_least <have> <want> — numeric X.Y.Z comparison, POSIX sh.
version_at_least() {
    _va_have="$1"; _va_want="$2"
    for _va_i in 1 2 3; do
        _va_h="$(printf '%s' "$_va_have" | cut -d. -f"$_va_i")"
        _va_w="$(printf '%s' "$_va_want" | cut -d. -f"$_va_i")"
        [ "${_va_h:-0}" -gt "${_va_w:-0}" ] && return 0
        [ "${_va_h:-0}" -lt "${_va_w:-0}" ] && return 1
    done
    return 0
}

RESQ_TEMPLATES_OK=0
if [ -n "$RESQ_BIN" ]; then
    resq_version="$("$RESQ_BIN" --version 2>/dev/null | head -1 \
        | sed -n 's/^resq[^ ]* v\{0,1\}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
    if [ -n "$resq_version" ] && version_at_least "$resq_version" "$RESQ_MIN_HOOKS_VERSION"; then
        RESQ_TEMPLATES_OK=1
    else
        printf 'warn  %s reports version %s; its embedded hooks predate the granular\n' \
            "$RESQ_BIN" "${resq_version:-<unreadable>}" >&2
        printf '      GIT_HOOKS_SKIP fix (needs >= %s). Installing the pinned, verified hooks\n' \
            "$RESQ_MIN_HOOKS_VERSION" >&2
        printf '      instead. Upgrade resq too — the new hooks may pass it flags it lacks:\n' >&2
        printf '      curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-resq.sh | sh\n' >&2
    fi
fi

# ── Path 1: use resq when present (preferred — offline, no raw fetch) ───────
# Prefer the new `hooks install` path; fall back to `dev install-hooks` for
# binaries built before resq-software/crates#60.
if [ "$RESQ_TEMPLATES_OK" = 1 ]; then
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
    CRATES_COMMIT="72e0ae4952624ccd5cf39adc632e15b3d91b86c9"

    hook_digest() {
        case "$1" in
            pre-commit)         echo "fd2d275571d431a8cb897a047176f0da9a096ef76a111a0ef0147bb10ba83ffc" ;;
            commit-msg)         echo "d33ecc52661d43aabaeae1d789df04c709ece41e37fd224b6940c7639ac2a6ef" ;;
            prepare-commit-msg) echo "4fa2e7abf284adc93da750b9c4387de781dd552874290c81885c5dc19debe99b" ;;
            pre-push)           echo "84f1d08fa54baa592d5cc3519ac85cba69d59bc1d502ca8d821cb8f30dde53ce" ;;
            post-checkout)      echo "aeacd20d8d42d75586f147f8cf92d5ae68eb0e7c9fbe99f7cd1838904f943180" ;;
            post-merge)         echo "32d3e73e5b894b7a42c21075192262997e7a953b84a18f89901cf579a431ab2c" ;;
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
    # EXIT and the signals get SEPARATE handlers, and the signal one exits.
    # Same defect install.sh carried: a trap on a non-EXIT signal runs its
    # handler and then RESUMES — it does not terminate. Here that meant Ctrl-C
    # during the fetch deleted the staging directory and then carried on into
    # the publish loop, reading from a directory that no longer existed.
    #
    # install.sh was fixed first and this was deliberately deferred to its own
    # change, because it is a separate pinned artifact whose digest is stamped.
    # This is that change.
    trap 'rm -rf "$_hk_tmp"' EXIT
    trap 'rm -rf "$_hk_tmp"; exit 130' HUP INT QUIT TERM

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
    #
    # Each file lands by atomic rename rather than being truncated in place.
    # This used to be `cat "$_hk_tmp/$h" > "$HOOKS_DIR/$h"`, where the redirect
    # truncates the destination BEFORE writing — so an interrupt mid-write left
    # a truncated hook that git would still execute. A rename is atomic within a
    # filesystem: every hook is either entirely the old one or entirely the new
    # one, never half a file.
    #
    # The staging name sits inside HOOKS_DIR on purpose. Renaming out of the
    # mktemp directory would usually cross a filesystem boundary (/tmp), where
    # mv silently degrades to copy-then-unlink and the atomicity is lost.
    #
    # This makes each FILE atomic, not the set: an interrupt between hooks can
    # still leave a mix of old and new, each individually valid. Making the set
    # atomic would mean swapping the whole directory, which would discard the
    # local-<hook> customisations this design deliberately keeps there.
    for h in $HOOKS; do
        if ! cp "$_hk_tmp/$h" "$HOOKS_DIR/.$h.new"; then
            printf 'fail  Could not stage %s into %s\n' "$h" "$HOOKS_DIR" >&2
            exit 1
        fi
        chmod +x "$HOOKS_DIR/.$h.new"
        if ! mv -f "$HOOKS_DIR/.$h.new" "$HOOKS_DIR/$h"; then
            printf 'fail  Could not publish %s\n' "$h" >&2
            exit 1
        fi
    done
    git -C "$TARGET_ROOT" config core.hooksPath .git-hooks
    if [ "$verify" = "1" ]; then
        printf '  ok  hooks verified against pinned commit %s\n' "$CRATES_COMMIT" >&2
    fi
fi

printf '  ok  ResQ hooks installed in %s\n' "$HOOKS_DIR" >&2
printf '      Bypass once:        git commit --no-verify\n' >&2
printf '      Skip one check:     export GIT_HOOKS_SKIP=audit   (or format, versioning,\n' >&2
printf '                          msg-format, wip-guard, force-push, branch-name, notify,\n' >&2
printf '                          local — comma-separate to combine)\n' >&2
printf '      Disable ALL checks: export GIT_HOOKS_SKIP=all\n' >&2
printf '                          GIT_HOOKS_SKIP is a list of check names, not a boolean.\n' >&2
printf '                          An unrecognised value fails closed, and every skip is\n' >&2
printf '                          announced — if you saw no banner, nothing was skipped.\n' >&2
printf '                          The secret scan has no token; only the all-off value\n' >&2
printf '                          (all/1/true/yes/on) or --no-verify disables it.\n' >&2
printf '                          prepare-commit-msg ignores GIT_HOOKS_SKIP entirely.\n' >&2
printf '      Add repo logic:     %s/local-<hook-name>\n' "$HOOKS_DIR" >&2

if [ -z "$RESQ_BIN" ]; then
    # The installed pre-commit fails closed without resq: it refuses the commit
    # rather than let an unscanned change through. Saying "soft-skip" here
    # (true of hooks before resq-software/crates#206) told a first-time user
    # their commits would pass while every one was refused.
    printf 'warn  resq backend not found. Until it is installed, pre-commit REFUSES every\n' >&2
    printf '      commit (no checks can run, so none are waived). Install it:\n' >&2
    printf '      curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-resq.sh | sh\n' >&2
    printf '      To commit without it on purpose: GIT_HOOKS_SKIP=all, or git commit --no-verify.\n' >&2
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
