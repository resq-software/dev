#!/bin/sh
# shellcheck disable=SC2059
# Copyright 2026 ResQ Software
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh | sh
#
# Or inspect first:
#   curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh -o install.sh
#   less install.sh
#   sh install.sh

# ── Bash re-exec ─────────────────────────────────────────────────────────────
# Local runs (sh install.sh) re-exec under bash for pipefail + better traps.
# Curl-pipe runs ($0="sh", no file) stay in POSIX sh with `set -eu` — that's
# the primary UX, so the script must work correctly without bash.

if [ -z "${_RESQ_REEXEC:-}" ] && [ -f "$0" ] && command -v bash >/dev/null 2>&1; then
  export _RESQ_REEXEC=1
  exec bash "$0" "$@"
fi
if [ -n "${BASH_VERSION:-}" ]; then
  # shellcheck disable=SC3040
  set -euo pipefail
else
  set -eu
fi

# ── Constants ────────────────────────────────────────────────────────────────

# Must match the v* tag this script is published under. The hook fetch below
# requests https://get.resq.software/v$SCRIPT_VERSION/hooks.sh, so an older
# install.sh keeps verifying against the digest it actually shipped with rather
# than against whatever happens to be current. release.yml refuses to publish a
# tag whose version disagrees with this value.
SCRIPT_VERSION="0.4.3"

# Everything this script creates belongs to the invoking user alone. Set before
# the first mkdir/mktemp so nothing is even briefly group- or world-readable.
umask 077

# Disable ANSI when stderr isn't a TTY or NO_COLOR is set (CI, log redirects).
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; RESET=''
fi

# Pinned to a version rather than the rolling endpoint.
# https://install.determinate.systems/nix is a redirect to exactly this URL
# today, so pinning costs nothing and means a change to what Determinate serves
# cannot silently change what we execute. The versioned URL was verified to
# return identical bytes across fetches.
#
# Bump both lines together. required.yml re-checks the digest against the live
# URL, so a stale pin fails CI rather than every user's install.
NIX_INSTALL_URL="https://install.determinate.systems/nix/tag/v3.21.9"
NIX_INSTALLER_SHA256="ed6067b13423cfd36c50e5b156b9e08eb3a7bea4dde8cb1c8d997d757b37b7f6"
ORG="resq-software"

# Pinned, hash-verified distribution endpoint (see worker/src/index.ts). It
# serves one specific commit and refuses to serve anything whose SHA-256 does
# not match, which is why fetching from here beats raw.githubusercontent.com's
# mutable /main ref.
DIST_BASE="https://get.resq.software"

# SHA-256 of scripts/install-hooks.sh as published at this SCRIPT_VERSION,
# checked before that file is ever executed. This is the link that closes the
# trust chain: the Worker vouches for install.sh, and install.sh vouches for
# the hook installer. A compromised endpoint still cannot get code past it.
# Regenerate with:
#   git cat-file blob "$(git rev-parse "v$SCRIPT_VERSION"):scripts/install-hooks.sh" | sha256sum
HOOKS_SHA256="62bfac28709ce2651a9313b6cd2010c953a675e3dd8cbe34eef8a32b2702bb03"

# Canonical repo table — one source of truth for the menu, REPO validation, and
# the post-install summary. Those used to be three separate lists that could
# disagree, and did: `landing` went private while still being offered as menu
# option 7, so choosing it failed at clone time.
#
#   name|one-line description|what's included, ';' separating lines
#
# Scope is mechanical so CI can verify it: public, non-archived, non-fork
# repositories in the org, excluding `.github`. Archived is part of the rule
# rather than an oversight — an archived repo is read-only, so offering it to
# clone-and-hack would be a dead end.
# Keep in sync with install.ps1 and README.md.
REPOS="$(cat <<'EOF'
crates|Rust workspace (CLI + DSA)|Rust toolchain, clippy, cargo-deny;Workspace: 9+ crates including CLI tools and resq-dsa
dev|Developer setup + installers|POSIX sh + PowerShell installers, Cloudflare Worker;shellcheck install.sh, node worker/test/index.test.mjs
docs|Documentation site|Mintlify docs site;npx mint dev for local preview
dotnet|Clean architecture building blocks (.NET)|.NET 9 SDK, pinned by global.json;Packages: ResQ.BuildingBlocks Domain, Application, Adapters, Testing;dotnet build -c Release, dotnet test -c Release
dotnet-sdk|.NET client libraries|.NET 9 SDK, Protobuf toolchain;dotnet build -c Release, dotnet test -c Release
npm|TypeScript packages (UI + DSA)|Bun, TypeScript, React 19, Storybook, Chromatic;Packages: @resq-sw/ui (55+ components), @resq-sw/dsa;Biome linter
programs|Solana/Anchor on-chain programs|Solana CLI, Anchor framework, Rust toolchain;make anchor-build, make anchor-test
pypi|Python packages (MCP + DSA)|Python 3.11-3.13, uv, ruff, mypy;Packages: resq-mcp, resq-dsa;90% test coverage gate enforced
vcpkg|C++ libraries|C++ toolchain, CMake, clang-format;Header-only library: resq-common
viz|3D visualization|Three.js / Cesium web viewers (TypeScript);Unity 3D viewer (.NET 9, ResQ.Viz.sln)
EOF
)"

