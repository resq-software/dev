#!/bin/sh
# Copyright 2026 ResQ Software
# SPDX-License-Identifier: Apache-2.0
#
# Propagate the single authored version, plus the hook-installer digests, into
# both installers.
#
#   sh bin/stamp.sh           # rewrite install.sh and install.ps1 in place
#   sh bin/stamp.sh --check   # fail if rewriting would change anything
#
# WHY STAMP RATHER THAN READ A SHARED FILE
#
# install.sh and install.ps1 are curl-piped single files. When they run there is
# no repository on disk, so they cannot read VERSION or hash install-hooks.*
# themselves — the values have to be baked in. Stamping keeps exactly one
# authored copy (VERSION, and the hook files themselves) and treats every
# embedded literal as generated output.
#
# --check verifies by regeneration rather than by comparing strings: CI runs the
# same transformation and fails if the result differs from what is committed. A
# stamped value cannot be silently forgotten, because forgetting it is a diff.
#
# ORDERING: stamp, merge, then tag. The tag has to land on a commit that already
# declares its own version, or the artifacts published at v0.4.0 would claim to
# be v0.3.0.

set -eu

die() { printf 'stamp: %s\n' "$*" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum < "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 < "$1" | cut -d' ' -f1; }
else
  die "neither sha256sum nor shasum is available"
fi

MODE="${1:---write}"

case "$MODE" in
  --write|--check) ;;
  -h|--help)
    cat >&2 <<'EOF'
stamp.sh — propagate VERSION and hook digests into the installers

  sh bin/stamp.sh           rewrite install.sh and install.ps1 in place
  sh bin/stamp.sh --check   fail if rewriting would change anything

VERSION is the only authored copy. Stamp, merge, then tag.
EOF
    exit 0
    ;;
  *) die "unknown option '$MODE' (try --write, --check)" ;;
esac

[ -f VERSION ] || die "VERSION not found — run from the repository root"

# Tolerate a trailing newline and stray whitespace, reject anything else. A
# malformed version gets stamped into a URL that then 404s at install time.
VERSION="$(tr -d ' \t\r\n' < VERSION)"
# Rejecting only non-numeric characters was too loose: '1..2', '...' and
# '1.2.3.4' all passed. Each becomes a URL path segment (/v$VERSION/hooks.ps1)
# that would 404 on a user's machine at install time, so validate the shape.
case "$VERSION" in
  ''|*[!0-9.]*|.*|*.|*..*)
    die "VERSION must look like MAJOR.MINOR.PATCH, got '$VERSION'" ;;
esac
_dots="$(printf '%s' "$VERSION" | tr -cd '.' | wc -c | tr -d ' ')"
[ "$_dots" = "2" ] || die "VERSION must have exactly three components, got '$VERSION'"

for f in install.sh install.ps1 scripts/install-hooks.sh scripts/install-hooks.ps1; do
  [ -f "$f" ] || die "$f not found — run from the repository root"
done

HOOKS_SH="$(sha256 scripts/install-hooks.sh)"
HOOKS_PS1="$(sha256 scripts/install-hooks.ps1)"

# Every rule is anchored to the start of a line and rewrites only the literal,
# so the same name appearing in a comment is left alone.
stamp_sh() {
  sed \
    -e "s|^SCRIPT_VERSION=\".*\"\$|SCRIPT_VERSION=\"$VERSION\"|" \
    -e "s|^HOOKS_SHA256=\".*\"\$|HOOKS_SHA256=\"$HOOKS_SH\"|" \
    "$1"
}

stamp_ps1() {
  sed \
    -e "s|^\\\$ScriptVersion  = '.*'|\$ScriptVersion  = '$VERSION'|" \
    -e "s|^\\\$HooksSha256    = '.*'|\$HooksSha256    = '$HOOKS_PS1'|" \
    "$1"
}

# Guard against a rename or reformat quietly turning stamping into a no-op. If a
# literal we expect to rewrite is missing, the file has drifted from what this
# script understands, and the output would look clean while being stale.
assert_present() {
  grep -q "$2" "$1" || die "$1 has no line matching /$2/ — stamp.sh needs updating"
}

assert_present install.sh  '^SCRIPT_VERSION="'
assert_present install.sh  '^HOOKS_SHA256="'
assert_present install.ps1 "^\\\$ScriptVersion  = '"
assert_present install.ps1 "^\\\$HooksSha256    = '"

CHANGED=0

apply() {  # file stamper
  _ap_tmp="$(mktemp)"
  "$2" "$1" > "$_ap_tmp"
  if cmp -s "$_ap_tmp" "$1"; then
    rm -f "$_ap_tmp"
    return 0
  fi
  CHANGED=1
  if [ "$MODE" = "--check" ]; then
    printf 'stamp: %s is out of date\n' "$1" >&2
    diff -u "$1" "$_ap_tmp" >&2 || true
    rm -f "$_ap_tmp"
  else
    cat "$_ap_tmp" > "$1"
    rm -f "$_ap_tmp"
    printf 'stamp: updated %s\n' "$1" >&2
  fi
}

apply install.sh  stamp_sh
apply install.ps1 stamp_ps1

if [ "$MODE" = "--check" ]; then
  [ "$CHANGED" -eq 0 ] || die "installers are out of sync with VERSION — run: sh bin/stamp.sh"
  printf 'stamp: in sync (version %s, hooks.sh %.12s…, hooks.ps1 %.12s…)\n' \
    "$VERSION" "$HOOKS_SH" "$HOOKS_PS1" >&2
elif [ "$CHANGED" -eq 0 ]; then
  printf 'stamp: already in sync (version %s)\n' "$VERSION" >&2
fi
