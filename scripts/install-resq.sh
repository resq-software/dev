#!/bin/sh
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Install the `resq` CLI binary, preferring a GitHub Release asset for the
# host platform (fast, no toolchain required) and falling back to
# `cargo install --git` if no matching release exists.
#
# Usage (curl-piped):
#     curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/scripts/install-resq.sh | sh
#
# Usage (local — from dev/):
#     scripts/install-resq.sh [version]
#
# Args:
#     [version]   Tag name without the leading 'resq-cli-v' (default: latest).
#                 e.g. `0.3.0` to install resq-cli-v0.3.0.
#
# Env:
#     RESQ_INSTALL_DIR   — install destination (default: $HOME/.local/bin or
#                          $HOME/.cargo/bin if cargo is present)
#     RESQ_FORCE_CARGO=1 — skip the release-binary path and always cargo-install
#     RESQ_REQUIRE_PROVENANCE=1
#                        — refuse to install unless the release's Sigstore
#                          attestation was verified (needs an authenticated gh
#                          2.68+); by default a missing gh only warns
#     RESQ_ALLOW_UNVERIFIED=1
#                        — proceed when the download cannot be verified (no
#                          SHA256SUMS, no hashing tool, provenance unreachable).
#                          Never overrides a check that ran and failed.
#
# Writes an install receipt to ${XDG_CONFIG_HOME:-$HOME/.config}/resq/install.json.

set -eu

REPO="resq-software/crates"
TAG_PREFIX="resq-cli-v"
WANTED_VERSION="${1:-}"

BIN_NAME="resq"
DEST_DIR="${RESQ_INSTALL_DIR:-}"
if [ -z "$DEST_DIR" ]; then
    if [ -d "$HOME/.cargo/bin" ]; then
        DEST_DIR="$HOME/.cargo/bin"
    else
        DEST_DIR="$HOME/.local/bin"
    fi
fi
mkdir -p "$DEST_DIR"

info() { printf 'info  %s\n' "$*" >&2; }
warn() { printf 'warn  %s\n' "$*" >&2; }
fail() { printf 'fail  %s\n' "$*" >&2; exit 1; }

# sha256 of a file, or nothing when no hashing tool exists (macOS has shasum only).
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# ── Install receipt ──────────────────────────────────────────────────────────
#
# Records what installed the binary and how, at
# ${XDG_CONFIG_HOME:-$HOME/.config}/resq/install.json. A background
# `resq self update` (resq-software/crates) is to replace only a binary whose
# receipt says "method": "release" for that exact path, so a cargo-, nix- or
# hand-built resq is never overwritten behind its owner's back. A cargo install
# writes "method": "cargo" for the same reason: the release path and cargo's
# default share ~/.cargo/bin, and a stale "release" receipt must not outlive it.
# A receipt that cannot be written is a warning, never a failed install.
json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
write_receipt() {  # <method> <ref> <path> <sha256> <provenance>
    _rc_dir="${XDG_CONFIG_HOME:-$HOME/.config}/resq"
    if mkdir -p "$_rc_dir" 2>/dev/null && {
        printf '{\n'
        printf '  "schema": 1,\n'
        printf '  "method": "%s",\n' "$1"
        printf '  "ref": "%s",\n' "$(json_str "$2")"
        printf '  "path": "%s",\n' "$(json_str "$3")"
        printf '  "sha256": "%s",\n' "$4"
        printf '  "provenance": "%s",\n' "$5"
        printf '  "installed_at": "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '}\n'
    } > "$_rc_dir/install.json.tmp" 2>/dev/null \
      && mv -f "$_rc_dir/install.json.tmp" "$_rc_dir/install.json"; then
        :
    else
        warn "Could not write the install receipt in $_rc_dir."
    fi
}

# ── Detect host triple ───────────────────────────────────────────────────────
detect_target() {
    os=$(uname -s)
    arch=$(uname -m)
    case "$os/$arch" in
        Linux/x86_64)        echo "x86_64-unknown-linux-gnu" ;;
        Linux/aarch64|Linux/arm64) echo "aarch64-unknown-linux-gnu" ;;
        Darwin/x86_64)       echo "x86_64-apple-darwin" ;;
        Darwin/arm64)        echo "aarch64-apple-darwin" ;;
        *)                   echo "" ;;
    esac
}
TARGET="$(detect_target)"