# ── Utility functions (all log to stderr) ────────────────────────────────────

info() { printf "${CYAN}info${RESET}  %s\n" "$*" >&2; }
ok()   { printf "${GREEN}  ok${RESET}  %s\n" "$*" >&2; }
warn() { printf "${YELLOW}warn${RESET}  %s\n" "$*" >&2; }
fail() { printf "${RED}fail${RESET}  %s\n" "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

# ── Temp file cleanup ────────────────────────────────────────────────────────
#
# One trap for the whole script. install_resq_cli used to set its own `trap ...
# EXIT` mid-run, which clobbered any trap set earlier and stayed armed across
# that function's several early `return` paths — so a later, unrelated failure
# would fire a handler still referring to a stale directory name.
#
# Newline-separated rather than space-separated so a TMPDIR containing spaces
# cannot turn cleanup into an `rm -rf` of the wrong thing.
_TMP_PATHS=""

cleanup() {
  [ -n "$_TMP_PATHS" ] || return 0
  printf '%s\n' "$_TMP_PATHS" | while IFS= read -r _cl_path; do
    [ -n "$_cl_path" ] && rm -rf "$_cl_path"
  done
  _TMP_PATHS=""
}
trap cleanup EXIT HUP INT QUIT TERM

# Creates a temp directory, registers it for cleanup, and reports it in the
# global TMPDIR_PATH. Fails loudly rather than returning an empty path that
# would later expand to nothing.
#
# Deliberately assigns a global instead of echoing: `d="$(make_tmpdir)"` would
# run this in a subshell, so the _TMP_PATHS registration would be thrown away
# and the directory would outlive the script.
make_tmpdir() {
  TMPDIR_PATH="$(mktemp -d 2>/dev/null)" || fail "could not create a temporary directory"
  _TMP_PATHS="$_TMP_PATHS
$TMPDIR_PATH"
}

# macOS ships `shasum -a 256` but not `sha256sum`. Reading from stdin keeps the
# output to a bare digest on both, with no filename column to strip.
sha256_of() {
  if has sha256sum; then sha256sum < "$1" | cut -d' ' -f1
  elif has shasum;  then shasum -a 256 < "$1" | cut -d' ' -f1
  else return 1
  fi
}

# Download $1 to $2, and keep it only if its SHA-256 equals $3. Returns 1 on
# any failure, having removed the file — a caller can never end up executing
# bytes this function did not vouch for.
fetch_verified() {
  _fv_url="$1"
  _fv_dest="$2"
  _fv_want="$3"

  curl -fsSL --proto '=https' --tlsv1.2 "$_fv_url" -o "$_fv_dest" || return 1

  if ! _fv_got="$(sha256_of "$_fv_dest")"; then
    warn "neither sha256sum nor shasum is available — refusing to run unverified code"
    rm -f "$_fv_dest"
    return 1
  fi

  if [ "$_fv_got" != "$_fv_want" ]; then
    rm -f "$_fv_dest"
    warn "checksum mismatch for $_fv_url"
    warn "  expected $_fv_want"
    warn "  got      $_fv_got"
    return 1
  fi
  return 0
}

# ── REPOS table access ───────────────────────────────────────────────────────
#
# awk compares the name with `==`, i.e. exact string equality, so a value typed
# by the user can never be interpreted as a pattern the way it could with grep.

repo_field() {  # name field-number -> field value (empty if no such repo)
  printf '%s\n' "$REPOS" | awk -F'|' -v n="$1" -v f="$2" '$1 == n { print $f; exit }'
}

repo_exists() { [ -n "$(repo_field "$1" 1)" ]; }

repo_names() { printf '%s\n' "$REPOS" | awk -F'|' '{ printf "%s ", $1 }'; }

# Accept either a menu number or a repo name, and echo the resolved name.
# Empty output means "no match" — the caller re-prompts rather than aborting.
resolve_choice() {
  case "$1" in
    ''|*[!0-9]*) printf '%s\n' "$REPOS" | awk -F'|' -v n="$1" '$1 == n { print $1; exit }' ;;
    *)           printf '%s\n' "$REPOS" | awk -F'|' -v i="$1" 'NR == i { print $1; exit }' ;;
  esac
}

