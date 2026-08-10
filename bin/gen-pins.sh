#!/bin/sh
# Copyright 2026 ResQ Software
# SPDX-License-Identifier: Apache-2.0
#
# Maintainer tool for the get.resq.software Worker. It lives in bin/, not
# scripts/, and that distinction is load-bearing: every file in scripts/ is an
# artifact the Worker serves to users. This one must never be. Keeping it out
# of that directory keeps it out of ARTIFACT_PATHS by construction.
#
# Emits the Worker pin set as JSON on stdout, derived from every v* tag.
#
# Why derive from tags rather than track state: the output is a pure function
# of the git history, so any checkout at any time reproduces it byte for byte.
# There is no manifest to drift, and every past release keeps working because
# every past tag is still in the history.
#
# Digests are taken from git blobs. raw.githubusercontent.com serves blob
# content verbatim, so these match what the Worker will fetch — `--check`
# proves that against the live source rather than assuming it.

set -eu

# Keep in sync with ARTIFACTS in worker/src/index.js. A path listed here but
# absent from a given tag is skipped for that release, so older tags that
# predate a script simply do not offer it.
ARTIFACT_PATHS="install.sh install.ps1 scripts/install-hooks.sh scripts/install-hooks.ps1 scripts/install-resq.sh scripts/setup.sh scripts/setup.ps1"

RAW_BASE="https://raw.githubusercontent.com/resq-software/dev"

die() { printf 'gen-pins: %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v git >/dev/null 2>&1 || die "git is required"

# macOS ships shasum but not sha256sum.
if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum | cut -d' ' -f1; }
else
  sha256() { shasum -a 256 | cut -d' ' -f1; }
fi

MODE="${1:---compact}"

TAGS="$(git tag -l 'v*' | sort -V)"
[ -n "$TAGS" ] || die "no v* tags found — tag a release first (git tag v0.4.0)"
LATEST="$(printf '%s\n' "$TAGS" | tail -n 1)"

# One tab-separated row per (release, artifact). Emitted as a stream so jq can
# fold it into the nested shape without this script doing any JSON quoting.
emit_rows() {
  for tag in $TAGS; do
    commit="$(git rev-parse "$tag^{commit}")"
    for path in $ARTIFACT_PATHS; do
      # Skip artifacts that did not exist at this tag rather than failing:
      # old releases legitimately have fewer files.
      if git cat-file -e "$commit:$path" 2>/dev/null; then
        digest="$(git cat-file blob "$commit:$path" | sha256)"
        printf '%s\t%s\t%s\t%s\n' "${tag#v}" "$commit" "$path" "$digest"
      fi
    done
  done
}

build_json() {
  emit_rows | jq -R -s --arg latest "${LATEST#v}" "$@" '
    [ split("\n")[] | select(length > 0) | split("\t") ]
    | reduce .[] as $row (
        {};
        .[$row[0]].commit = $row[1]
        | .[$row[0]].artifacts[$row[2]] = $row[3]
      )
    | { latest: $latest, releases: . }
  '
}

# Confirm GitHub actually serves the bytes we are about to pin. If this fails,
# deploying would produce a Worker that fails closed on every request — better
# to find out in CI than from users whose shells get a 502.
check_remote() {
  commit="$(git rev-parse "$LATEST^{commit}")"
  printf 'gen-pins: verifying %s (%s)\n' "$LATEST" "$commit" >&2
  rc=0
  for path in $ARTIFACT_PATHS; do
    git cat-file -e "$commit:$path" 2>/dev/null || continue
    expected="$(git cat-file blob "$commit:$path" | sha256)"
    if actual="$(curl -fsSL --proto '=https' --tlsv1.2 "$RAW_BASE/$commit/$path" | sha256)"; then
      if [ "$expected" = "$actual" ]; then
        printf '  ok        %s  %s\n' "$expected" "$path" >&2
      else
        printf '  MISMATCH  %s\n    git:    %s\n    remote: %s\n' "$path" "$expected" "$actual" >&2
        rc=1
      fi
    else
      printf '  FETCH FAIL  %s\n' "$path" >&2
      rc=1
    fi
  done
  [ "$rc" -eq 0 ] || die "remote bytes do not match pinned digests — refusing to vouch for this release"
  printf 'gen-pins: all artifacts verified\n' >&2
}

# Rewrite the PINS block in the Worker source. Since the Worker is deployed by
# Cloudflare Workers Builds straight from git, the source IS the deploy — there
# is no separate injection step, and this edit is the thing that changes what
# users are served. It lands via a reviewed PR, never straight to main.
#
# The block is located structurally rather than by regex-replacing digests, so
# a malformed or partially-applied edit cannot leave half-old pins behind.
write_source() {
  target="worker/src/index.js"
  [ -f "$target" ] || die "$target not found — run from the repository root"

  # `|| true` is load-bearing: grep -c exits 1 when the count is zero, the
  # command substitution inherits that status, and `set -e` kills the script
  # right here — so the die below could never report the real problem. The
  # guard existed but was unreachable in precisely the case it was written for.
  occurrences="$(grep -c '^const PINS = {' "$target" || true)"
  [ "$occurrences" = "1" ] || die "expected exactly one 'const PINS = {' in $target, found $occurrences"

  start="$(grep -n '^const PINS = {' "$target" | cut -d: -f1)"
  end="$(awk -v s="$start" 'NR > s && /^\};/ { print NR; exit }' "$target")"
  [ -n "$end" ] || die "could not find the closing '};' of the PINS block in $target"

  json="$(build_json)"
  tmp="$(mktemp)"
  {
    head -n "$((start - 1))" "$target"
    printf 'const PINS = %s;\n' "$json"
    tail -n +"$((end + 1))" "$target"
  } > "$tmp"

  # Never leave the Worker source syntactically broken: if node cannot parse the
  # result, keep the original and fail loudly.
  #
  # Checked through a .mjs copy deliberately. `node --check` on a suffix-less
  # temp file assumes CommonJS, where the Worker's `export default` is a syntax
  # error — so checking $tmp directly rejects every correct regeneration.
  if command -v node >/dev/null 2>&1; then
    cp "$tmp" "$tmp.mjs"
    if ! node --check "$tmp.mjs" 2>/dev/null; then
      rm -f "$tmp" "$tmp.mjs"
      die "regenerated $target does not parse — original left untouched"
    fi
    rm -f "$tmp.mjs"
  fi

  if cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    printf 'gen-pins: %s already up to date\n' "$target" >&2
    return 0
  fi

  cat "$tmp" > "$target"
  rm -f "$tmp"
  printf 'gen-pins: rewrote PINS in %s (latest %s)\n' "$target" "${LATEST#v}" >&2
}

# Spelled out rather than sliced out of the header with line numbers — that
# coupling breaks silently every time the comment block above is edited.
usage() {
  cat >&2 <<'EOF'
gen-pins.sh — pin set for the get.resq.software Worker

  sh bin/gen-pins.sh            compact JSON, single line
  sh bin/gen-pins.sh --pretty   readable JSON
  sh bin/gen-pins.sh --check    assert GitHub serves exactly these pinned bytes
  sh bin/gen-pins.sh --write    rewrite the PINS block in worker/src/index.js

Derived from every v* tag, so any checkout reproduces the same output.
EOF
}

case "$MODE" in
  --compact) build_json -c ;;
  --pretty)  build_json ;;
  --check)   check_remote ;;
  --write)   write_source ;;
  -h|--help) usage ;;
  *) usage; die "unknown option '$MODE'" ;;
esac
