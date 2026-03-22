#!/bin/sh
# Copyright 2026 ResQ Software
# Licensed under the Apache License, Version 2.0
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh | sh
#
# Or inspect first:
#   curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh -o install.sh
#   less install.sh
#   sh install.sh

set -eu

# ── Constants ────────────────────────────────────────────────────────────────

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

NIX_INSTALL_URL="https://install.determinate.systems/nix"
ORG="resq-software"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf "${CYAN}info${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}  ok${RESET}  %s\n" "$*"; }
warn()  { printf "${YELLOW}warn${RESET}  %s\n" "$*"; }
fail()  { printf "${RED}fail${RESET}  %s\n" "$*" >&2; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  printf "\n${BOLD}  ResQ Developer Setup${RESET}\n"
  printf "  ─────────────────────\n\n"

  # ── Detect OS ────────────────────────────────────────────────────────────

  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS" in
    Linux|Darwin) ;;
    *) fail "Unsupported OS: $OS. ResQ requires Linux or macOS." ;;
  esac
  info "Detected $OS ($ARCH)"

  # ── Git ──────────────────────────────────────────────────────────────────

  if ! has git; then
    fail "git is required. Install it first: https://git-scm.com/downloads"
  fi
  ok "git $(git --version | cut -d' ' -f3)"

  # ── GitHub CLI ───────────────────────────────────────────────────────────

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
  ok "gh $(gh --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

  # ── GitHub Auth ──────────────────────────────────────────────────────────

  if ! gh auth status >/dev/null 2>&1; then
    info "Not logged in to GitHub — starting auth..."
    gh auth login
  fi
  ok "GitHub authenticated as $(gh api user --jq '.login' 2>/dev/null || echo 'unknown')"

  # ── Nix ──────────────────────────────────────────────────────────────────

  if ! has nix; then
    info "Installing Nix via Determinate Systems installer..."
    curl --proto '=https' --tlsv1.2 -sSf -L "$NIX_INSTALL_URL" | sh -s -- install
    # Source nix in current shell
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

  # ── Choose repo ──────────────────────────────────────────────────────────

  printf "\n${BOLD}  Which repo do you want to work on?${RESET}\n\n"
  printf "  ${CYAN}1${RESET}  resQ          Full platform (monorepo, private — requires org access)\n"
  printf "  ${CYAN}2${RESET}  programs      Solana/Anchor on-chain programs\n"
  printf "  ${CYAN}3${RESET}  dotnet-sdk    .NET client libraries\n"
  printf "  ${CYAN}4${RESET}  mcp           MCP server for AI clients\n"
  printf "  ${CYAN}5${RESET}  cli           Rust CLI/TUI tools\n"
  printf "  ${CYAN}6${RESET}  ui            React component library\n"
  printf "  ${CYAN}7${RESET}  landing       Marketing site\n"
  printf "\n"
  printf "  Choice [1-7]: "
  read -r choice

  case "$choice" in
    1) REPO="resQ" ;;
    2) REPO="programs" ;;
    3) REPO="dotnet-sdk" ;;
    4) REPO="mcp" ;;
    5) REPO="cli" ;;
    6) REPO="ui" ;;
    7) REPO="landing" ;;
    *) fail "Invalid choice: $choice" ;;
  esac

  # ── Clone ────────────────────────────────────────────────────────────────

  TARGET_DIR="${RESQ_DIR:-$HOME/resq}/$REPO"

  if [ -d "$TARGET_DIR/.git" ]; then
    info "$TARGET_DIR already exists — pulling latest..."
    git -C "$TARGET_DIR" pull --ff-only 2>/dev/null || true
  else
    info "Cloning $ORG/$REPO → $TARGET_DIR"
    mkdir -p "$(dirname "$TARGET_DIR")"
    gh repo clone "$ORG/$REPO" "$TARGET_DIR"
  fi

  ok "Repository ready at $TARGET_DIR"

  # ── Enter dev environment ────────────────────────────────────────────────

  if [ -f "$TARGET_DIR/flake.nix" ]; then
    info "Nix flake detected — entering dev environment..."
    printf "\n${BOLD}${GREEN}  Ready!${RESET} Run:\n\n"
    printf "    cd %s\n" "$TARGET_DIR"
    printf "    nix develop\n\n"
  elif [ -f "$TARGET_DIR/shell.nix" ]; then
    printf "\n${BOLD}${GREEN}  Ready!${RESET} Run:\n\n"
    printf "    cd %s\n" "$TARGET_DIR"
    printf "    nix-shell\n\n"
  else
    printf "\n${BOLD}${GREEN}  Ready!${RESET} Run:\n\n"
    printf "    cd %s\n\n" "$TARGET_DIR"
  fi
}

main "$@"