# Compare two dotted version strings. Returns 0 if $1 >= $2.
# POSIX-compatible: uses IFS splitting and positional params (no arrays).
version_gte() {
  _vgte_ver="$(echo "$1" | sed 's/[^0-9.]//g')"
  _vgte_min="$(echo "$2" | sed 's/[^0-9.]//g')"

  # Split $1 into positional params
  _vgte_old_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $_vgte_ver
  _vgte_major1="${1:-0}"
  _vgte_minor1="${2:-0}"
  _vgte_patch1="${3:-0}"

  # Split $2
  # shellcheck disable=SC2086
  set -- $_vgte_min
  _vgte_major2="${1:-0}"
  _vgte_minor2="${2:-0}"
  _vgte_patch2="${3:-0}"
  IFS="$_vgte_old_ifs"

  if [ "$_vgte_major1" -gt "$_vgte_major2" ]; then return 0; fi
  if [ "$_vgte_major1" -lt "$_vgte_major2" ]; then return 1; fi
  if [ "$_vgte_minor1" -gt "$_vgte_minor2" ]; then return 0; fi
  if [ "$_vgte_minor1" -lt "$_vgte_minor2" ]; then return 1; fi
  if [ "$_vgte_patch1" -ge "$_vgte_patch2" ]; then return 0; fi
  return 1
}

# Warn (but do not fail) if a tool's version is below the minimum.
# Args: tool_name actual_version min_version url
require_version() {
  _rv_tool="$1"
  _rv_actual="$2"
  _rv_min="$3"
  _rv_url="$4"
  if ! version_gte "$_rv_actual" "$_rv_min"; then
    warn "$_rv_tool $_rv_actual is below recommended minimum $_rv_min — upgrade: $_rv_url"
  fi
}

# Prompt [y/N] to stderr, returns 0 on yes, 1 on no.
# Bypassed when YES=1 environment variable is set.
confirm() {
  if [ "${YES:-0}" = "1" ]; then return 0; fi
  if [ ! -e /dev/tty ]; then return 1; fi
  printf "%s [y/N] " "$1" >&2
  read -r _confirm_answer < /dev/tty
  case "$_confirm_answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Step functions ───────────────────────────────────────────────────────────

detect_platform() {
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  IS_WSL=0
  DISTRO="unknown"
  case "$OS" in
    Linux)
      if [ -r /proc/version ] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        IS_WSL=1
      fi
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        DISTRO="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-unknown}")"
      fi
      ;;
    Darwin) DISTRO="macos" ;;
    *) fail "Unsupported OS: $OS. Linux/macOS only — Windows users: use install.ps1 or WSL." ;;
  esac
  if [ "$IS_WSL" = "1" ]; then
    info "Detected WSL/$DISTRO ($ARCH)"
  else
    info "Detected $OS/$DISTRO ($ARCH)"
  fi
}

check_git() {
  if ! has git; then
    fail "git is required. Install it first: https://git-scm.com/downloads"
  fi
  _git_ver="$(git --version | cut -d' ' -f3)"
  ok "git $_git_ver"
  require_version "git" "$_git_ver" "2.0" "https://git-scm.com/downloads"
}

install_gh_apt() {
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update && sudo apt-get install -y gh
}

