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

SCRIPT_VERSION="0.3.0"

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

NIX_INSTALL_URL="https://install.determinate.systems/nix"
ORG="resq-software"

# Canonical repo list — keep in sync with install.ps1 and README.md.
VALID_REPOS="programs dotnet-sdk pypi crates npm vcpkg landing docs"

# ── Utility functions (all log to stderr) ────────────────────────────────────

info() { printf "${CYAN}info${RESET}  %s\n" "$*" >&2; }
ok()   { printf "${GREEN}  ok${RESET}  %s\n" "$*" >&2; }
warn() { printf "${YELLOW}warn${RESET}  %s\n" "$*" >&2; }
fail() { printf "${RED}fail${RESET}  %s\n" "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

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
  if ! has nix; then
    if ! confirm "Install Nix package manager?"; then
      warn "Skipping Nix install — some repos require Nix for their dev environment."
      return 0
    fi
    info "Installing Nix via Determinate Systems installer..."
    curl --proto '=https' --tlsv1.2 -sSf -L "$NIX_INSTALL_URL" | sh -s -- install

    # Source nix in current shell
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
    for _r in $VALID_REPOS; do
      if [ "$_r" = "$REPO" ]; then
        info "Using REPO=$REPO from environment"
        return 0
      fi
    done
    fail "Invalid REPO='$REPO'. Valid: $VALID_REPOS"
  fi

  if [ ! -e /dev/tty ]; then
    fail "No TTY for interactive prompt. Set REPO=<name> to run unattended. Valid: $VALID_REPOS"
  fi

  printf "\n${BOLD}  Which repo do you want to work on?${RESET}\n\n" >&2
  printf "  ${CYAN} 1${RESET}  programs      Solana/Anchor on-chain programs\n" >&2
  printf "  ${CYAN} 2${RESET}  dotnet-sdk    .NET client libraries\n" >&2
  printf "  ${CYAN} 3${RESET}  pypi          Python packages (MCP + DSA)\n" >&2
  printf "  ${CYAN} 4${RESET}  crates        Rust workspace (CLI + DSA)\n" >&2
  printf "  ${CYAN} 5${RESET}  npm           TypeScript packages (UI + DSA)\n" >&2
  printf "  ${CYAN} 6${RESET}  vcpkg         C++ libraries\n" >&2
  printf "  ${CYAN} 7${RESET}  landing       Marketing site\n" >&2
  printf "  ${CYAN} 8${RESET}  docs          Documentation site\n" >&2
  printf "\n  Choice [1-8]: " >&2
  read -r choice < /dev/tty

  case "$choice" in
    1)  REPO="programs" ;;
    2)  REPO="dotnet-sdk" ;;
    3)  REPO="pypi" ;;
    4)  REPO="crates" ;;
    5)  REPO="npm" ;;
    6)  REPO="vcpkg" ;;
    7)  REPO="landing" ;;
    8)  REPO="docs" ;;
    *)  fail "Invalid choice: $choice" ;;
  esac
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
  _hooks_url="https://raw.githubusercontent.com/$ORG/dev/main/scripts/install-hooks.sh"
  if (cd "$TARGET_DIR" && curl -fsSL "$_hooks_url" | sh); then
    ok "Git hooks configured"
  else
    warn "Hook install failed — re-run: cd $TARGET_DIR && curl -fsSL $_hooks_url | sh"
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
  _tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf \"$_tmp\"" EXIT HUP INT QUIT TERM

  _asset="resq-cli-${_tag}-${_triple}.tar.gz"
  if ! gh release download "$_tag" --repo "$ORG/crates" \
        --pattern "$_asset" --pattern 'SHA256SUMS' --dir "$_tmp" --clobber >/dev/null 2>&1; then
    warn "Failed to download $_asset from $_tag — skipping"
    return 0
  fi

  # Verify checksum. SHA256SUMS lists every asset; filter to just ours before
  # feeding to `sha256sum -c` so other missing files don't trigger failures.
  if ! (cd "$_tmp" && grep -F " $_asset" SHA256SUMS | sha256sum -c --quiet >/dev/null 2>&1); then
    warn "SHA256 verification failed for $_asset — not installing"
    return 0
  fi

  tar -xzf "$_tmp/$_asset" -C "$_tmp"
  _staging_dir="$_tmp/resq-cli-${_tag}-${_triple}"
  if [ ! -x "$_staging_dir/resq" ]; then
    warn "Archive layout unexpected ($_staging_dir/resq missing) — skipping"
    return 0
  fi

  mkdir -p "$_bin_dir"
  install -m 0755 "$_staging_dir/resq" "$_bin_path"
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
  if "$_bin_path" completions "$_shell_name" > "$_compl_file" 2>/dev/null; then
    ok "Installed $_shell_name completions to $_compl_file"
    if [ "$_shell_name" = "zsh" ]; then
      info "  zsh: add to ~/.zshrc if not already: fpath+=(\"$_compl_dir\"); autoload -Uz compinit && compinit"
    fi
  else
    warn "Failed to generate $_shell_name completions — skip"
  fi
}

print_repo_info() {
  case "$REPO" in
    programs)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "    Solana CLI, Anchor framework, Rust toolchain\n" >&2
      printf "    make anchor-build, make anchor-test\n\n" >&2
      ;;
    pypi)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "    Python 3.11-3.13, uv, ruff, mypy\n" >&2
      printf "    Packages: resq-mcp, resq-dsa\n" >&2
      printf "    90%% test coverage gate enforced\n\n" >&2
      ;;
    crates)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "    Rust toolchain, clippy, cargo-deny\n" >&2
      printf "    Workspace: 9+ crates including CLI tools and resq-dsa\n\n" >&2
      ;;
    npm)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "    Bun, TypeScript, React 19, Storybook, Chromatic\n" >&2
      printf "    Packages: @resq-sw/ui (55+ components), @resq-sw/dsa\n" >&2
      printf "    Biome linter\n\n" >&2
      ;;
    vcpkg)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "    C++ toolchain, CMake, clang-format\n" >&2
      printf "    Header-only library: resq-common\n\n" >&2
      ;;
    docs)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "    Mintlify docs site\n" >&2
      printf "    npx mint dev for local preview\n\n" >&2
      ;;
  esac
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  printf "\n${BOLD}  ResQ Developer Setup v%s${RESET}\n" "$SCRIPT_VERSION" >&2
  printf "  ─────────────────────────────\n\n" >&2

  detect_platform
  check_git
  install_gh
  authenticate_gh
  install_nix
  choose_repo
  clone_repo
  post_clone_setup
  install_resq_cli
  print_repo_info

  printf "${BOLD}${GREEN}  Ready!${RESET}\n\n" >&2
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