# ── Cargo-install fallback (used by 3 paths below) ───────────────────────────
#
# Release binaries ship from resq-cli 0.5.0 on, so this now runs only for an
# unsupported host, a release without an asset for this platform, an explicit
# pre-0.5.0 version, or RESQ_FORCE_CARGO=1. It is never reached because the
# GitHub API failed: that stops the install instead (see api_fail below).
#
# It used to end in `cargo install --git <repo> resq-cli` with no --rev and no
# --tag, which builds whatever the default branch points at that second. The
# Worker hands this script over pinned to a commit and verified byte for byte,
# and the script then discarded that guarantee one hop later. It was also the
# only unverified branch in this repo not gated by RESQ_ALLOW_UNVERIFIED — the
# silent default rather than a deliberate choice.
#
# Bump alongside CRATES_COMMIT in scripts/install-hooks.sh when moving to a newer
# crates revision. required.yml checks this commit exists and is an ancestor of
# the crates default branch, so a typo or a rebased-away commit fails CI rather
# than every user's install.
CRATES_COMMIT="72e0ae4952624ccd5cf39adc632e15b3d91b86c9"

cargo_install() {
    if ! command -v cargo >/dev/null 2>&1; then
        fail "cargo not found and no release binary available — install Rust (https://rustup.rs) and re-run."
    fi

    if [ -n "$WANTED_VERSION" ]; then
        # An explicit version is a request for that tag, so honour it. Weaker
        # than a commit pin — a tag can be force-moved by anyone with write
        # access, where a commit SHA cannot — but the user named this version,
        # and quietly building a different one would be worse.
        info "Installing resq-cli at tag ${TAG_PREFIX}${WANTED_VERSION} via cargo ..."
        cargo install --git "https://github.com/$REPO" --tag "${TAG_PREFIX}${WANTED_VERSION}" resq-cli
        _cargo_ref="${TAG_PREFIX}${WANTED_VERSION}"
    elif [ "${RESQ_ALLOW_UNVERIFIED:-0}" = "1" ]; then
        warn "Building resq-cli from the $REPO default branch — unpinned, whatever it points at right now (RESQ_ALLOW_UNVERIFIED=1)."
        cargo install --git "https://github.com/$REPO" resq-cli
        _cargo_ref="default-branch"
    else
        # The default: a commit SHA, which cannot be repointed.
        info "Installing resq-cli from pinned commit $CRATES_COMMIT via cargo ..."
        cargo install --git "https://github.com/$REPO" --rev "$CRATES_COMMIT" resq-cli
        _cargo_ref="$CRATES_COMMIT"
    fi

    _cargo_bin="${CARGO_INSTALL_ROOT:-${CARGO_HOME:-$HOME/.cargo}}/bin/$BIN_NAME"
    write_receipt cargo "$_cargo_ref" "$_cargo_bin" "$(sha256_of "$_cargo_bin" 2>/dev/null)" "n/a"
}

if [ "${RESQ_FORCE_CARGO:-0}" = "1" ]; then
    cargo_install
    exit 0
fi

if [ -z "$TARGET" ]; then
    warn "Unsupported host ($(uname -s)/$(uname -m)) for prebuilt binary — falling back to cargo."
    cargo_install
    exit 0
fi

# ── Resolve release tag ──────────────────────────────────────────────────────
#
# Every GitHub API response is captured on its own, so a failed request stops
# the install. These were `curl ... | sed | head` pipelines under `set -eu`
# without pipefail: an API error (network, proxy, the 60/hour unauthenticated
# rate limit) came out as an empty tag, read as "no release exists", and the
# script quietly fell through to building from source.
api_fail() {
    fail "GitHub API request failed: $1. Check network/proxy/rate limit and re-run, or set RESQ_FORCE_CARGO=1 to build the pinned commit from source."
}

if [ -n "$WANTED_VERSION" ]; then
    TAG="${TAG_PREFIX}${WANTED_VERSION}"
else
    releases_json="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=100")" \
        || api_fail "could not list $REPO releases"
    # The highest stable resq-cli-vX.Y.Z by number. The API orders releases by
    # creation date and this repository releases several crates at once, so
    # the first match was the newest-created, not the newest version. A
    # pre-release is never picked; drafts are not returned to this caller.
    TAG="$(printf '%s\n' "$releases_json" | awk '
            /"tag_name":/   { t = $0; sub(/.*"tag_name":[[:space:]]*"/, "", t); sub(/".*/, "", t); next }
            /"prerelease":/ { if (t != "" && $0 ~ /false/) print t; t = "" }' \
        | sed -n "s/^${TAG_PREFIX}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\$/\1/p" \
        | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    [ -z "$TAG" ] || TAG="${TAG_PREFIX}${TAG}"
fi
if [ -z "$TAG" ]; then
    warn "No $TAG_PREFIX* release found — falling back to cargo."
    cargo_install
    exit 0
fi
info "Resolved release tag: $TAG"
TAG_VERSION="${TAG#"$TAG_PREFIX"}"