install_gh_linux() {
  # Prefer distro ID; fall back to probing package managers for unknowns.
  case "$DISTRO" in
    ubuntu|debian|linuxmint|pop|raspbian) install_gh_apt ;;
    fedora|rhel|centos|rocky|almalinux) sudo dnf install -y gh ;;
    arch|manjaro|endeavouros|cachyos) sudo pacman -S --noconfirm github-cli ;;
    opensuse*|sles|suse) sudo zypper install -y gh ;;
    alpine) sudo apk add --no-cache github-cli ;;
    void) sudo xbps-install -Sy github-cli ;;
    *)
      if   has apt-get; then install_gh_apt
      elif has dnf;     then sudo dnf install -y gh
      elif has pacman;  then sudo pacman -S --noconfirm github-cli
      elif has zypper;  then sudo zypper install -y gh
      elif has apk;     then sudo apk add --no-cache github-cli
      elif has xbps-install; then sudo xbps-install -Sy github-cli
      else fail "Cannot auto-install gh on '$DISTRO'. Install manually: https://cli.github.com"
      fi
      ;;
  esac
}

install_gh() {
  if ! has gh; then
    warn "gh (GitHub CLI) not found — installing..."
    case "$OS" in
      Darwin)
        if has brew; then
          brew install gh
        else
          fail "Install Homebrew first (https://brew.sh) or install gh manually"
        fi
        ;;
      Linux) install_gh_linux ;;
    esac
  fi
  _gh_ver="$(gh --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  ok "gh $_gh_ver"
  require_version "gh" "$_gh_ver" "2.0" "https://cli.github.com"
}

authenticate_gh() {
  if ! gh auth status >/dev/null 2>&1; then
    info "Not logged in to GitHub — starting auth..."
    gh auth login
  fi
  ok "GitHub authenticated as $(gh api user --jq '.login' 2>/dev/null || echo 'unknown')"
}

