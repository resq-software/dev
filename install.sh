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
# When piped to sh, re-exec under bash for pipefail support if available.

if [ -z "${_RESQ_REEXEC:-}" ] && command -v bash >/dev/null 2>&1; then
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

SCRIPT_VERSION="0.2.0"

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

NIX_INSTALL_URL="https://install.determinate.systems/nix"
ORG="resq-software"

# ── Utility functions (all log to stderr) ────────────────────────────────────

info() { printf "${CYAN}info${RESET}  %s\n" "$*" >&2; }
ok()   { printf "${GREEN}  ok${RESET}  %s\n" "$*" >&2; }
warn() { printf "${YELLOW}warn${RESET}  %s\n" "$*" >&2; }
fail() { printf "${RED}fail${RESET}  %s\n" "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

# Compare two dotted version strings. Returns 0 if $1 >= $2.
# POSIX-compatible: uses IFS splitting and positional params (no arrays).
version_gte() {
  _vgte_ver="$1"
  _vgte_min="$2"

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
  printf "%s [y/N] " "$1" >&2
  read -r _confirm_answer
  case "$_confirm_answer" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Step functions ───────────────────────────────────────────────────────────

detect_platform() {
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS" in
    Linux|Darwin) ;;
    *) fail "Unsupported OS: $OS. ResQ requires Linux or macOS." ;;
  esac
  info "Detected $OS ($ARCH)"
}

check_git() {
  if ! has git; then
    fail "git is required. Install it first: https://git-scm.com/downloads"
  fi
  _git_ver="$(git --version | cut -d' ' -f3)"
  ok "git $_git_ver"
  require_version "git" "$_git_ver" "2.0" "https://git-scm.com/downloads"
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
      Linux)
        if has apt-get; then
          curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
          sudo apt-get update && sudo apt-get install -y gh
        elif has dnf; then
          sudo dnf install -y gh
        elif has pacman; then
          sudo pacman -S --noconfirm github-cli
        else
          fail "Cannot auto-install gh. Install manually: https://cli.github.com"
        fi
        ;;
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
  else
    warn "Nix installed but not in PATH. Restart your shell and re-run this script."
    exit 0
  fi
}

choose_repo() {
  printf "\n${BOLD}  Which repo do you want to work on?${RESET}\n\n" >&2
  printf "  ${CYAN} 1${RESET}  resQ          Platform monorepo ${DIM}(private)${RESET}\n" >&2
  printf "  ${CYAN} 2${RESET}  programs      Solana/Anchor on-chain programs\n" >&2
  printf "  ${CYAN} 3${RESET}  dotnet-sdk    .NET client libraries\n" >&2
  printf "  ${CYAN} 4${RESET}  pypi          Python packages (MCP + DSA)\n" >&2
  printf "  ${CYAN} 5${RESET}  crates        Rust workspace (CLI + DSA)\n" >&2
  printf "  ${CYAN} 6${RESET}  npm           TypeScript packages (UI + DSA)\n" >&2
  printf "  ${CYAN} 7${RESET}  vcpkg         C++ libraries\n" >&2
  printf "  ${CYAN} 8${RESET}  landing       Marketing site\n" >&2
  printf "  ${CYAN} 9${RESET}  cms           Content management\n" >&2
  printf "  ${CYAN}10${RESET}  docs          Documentation site\n" >&2
  printf "\n  Choice [1-10]: " >&2
  read -r choice

  case "$choice" in
    1)  REPO="resQ" ;;
    2)  REPO="programs" ;;
    3)  REPO="dotnet-sdk" ;;
    4)  REPO="pypi" ;;
    5)  REPO="crates" ;;
    6)  REPO="npm" ;;
    7)  REPO="vcpkg" ;;
    8)  REPO="landing" ;;
    9)  REPO="cms" ;;
    10) REPO="docs" ;;
    *)  fail "Invalid choice: $choice" ;;
  esac
}

clone_repo() {
  TARGET_DIR="${RESQ_DIR:-$HOME/resq}/$REPO"

  if [ -d "$TARGET_DIR/.git" ]; then
    if confirm "$TARGET_DIR already exists — pull latest?"; then
      info "Pulling latest changes..."
      git -C "$TARGET_DIR" pull --ff-only 2>/dev/null || true
    fi
  else
    info "Cloning $ORG/$REPO into $TARGET_DIR"
    mkdir -p "$(dirname "$TARGET_DIR")"
    gh repo clone "$ORG/$REPO" "$TARGET_DIR"
  fi
  ok "Repository ready at $TARGET_DIR"
}

post_clone_setup() {
  if [ -f "$TARGET_DIR/flake.nix" ]; then
    info "Nix flake detected — building dev environment (first run may take a few minutes)..."
    nix develop "$TARGET_DIR" --command echo "Environment ready" 2>/dev/null || true
  fi

  if [ -f "$TARGET_DIR/tools/scripts/setup-hooks.sh" ]; then
    info "Setting up git hooks..."
    (cd "$TARGET_DIR" && bash tools/scripts/setup-hooks.sh 2>/dev/null) || true
    ok "Git hooks configured"
  fi
}

print_repo_info() {
  case "$REPO" in
    resQ)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "  ${DIM}Toolchain (via Nix)${RESET}\n" >&2
      printf "    Rust, Node/Bun, Python, .NET, C++, CMake, Protobuf\n\n" >&2
      printf "  ${DIM}Quality gates (automatic on commit)${RESET}\n" >&2
      printf "    Copyright headers, secret scanning, formatting (Rust/TS/Python/C++/C#)\n" >&2
      printf "    OSV vulnerability scan, debug statement detection, file size limits\n\n" >&2
      printf "  ${DIM}Security workflows (CI)${RESET}\n" >&2
      printf "    OSV scan, dependency review, CodeQL, secret scanning\n" >&2
      printf "    AI-powered: secrets analysis, security compliance audits\n\n" >&2
      printf "  ${DIM}Developer tools${RESET}\n" >&2
      printf "    resq CLI      — audit, health checks, log viewer, perf monitor\n" >&2
      printf "    make test     — run all tests across all languages\n" >&2
      printf "    make build    — build all services\n" >&2
      printf "    make dev      — start dev servers\n" >&2
      printf "    make lint     — lint everything\n\n" >&2
      ;;
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
    cms)
      printf "\n  ${BOLD}What's included:${RESET}\n\n" >&2
      printf "    TypeScript, pnpm, Wrangler\n" >&2
      printf "    Deploys to Cloudflare Workers\n\n" >&2
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