# ── Find platform asset ──────────────────────────────────────────────────────
release_json="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$TAG")" \
    || api_fail "could not read release $TAG (does it exist?)"
asset_url=$(printf '%s\n' "$release_json" \
    | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -F "$TARGET" \
    | grep -E '\.tar\.gz$|\.zip$' \
    | head -1)
sums_url=$(printf '%s\n' "$release_json" \
    | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*SHA256SUMS[^"]*\)".*/\1/p' \
    | head -1)

if [ -z "$asset_url" ]; then
    warn "No asset for $TARGET in $TAG — falling back to cargo."
    cargo_install
    exit 0
fi

# ── Download + verify ────────────────────────────────────────────────────────
tmp=$(mktemp -d)
staged=""
trap 'rm -rf "$tmp"; [ -z "$staged" ] || rm -f "$staged"' EXIT
# dash (the /bin/sh curl|sh usually lands in) does not run EXIT traps on a fatal
# signal, so an interrupt mid-install would leave the staged binary behind.
# Exiting from the signal handler runs the EXIT trap above.
trap 'exit 130' HUP INT QUIT TERM

asset_name=$(basename "$asset_url")
info "Downloading $asset_name ..."
curl -fsSL "$asset_url" -o "$tmp/$asset_name"

# Integrity gate: FAIL CLOSED. An installer that downloads + installs a binary
# must refuse to proceed when it cannot verify the artifact. Every "can't
# verify" branch aborts unless the operator explicitly opts out.
allow_unverified="${RESQ_ALLOW_UNVERIFIED:-0}"
if [ -n "$sums_url" ]; then
    info "Verifying SHA256 against SHA256SUMS ..."
    curl -fsSL "$sums_url" -o "$tmp/SHA256SUMS"
    # Exact filename-column match (text "  name" and binary " *name"); a plain
    # grep -F would also match name.sig/.sha256 lines and yield multiple hashes.
    expected=$(awk -v a="$asset_name" '$2 == a || $2 == "*"a {print $1}' "$tmp/SHA256SUMS")
    if [ -z "$expected" ]; then
        if [ "$allow_unverified" = "1" ]; then
            warn "Asset not listed in SHA256SUMS — proceeding (RESQ_ALLOW_UNVERIFIED=1)."
        else
            fail "Asset not listed in SHA256SUMS — refusing to install unverified (set RESQ_ALLOW_UNVERIFIED=1 to override)."
        fi
    else
        actual="$(sha256_of "$tmp/$asset_name")"
        if [ -z "$actual" ]; then
            if [ "$allow_unverified" = "1" ]; then
                warn "No sha256sum/shasum available — proceeding unverified (RESQ_ALLOW_UNVERIFIED=1)."
            else
                fail "No sha256sum/shasum tool to verify the download — refusing (install coreutils, or set RESQ_ALLOW_UNVERIFIED=1)."
            fi
        elif [ "$expected" != "$actual" ]; then
            fail "SHA256 mismatch for $asset_name (expected $expected, got $actual)."
        fi
    fi
elif [ "$allow_unverified" = "1" ]; then
    warn "No SHA256SUMS in release — proceeding unverified (RESQ_ALLOW_UNVERIFIED=1)."
else
    fail "No SHA256SUMS in release — refusing to install unverified (set RESQ_ALLOW_UNVERIFIED=1 to override)."
fi

# ── Verify build provenance ──────────────────────────────────────────────────
#
# SHA256SUMS comes from the same release as the archive, so it proves only that
# the download is intact — anyone able to publish the release can publish
# matching sums. The Sigstore attestation proves who built it: release.yml in
# resq-software/crates, running at this tag, on a GitHub-hosted runner, from the
# commit the tag names, and that commit is on master. The signer is matched
# EXACTLY (--cert-identity); --signer-workflow would accept any workflow path
# with that prefix.
#
# Needs an authenticated gh 2.68+ (`attestation verify --source-digest`). Without one, the
# install continues on the checksum alone and says so; RESQ_REQUIRE_PROVENANCE=1
# makes that fatal. RESQ_ALLOW_UNVERIFIED=1 skips the check deliberately (for
# when Sigstore or the API is unreachable). A check that RUNS and FAILS is never
# overridable, like a checksum mismatch.
provenance="unchecked"
if [ "$allow_unverified" = "1" ] && [ "${RESQ_REQUIRE_PROVENANCE:-0}" = "1" ]; then
    fail "RESQ_REQUIRE_PROVENANCE=1 and RESQ_ALLOW_UNVERIFIED=1 contradict each other — unset one."
elif [ "$allow_unverified" = "1" ]; then
    warn "Build provenance NOT checked (RESQ_ALLOW_UNVERIFIED=1)."
# Probe for the flag the check uses, not just the subcommand: gh 2.49-2.67 has
# `attestation verify` without --source-ref/--source-digest (added in 2.68.0),
# and on those every check would "fail" and refuse a good release.
elif command -v gh >/dev/null 2>&1 \
        && gh attestation verify --help 2>&1 | grep -q -- '--source-digest' \
        && gh auth status >/dev/null 2>&1; then
    info "Verifying build provenance (Sigstore attestation) ..."
    tag_sha="$(gh api "repos/$REPO/commits/$TAG" --jq .sha 2>/dev/null)" || tag_sha=""
    [ -n "$tag_sha" ] || fail "Could not resolve $TAG to a commit to check its provenance."
    tag_status="$(gh api "repos/$REPO/compare/master...$tag_sha" --jq .status 2>/dev/null)" || tag_status=""
    case "$tag_status" in
        identical|behind) ;;
        *) fail "$TAG points at $tag_sha, which is not on $REPO master (${tag_status:-unknown}) — refusing a release built from unmerged code." ;;
    esac
    if ! attest_out="$(gh attestation verify "$tmp/$asset_name" --repo "$REPO" \
            --cert-identity "https://github.com/$REPO/.github/workflows/release.yml@refs/tags/$TAG" \
            --cert-oidc-issuer "https://token.actions.githubusercontent.com" \
            --source-ref "refs/tags/$TAG" --source-digest "$tag_sha" \
            --deny-self-hosted-runners 2>&1)"; then
        printf '%s\n' "$attest_out" >&2
        fail "Build provenance verification FAILED for $asset_name ($TAG) — refusing to install."
    fi
    provenance="verified"
    info "Provenance verified: built by release.yml at $TAG ($tag_sha)."