install_nix() {
  # Track whether Determinate installed Nix this session so we can remind the
  # user to start a fresh shell (or source the profile) for `nix` to be on
  # PATH in their interactive terminal — env mutations inside `curl | sh`
  # don't propagate to the parent process.
  NIX_JUST_INSTALLED=0
  if ! has nix; then
    if ! confirm "Install Nix package manager?"; then
      warn "Skipping Nix install — some repos require Nix for their dev environment."
      return 0
    fi
    info "Installing Nix via Determinate Systems installer..."
    # Download and verify before executing, rather than piping to sh. This is
    # the same treatment install-hooks.sh gets; the Nix installer runs with
    # sudo and touches /nix, so it warrants at least as much.
    #
    # It remains a third-party artifact — Determinate publishes no digest of
    # their own — so this pins *what we execute*, not what they wrote. A
    # compromise of that endpoint before the pin was taken would still land.
    make_tmpdir
    _nix_installer="$TMPDIR_PATH/nix-installer.sh"
    if ! fetch_verified "$NIX_INSTALL_URL" "$_nix_installer" "$NIX_INSTALLER_SHA256"; then
      warn "Could not obtain a verified Nix installer — skipping Nix setup."
      warn "  Install it yourself: https://determinate.systems/nix"
      return 0
    fi
    # Check the installer's exit status. Verifying the download says the script
    # is authentic, not that it worked — and setting NIX_JUST_INSTALLED after a
    # failed run would print "Nix was just installed" and a PATH hint for a Nix
    # that is not there.
    if ! sh "$_nix_installer" install; then
      warn "The Nix installer failed — continuing without Nix."
      warn "  Retry manually: https://determinate.systems/nix"
      return 0
    fi
    NIX_JUST_INSTALLED=1

    # Source nix in current shell (this script's process only; see note above).
    # shellcheck disable=SC1091
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    elif [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi
  fi

  if has nix; then
    ok "nix $(nix --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    check_nix_flakes
  else
    warn "Nix installed but not in PATH. Restart your shell and re-run this script."
    exit 0
  fi
}

# Confirm nix-command + flakes are enabled — `nix develop` is a no-go without them.
# The Determinate installer enables both by default; pre-existing installs often don't.
check_nix_flakes() {
  if nix --extra-experimental-features 'nix-command flakes' \
       flake --help >/dev/null 2>&1; then
    return 0
  fi
  warn "Nix flakes not enabled — 'nix develop' will fail."
  warn "  Add to ~/.config/nix/nix.conf:  experimental-features = nix-command flakes"
}

choose_repo() {
  # Honour REPO=<name> for unattended installs (CI, provisioning).
  if [ -n "${REPO:-}" ]; then
    if repo_exists "$REPO"; then
      info "Using REPO=$REPO from environment"
      return 0
    fi
    fail "Invalid REPO='$REPO'. Valid: $(repo_names)"
  fi

  if [ ! -e /dev/tty ]; then
    fail "No TTY for interactive prompt. Set REPO=<name> to run unattended. Valid: $(repo_names)"
  fi

  _cr_count="$(printf '%s\n' "$REPOS" | wc -l | tr -d ' ')"

  # Loop rather than abort. A typo here used to end the whole run — after gh,
  # Nix and a package manager pass had already completed — forcing the user to
  # start over for a mistyped digit.
  while :; do
    printf "\n${BOLD}  Which repo do you want to work on?${RESET}\n\n" >&2

    # Numbered from the table itself, so the list can grow past 9 entries
    # without the prompt and the mapping drifting apart. Colours stay inside
    # the printf format string because that is what expands \033.
    _cr_i=0
    printf '%s\n' "$REPOS" | while IFS='|' read -r _cr_name _cr_desc _cr_rest; do
      _cr_i=$((_cr_i + 1))
      printf "  ${CYAN}%2d${RESET}  %-12s %s\n" "$_cr_i" "$_cr_name" "$_cr_desc" >&2
    done

    printf "\n  Choice [1-%s, or a name]: " "$_cr_count" >&2

    # A closed stdin (piped, no tty) must not spin forever.
    if ! read -r _cr_choice < /dev/tty; then
      fail "No input on /dev/tty — set REPO=<name> to run unattended"
    fi

    REPO="$(resolve_choice "$_cr_choice")"
    [ -n "$REPO" ] && return 0

    warn "Not a valid choice: $_cr_choice"
  done
}

clone_repo() {
  TARGET_DIR="${RESQ_DIR:-$HOME/resq}/$REPO"

  if [ -d "$TARGET_DIR/.git" ]; then
    if confirm "$TARGET_DIR already exists — pull latest?"; then
      info "Pulling latest changes..."
      if ! git -C "$TARGET_DIR" pull --ff-only; then
        warn "Fast-forward pull failed in $TARGET_DIR — resolve manually"
      fi
    fi
  else
    info "Cloning $ORG/$REPO into $TARGET_DIR"
    mkdir -p "$(dirname "$TARGET_DIR")"
    gh repo clone "$ORG/$REPO" "$TARGET_DIR"
  fi
  ok "Repository ready at $TARGET_DIR"
}

post_clone_setup() {
  if [ -f "$TARGET_DIR/flake.nix" ] && has nix; then
    info "Building Nix dev environment at $TARGET_DIR"
    info "  (first run downloads ~500 MB – 2 GB; expect 2–5 minutes, no progress bar)"
    _nix_start="$(date +%s 2>/dev/null || echo 0)"
    if nix develop "$TARGET_DIR" --command true; then
      _nix_end="$(date +%s 2>/dev/null || echo 0)"
      _nix_elapsed=$((_nix_end - _nix_start))
      ok "Nix dev environment ready (${_nix_elapsed}s)"
    else
      warn "nix develop failed — cd into $TARGET_DIR and run 'nix develop' to see errors"
    fi
  fi

  info "Installing canonical ResQ git hooks..."
  # Prefer the hooks script already present in the freshly-cloned tree — it was
  # fetched over authenticated HTTPS by `gh repo clone`. Re-fetching it from a
  # mutable raw.githubusercontent.com/main ref and piping to sh is a TOFU/RCE
  # path (any branch/endpoint compromise → arbitrary code execution).
  _hooks_local="$TARGET_DIR/scripts/install-hooks.sh"
  if [ -f "$_hooks_local" ]; then
    if (cd "$TARGET_DIR" && sh "$_hooks_local"); then
      ok "Git hooks configured"
    else
      warn "Hook install failed — re-run: cd $TARGET_DIR && sh scripts/install-hooks.sh"
    fi
    return 0
  fi

  # No local copy (the cloned repo isn't `dev`), so fetch one.
  #
  # This was `curl .../dev/main/scripts/install-hooks.sh | sh` — a plain remote
  # code execution path: /main is mutable, nothing was verified, and the bytes
  # reached a shell without ever being inspected. Now the download is pinned to
  # this script's own version and checked against HOOKS_SHA256 before it runs,
  # so neither a compromised endpoint nor a MITM can substitute code.
  #
  # /v$SCRIPT_VERSION/ rather than bare /hooks.sh on purpose: an install.sh from
  # an older release has to verify against the digest it shipped with, not
  # against whatever the newest release happens to publish.
  make_tmpdir
  _hooks_tmp="$TMPDIR_PATH/install-hooks.sh"
  _hooks_url="$DIST_BASE/v$SCRIPT_VERSION/hooks.sh"

  if ! fetch_verified "$_hooks_url" "$_hooks_tmp" "$HOOKS_SHA256"; then
    # Fall back to the tag ref: the endpoint may simply be down. The digest
    # check is what provides the safety here, not the choice of host, and v*
    # tags cannot be moved or deleted under the `release-tags` ruleset.
    _hooks_url="https://raw.githubusercontent.com/$ORG/dev/v$SCRIPT_VERSION/scripts/install-hooks.sh"
    if ! fetch_verified "$_hooks_url" "$_hooks_tmp" "$HOOKS_SHA256"; then
      warn "Could not obtain a verified install-hooks.sh — skipping hook setup"
      warn "  Set them up later with: cd $TARGET_DIR && resq hooks install"
      return 0
    fi
  fi

  if (cd "$TARGET_DIR" && sh "$_hooks_tmp"); then
    ok "Git hooks configured (verified $(printf '%.12s' "$HOOKS_SHA256")…)"
  else
    warn "Hook install failed — re-run: cd $TARGET_DIR && resq hooks install"
  fi
}

# Install the `resq` binary from resq-software/crates GitHub Releases. Chooses
# the tar.gz for the current $OS/$ARCH, verifies SHA256 against the release's
# SHA256SUMS, and drops the binary into $RESQ_BIN_DIR (default ~/.local/bin).
# Idempotent: skips when the currently-installed `resq --version` matches the
# latest release. Skip entirely with SKIP_RESQ_CLI=1.
install_resq_cli() {
  if [ "${SKIP_RESQ_CLI:-0}" = "1" ]; then
    info "SKIP_RESQ_CLI=1 — skipping resq binary install"
    return 0
  fi

  case "$OS-$ARCH" in
    Linux-x86_64)              _triple="x86_64-unknown-linux-gnu" ;;
    Linux-aarch64|Linux-arm64) _triple="aarch64-unknown-linux-gnu" ;;
    Darwin-x86_64)             _triple="x86_64-apple-darwin" ;;
    Darwin-arm64)              _triple="aarch64-apple-darwin" ;;
    *)
      warn "No resq-cli binary published for $OS-$ARCH — skipping"
      return 0
      ;;
  esac

  _tag="$(gh release list --repo "$ORG/crates" --limit 40 \
    --json tagName --jq '.[] | .tagName' 2>/dev/null \
    | grep -m1 '^resq-cli-v' || true)"
  if [ -z "$_tag" ]; then
    warn "No resq-cli release found in $ORG/crates — skipping binary install"
    return 0
  fi
  _expected_ver="$(echo "$_tag" | sed 's/^resq-cli-v//')"

  _bin_dir="${RESQ_BIN_DIR:-$HOME/.local/bin}"
  _bin_path="$_bin_dir/resq"

  if [ -x "$_bin_path" ]; then
    _installed_ver="$("$_bin_path" --version 2>/dev/null | awk '{print $NF}')"
    if [ "$_installed_ver" = "$_expected_ver" ]; then
      ok "resq $_expected_ver already installed at $_bin_path"
      install_resq_completions
      return 0
    fi
  fi

  info "Installing resq $_expected_ver for $_triple..."
  # Registers with the script-wide cleanup trap instead of installing a local
  # one. The previous `trap "rm -rf $_tmp" EXIT HUP INT QUIT TERM` here replaced
  # whatever trap was already set, and stayed armed across the several early
  # `return` paths below — so an unrelated later failure fired a handler still
  # pointing at this function's directory.
  make_tmpdir
  _tmp="$TMPDIR_PATH"

  _asset="resq-cli-${_tag}-${_triple}.tar.gz"
  if ! gh release download "$_tag" --repo "$ORG/crates" \
        --pattern "$_asset" --pattern 'SHA256SUMS' --dir "$_tmp" --clobber >/dev/null 2>&1; then
    warn "Failed to download $_asset from $_tag — skipping"
    return 0
  fi

  # Verify checksum. SHA256SUMS lists every asset; filter to just ours before
  # feeding to the checker so other missing files don't trigger failures.
  # macOS ships `shasum -a 256` but not `sha256sum`; prefer sha256sum when
  # available and fall back to shasum. `--quiet` is a GNU-only flag, so drop
  # it and redirect stdout to /dev/null instead.
  _check_cmd="sha256sum -c"
  has sha256sum || _check_cmd="shasum -a 256 -c"
  if ! (cd "$_tmp" && grep -F " $_asset" SHA256SUMS | $_check_cmd >/dev/null 2>&1); then
    warn "SHA256 verification failed for $_asset — not installing"
    return 0
  fi

  tar -xzf "$_tmp/$_asset" -C "$_tmp"
  # Locate the binary inside the extracted tree rather than assuming the
  # staging-dir layout. Matches the pattern already used by
  # scripts/install-resq.sh and stays resilient if release.yml ever renames
  # the inner directory.
  _staging_bin="$(find "$_tmp" -type f -name resq | head -n 1)"
  if [ -z "$_staging_bin" ]; then
    warn "Archive layout unexpected (resq binary missing) — skipping"
    return 0
  fi

  mkdir -p "$_bin_dir"
  install -m 0755 "$_staging_bin" "$_bin_path"
  ok "Installed $_bin_path"

  case ":$PATH:" in
    *":$_bin_dir:"*) ;;
    *) warn "$_bin_dir is not in PATH. Add to your shell rc: export PATH=\"$_bin_dir:\$PATH\"" ;;
  esac

  install_resq_completions
}

