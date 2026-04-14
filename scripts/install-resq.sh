#!/bin/sh
# Copyright 2026 ResQ Software
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

# ── Cargo-install fallback (used by 2 paths below) ───────────────────────────
cargo_install() {
    if ! command -v cargo >/dev/null 2>&1; then
        fail "cargo not found and no release binary available — install Rust (https://rustup.rs) and re-run."
    fi
    info "Installing via cargo install --git $REPO resq-cli ..."
    if [ -n "$WANTED_VERSION" ]; then
        cargo install --git "https://github.com/$REPO" --tag "${TAG_PREFIX}${WANTED_VERSION}" resq-cli
    else
        cargo install --git "https://github.com/$REPO" resq-cli
    fi
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
resolve_tag() {
    if [ -n "$WANTED_VERSION" ]; then
        echo "${TAG_PREFIX}${WANTED_VERSION}"
        return
    fi
    # Find newest resq-cli-v* tag via the releases endpoint.
    url="https://api.github.com/repos/$REPO/releases"
    curl -fsSL "$url" \
        | sed -n 's/.*"tag_name":[[:space:]]*"\(resq-cli-v[^"]*\)".*/\1/p' \
        | head -1
}
TAG="$(resolve_tag)"
if [ -z "$TAG" ]; then
    warn "No $TAG_PREFIX* release found — falling back to cargo."
    cargo_install
    exit 0
fi
info "Resolved release tag: $TAG"

# ── Find platform asset ──────────────────────────────────────────────────────
asset_url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
    | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep -F "$TARGET" \
    | grep -E '\.tar\.gz$|\.zip$' \
    | head -1)
sums_url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
    | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*SHA256SUMS[^"]*\)".*/\1/p' \
    | head -1)

if [ -z "$asset_url" ]; then
    warn "No asset for $TARGET in $TAG — falling back to cargo."
    cargo_install
    exit 0
fi

# ── Download + verify ────────────────────────────────────────────────────────
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

asset_name=$(basename "$asset_url")
info "Downloading $asset_name ..."
curl -fsSL "$asset_url" -o "$tmp/$asset_name"

if [ -n "$sums_url" ]; then
    info "Verifying SHA256 against SHA256SUMS ..."
    curl -fsSL "$sums_url" -o "$tmp/SHA256SUMS"
    expected=$(grep -F "$asset_name" "$tmp/SHA256SUMS" | awk '{print $1}')
    if [ -z "$expected" ]; then
        warn "Asset not listed in SHA256SUMS — skipping verification."
    else
        if command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "$tmp/$asset_name" | awk '{print $1}')
        elif command -v shasum >/dev/null 2>&1; then
            actual=$(shasum -a 256 "$tmp/$asset_name" | awk '{print $1}')
        else
            actual=""
        fi
        if [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
            fail "SHA256 mismatch for $asset_name (expected $expected, got $actual)."
        fi
    fi
else
    warn "No SHA256SUMS in release — skipping verification."
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

install -m 0755 "$src_bin" "$DEST_DIR/$BIN_NAME"
info "Installed $DEST_DIR/$BIN_NAME"

case ":$PATH:" in
    *":$DEST_DIR:"*) ;;
    *) warn "$DEST_DIR is not on PATH. Add it to your shell profile, e.g.:" >&2
       printf '      export PATH="%s:$PATH"\n' "$DEST_DIR" >&2 ;;
esac

"$DEST_DIR/$BIN_NAME" --version 2>&1 | head -1 | sed 's/^/  ok  /'