elif [ "${RESQ_REQUIRE_PROVENANCE:-0}" = "1" ]; then
    fail "RESQ_REQUIRE_PROVENANCE=1, but no authenticated gh 2.68+ (with 'attestation verify --source-digest') is available to check it."
else
    warn "Build provenance NOT checked — needs an authenticated gh 2.68+. Trusting SHA256SUMS alone."
fi

# ── Extract ──────────────────────────────────────────────────────────────────
case "$asset_name" in
    *.tar.gz) tar -xzf "$tmp/$asset_name" -C "$tmp" ;;
    *.zip)    (cd "$tmp" && unzip -q "$asset_name") ;;
    *)        fail "Unknown archive format: $asset_name" ;;
esac

# Find the binary anywhere under the extracted tree
src_bin=$(find "$tmp" -type f -name "$BIN_NAME" -perm -u+x | head -1)
if [ -z "$src_bin" ]; then
    src_bin=$(find "$tmp" -type f -name "$BIN_NAME" | head -1)
fi
[ -n "$src_bin" ] || fail "Could not locate '$BIN_NAME' inside $asset_name."

# ── Install ──────────────────────────────────────────────────────────────────
#
# The new binary has to run and report the version the tag names before it may
# replace anything. It is then staged beside the target and renamed into place,
# so an interrupted install never leaves a half-written resq; the binary it
# replaces is kept as resq.prev.
chmod 0755 "$src_bin"
new_version="$("$src_bin" --version 2>/dev/null | head -1)" || new_version=""
case "$new_version" in
    *" $TAG_VERSION"|*" v$TAG_VERSION") ;;
    *) fail "$asset_name reports '${new_version:-nothing}' for --version, not $TAG_VERSION — refusing to install it." ;;
esac

staged="$DEST_DIR/.$BIN_NAME.new.$$"
install -m 0755 "$src_bin" "$staged"
if [ -f "$DEST_DIR/$BIN_NAME" ]; then
    cp -p "$DEST_DIR/$BIN_NAME" "$DEST_DIR/$BIN_NAME.prev" \
        || warn "Could not keep the previous binary as $BIN_NAME.prev."
fi
mv -f "$staged" "$DEST_DIR/$BIN_NAME"
staged=""
info "Installed $DEST_DIR/$BIN_NAME"
write_receipt release "$TAG" "$DEST_DIR/$BIN_NAME" "$(sha256_of "$DEST_DIR/$BIN_NAME")" "$provenance"

case ":$PATH:" in
    *":$DEST_DIR:"*) ;;
    *) warn "$DEST_DIR is not on PATH. Add it to your shell profile, e.g.:" >&2
       printf '      export PATH="%s:$PATH"\n' "$DEST_DIR" >&2 ;;
esac

"$DEST_DIR/$BIN_NAME" --version 2>&1 | head -1 | sed 's/^/  ok  /'