# Emit shell completion scripts for the user's current shell into the
# conventional user-local path. Bash / zsh / fish are handled; other shells
# get a hint to run `resq completions <shell>` manually. Silent-ok if the
# `resq` binary couldn't be installed.
install_resq_completions() {
  _bin_dir="${RESQ_BIN_DIR:-$HOME/.local/bin}"
  _bin_path="$_bin_dir/resq"
  if [ ! -x "$_bin_path" ]; then
    return 0
  fi

  _shell_name="$(basename "${SHELL:-sh}")"
  case "$_shell_name" in
    bash)
      _compl_dir="$HOME/.local/share/bash-completion/completions"
      _compl_file="$_compl_dir/resq"
      ;;
    zsh)
      _compl_dir="$HOME/.local/share/zsh/site-functions"
      _compl_file="$_compl_dir/_resq"
      ;;
    fish)
      _compl_dir="$HOME/.config/fish/completions"
      _compl_file="$_compl_dir/resq.fish"
      ;;
    *)
      info "Shell completions: run \`resq completions <bash|zsh|fish|elvish|powershell>\` manually"
      return 0
      ;;
  esac

  mkdir -p "$_compl_dir"
  # Capture stderr on failure so the user sees the real reason. Older resq
  # binaries (before v0.2.7) don't know about `completions`; newer ones do.
  # Using mktemp (not /tmp/...$$) so TMPDIR is honoured and we can't collide
  # with a stale file owned by another user on a shared host.
  _err_tmp="$(mktemp)"
  _compl_err="$("$_bin_path" completions "$_shell_name" 2> "$_err_tmp" > "$_compl_file" && echo ok || echo fail)"
  if [ "$_compl_err" = "ok" ] && [ -s "$_compl_file" ]; then
    rm -f "$_err_tmp"
    ok "Installed $_shell_name completions to $_compl_file"
    if [ "$_shell_name" = "zsh" ]; then
      info "  zsh: add to ~/.zshrc if not already: fpath+=(\"$_compl_dir\"); autoload -Uz compinit && compinit"
    fi
  else
    _err_msg="$(head -n 1 "$_err_tmp" 2>/dev/null)"
    rm -f "$_compl_file" "$_err_tmp"
    if [ -n "$_err_msg" ]; then
      warn "Failed to generate $_shell_name completions: $_err_msg"
    else
      warn "Failed to generate $_shell_name completions (empty output — the installed resq may predate the 'completions' subcommand; retry once a newer release is out)"
    fi
  fi
}

