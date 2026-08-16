#!/bin/sh
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Asserts how scripts/install-resq.sh invokes cargo.
#
# Why this exists: the cargo fallback is the ONLY path that runs today, because
# resq-software/crates publishes no resq-cli-v* release for resolve_tag to find.
# It used to build from the default branch with no --rev and no --tag — an
# unpinned build of a moving target, reached by `curl .../resq.sh | sh`, and the
# one unverified branch in this repo that RESQ_ALLOW_UNVERIFIED did not gate.
#
# The property under test is therefore: an unpinned build cannot happen by
# accident, only by asking for one.
#
# cargo is stubbed on PATH and records its argv; nothing is compiled and no
# network is touched (RESQ_FORCE_CARGO=1 short-circuits before the release
# lookup). Run directly with: sh tests/installers/pinning.sh

set -eu

SCRIPT="${1:-scripts/install-resq.sh}"
[ -f "$SCRIPT" ] || { printf 'fail  %s not found — run from the repository root\n' "$SCRIPT" >&2; exit 1; }

pass=0
fail=0
check() {
    if [ "$2" = "0" ]; then
        pass=$((pass + 1)); printf '  PASS  %s\n' "$1"
    else
        fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"
        if [ -n "${3:-}" ]; then printf '        %s\n' "$3"; fi
    fi
}

# Fresh sandbox per invocation: a stub cargo that records its arguments, and a
# throwaway install destination, so nothing here can reach a real toolchain.
run_install() {
    _tmp="$(mktemp -d)"
    mkdir -p "$_tmp/bin" "$_tmp/dest"
    cat > "$_tmp/bin/cargo" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" > "$CARGO_ARGV_OUT"
STUB
    chmod +x "$_tmp/bin/cargo"

    CARGO_ARGV_OUT="$_tmp/argv" \
    PATH="$_tmp/bin:$PATH" \
    RESQ_FORCE_CARGO=1 \
    RESQ_INSTALL_DIR="$_tmp/dest" \
    "$@" >/dev/null 2>&1 || true

    cat "$_tmp/argv" 2>/dev/null || printf ''
    rm -rf "$_tmp"
}

PINNED="$(sed -n 's/^CRATES_COMMIT="\(.*\)"$/\1/p' "$SCRIPT")"

printf '\n== install-resq.sh cargo pinning ==\n'

r=1
if [ "${#PINNED}" -eq 40 ]; then
    case "$PINNED" in
        *[!0-9a-f]*) r=1 ;;
        *) r=0 ;;
    esac
fi
check "CRATES_COMMIT is a 40-hex commit SHA" "$r" "got '$PINNED'"

# 1. The default must pin. This is the assertion that matters: it is what runs
#    for every user who types the documented curl command.
argv="$(run_install sh "$SCRIPT")"
case "$argv" in
    *"--rev $PINNED"*) r=0 ;;
    *) r=1 ;;
esac
check "default build pins --rev to CRATES_COMMIT" "$r" "cargo $argv"

case "$argv" in
    *--tag*) r=1 ;;
    *) r=0 ;;
esac
check "default build does not use a movable tag" "$r" "cargo $argv"

# 2. The unpinned form must be unreachable without an explicit opt-out. Asserted
#    as "no --rev AND no --tag", not merely "differs from the default", so a
#    later edit cannot satisfy this by pinning something else.
argv="$(RESQ_ALLOW_UNVERIFIED=1 run_install sh "$SCRIPT")"
case "$argv" in
    *--rev*|*--tag*) r=1 ;;
    *resq-cli*) r=0 ;;
    *) r=1 ;;
esac
check "RESQ_ALLOW_UNVERIFIED=1 opts in to an unpinned build" "$r" "cargo $argv"

# 3. An explicit version still resolves to that tag — the guard must not break
#    the documented `install-resq.sh 0.3.0` form.
argv="$(run_install sh "$SCRIPT" 0.3.0)"
case "$argv" in
    *"--tag resq-cli-v0.3.0"*) r=0 ;;
    *) r=1 ;;
esac
check "explicit version installs that tag" "$r" "cargo $argv"

printf '\n%s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
