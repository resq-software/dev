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
DIM='\033[2m'
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
  printf "  ${CYAN}1${RESET}  resQ          Full platform monorepo ${DIM}(private)${RESET}\n"
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
    info "Cloning $ORG/$REPO into $TARGET_DIR"
    mkdir -p "$(dirname "$TARGET_DIR")"
    gh repo clone "$ORG/$REPO" "$TARGET_DIR"
  fi

  ok "Repository ready at $TARGET_DIR"

  # ── Post-clone setup ───────────────────────────────────────────────────

  if [ -f "$TARGET_DIR/flake.nix" ]; then
    info "Nix flake detected — building dev environment (first run may take a few minutes)..."
    nix develop "$TARGET_DIR" --command echo "Environment ready" 2>/dev/null || true
  fi

  # Git hooks
  if [ -f "$TARGET_DIR/tools/scripts/setup-hooks.sh" ]; then
    info "Setting up git hooks..."
    (cd "$TARGET_DIR" && bash tools/scripts/setup-hooks.sh 2>/dev/null) || true
    ok "Git hooks configured (pre-commit, pre-push, commit-msg)"
  elif [ -f "$TARGET_DIR/package.json" ] && grep -q "setup-hooks" "$TARGET_DIR/package.json" 2>/dev/null; then
    info "Git hooks will be configured on first install"
  fi

  # ── Print what you get ─────────────────────────────────────────────────

  printf "\n${BOLD}${GREEN}  Ready!${RESET}\n\n"
  printf "  ${BOLD}Get started:${RESET}\n\n"
  printf "    cd %s\n" "$TARGET_DIR"

  if [ -f "$TARGET_DIR/flake.nix" ]; then
    printf "    nix develop\n"
  fi

  if [ -f "$TARGET_DIR/Makefile" ]; then
    printf "    make help\n"
  fi

  printf "\n"

  # Show what's included based on repo
  if [ "$REPO" = "resQ" ]; then
    printf "  ${BOLD}What's included:${RESET}\n\n"
    printf "  ${DIM}Toolchain (via Nix)${RESET}\n"
    printf "    Rust, Node/Bun, Python, .NET, C++, CMake, Protobuf\n\n"
    printf "  ${DIM}Quality gates (automatic on commit)${RESET}\n"
    printf "    Copyright headers, secret scanning, formatting (Rust/TS/Python/C++/C#)\n"
    printf "    OSV vulnerability scan, debug statement detection, file size limits\n\n"
    printf "  ${DIM}Security workflows (CI)${RESET}\n"
    printf "    OSV scan, dependency review, CodeQL, secret scanning\n"
    printf "    AI-powered: secrets analysis, security compliance audits\n\n"
    printf "  ${DIM}Developer tools${RESET}\n"
    printf "    resq CLI     — audit, health checks, log viewer, perf monitor\n"
    printf "    make test     — run all tests across all languages\n"
    printf "    make build    — build all services\n"
    printf "    make dev      — start dev servers\n"
    printf "    make lint     — lint everything\n\n"
  elif [ "$REPO" = "programs" ]; then
    printf "  ${BOLD}What's included:${RESET}\n\n"
    printf "    Solana CLI, Anchor framework, Rust toolchain\n"
    printf "    make anchor-build, make anchor-test\n\n"
  elif [ "$REPO" = "mcp" ]; then
    printf "  ${BOLD}What's included:${RESET}\n\n"
    printf "    Python 3.11-3.13, uv, ruff, mypy\n"
    printf "    Pre-commit hooks for formatting + security\n"
    printf "    90%% test coverage threshold enforced\n\n"
  elif [ "$REPO" = "cli" ]; then
    printf "  ${BOLD}What's included:${RESET}\n\n"
    printf "    Rust toolchain, clippy, cargo-deny\n"
    printf "    9 crates: audit, cleanup, deploy, explore, health, logs, tui\n\n"
  elif [ "$REPO" = "ui" ]; then
    printf "  ${BOLD}What's included:${RESET}\n\n"
    printf "    Bun, TypeScript, React 19, Storybook, Chromatic\n"
    printf "    55+ components, Biome linter\n\n"
  fi
}

main "$@"