print_repo_info() {
  _pri_includes="$(repo_field "$REPO" 3)"
  [ -n "$_pri_includes" ] || return 0

  printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2

  # Field 3 is a ';'-separated list of lines. Printed via %s rather than being
  # baked into the format string, so a description containing a '%' is safe —
  # the old hand-written calls had to remember to escape those as '%%', and
  # "90%% test coverage" was the only one that did.
  printf '%s\n' "$_pri_includes" | tr ';' '\n' | while IFS= read -r _pri_line; do
    [ -n "$_pri_line" ] && printf '    %s\n' "$_pri_line" >&2
  done

  printf "\n" >&2
}

# ── Main ─────────────────────────────────────────────────────────────────────

usage() {
  cat >&2 <<EOF
ResQ Developer Setup v$SCRIPT_VERSION

  curl -fsSL $DIST_BASE | sh
  sh install.sh [--help] [--version]

Environment:
  REPO=<name>        choose a repository non-interactively
  RESQ_DIR=<path>    where to clone (default: \$HOME/resq)
  RESQ_BIN_DIR=<p>   where to put the resq binary (default: \$HOME/.local/bin)
  YES=1              assume yes at confirmation prompts
  SKIP_RESQ_CLI=1    skip installing the resq binary
  NO_COLOR=1         disable ANSI colour

Repositories:
$(printf '%s\n' "$REPOS" | awk -F'|' '{ printf "  %-12s %s\n", $1, $2 }')

Verify before running:
  curl -fsSL $DIST_BASE/install.sh | sha256sum
  curl -fsSL $DIST_BASE/SHA256SUMS
EOF
}

# curl drives the Nix install, the hook fetch and release downloads, but was
# never checked for. On a machine without it the run got several steps in
# before dying with a bare "curl: not found" from inside a pipeline.
check_curl() {
  has curl || fail "curl is required. Install it first, then re-run."
  ok "curl $(curl --version 2>/dev/null | head -1 | awk '{print $2}')"
}

main() {
  # Curl-pipe runs pass no arguments, so this loop is normally a no-op.
  for _arg in "$@"; do
    case "$_arg" in
      -h|--help)    usage; exit 0 ;;
      -V|--version) printf '%s\n' "$SCRIPT_VERSION"; exit 0 ;;
      *)            fail "Unknown option: $_arg (try --help)" ;;
    esac
  done

  printf "\n${BOLD}  ResQ Developer Setup v%s${RESET}\n" "$SCRIPT_VERSION" >&2
  printf "  ─────────────────────────────\n\n" >&2

  detect_platform
  check_git
  check_curl
  install_gh
  authenticate_gh
  install_nix
  choose_repo
  clone_repo
  post_clone_setup
  install_resq_cli
  print_repo_info

  printf "${BOLD}${GREEN}  Ready!${RESET}\n\n" >&2

  # If Determinate installed Nix this run, the user's interactive shell
  # (which spawned `curl | sh`) hasn't sourced the profile yet. Flag this
  # prominently before the "Get started" list so they don't hit
  # `nix: command not found` when they follow the instructions.
  if [ "${NIX_JUST_INSTALLED:-0}" = "1" ]; then
    printf "  ${BOLD}${YELLOW}Note:${RESET} Nix was just installed. For \`nix\` to be on PATH, either:\n" >&2
    printf "    - open a new terminal, or\n" >&2
    printf "    - run:  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh\n" >&2
    printf "  (fish users: set -x PATH /nix/var/nix/profiles/default/bin \$PATH)\n\n" >&2
  fi

  printf "  ${BOLD}Get started:${RESET}\n\n" >&2
  printf "    cd %s\n" "$TARGET_DIR" >&2
  if [ -f "$TARGET_DIR/flake.nix" ]; then
    printf "    nix develop\n" >&2
  fi
  if [ -f "$TARGET_DIR/Makefile" ]; then
    printf "    make help\n" >&2
  fi
  printf "\n" >&2
}

main "$@"
