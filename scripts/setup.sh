#!/usr/bin/env bash

# Copyright 2026 ResQ Systems, Inc.
#
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

# Sets up the ResQ Landing development environment.
#
# Usage:
#   ./scripts/setup.sh [--check] [--yes]
#
# Options:
#   --check   Verify the environment without making changes.
#   --yes     Auto-confirm all prompts (CI mode).
#
# What this does:
#   1. Installs Nix with flakes support (if missing).
#   2. Re-enters inside `nix develop` — provides Node 22 and Bun.
#   3. Installs Docker (if missing).
#   4. Runs `bun install` to hydrate node_modules.
#
# Requirements:
#   curl, git, bash 4+
#
# Exit codes:
#   0  Success.
#   1  A required step failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/shell-utils.sh
source "${SCRIPT_DIR}/lib/shell-utils.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
CHECK_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --check)  CHECK_ONLY=true ;;
        --yes)    export YES=1 ;;
        --help|-h)
            sed -n '/^# Usage/,/^$/p' "$0"
            exit 0
            ;;
    esac
done

# ── Check mode ────────────────────────────────────────────────────────────────
if [ "$CHECK_ONLY" = true ]; then
    log_info "Checking ResQ Landing environment..."
    ERRORS=0

    command_exists nix  || { log_error "nix not found"; ERRORS=$((ERRORS+1)); }
    command_exists node || { log_warning "node not found (run: nix develop)"; }
    command_exists bun  || { log_warning "bun not found (run: nix develop)"; }
    command_exists docker || { log_warning "docker not found"; }

    [ -d "$PROJECT_ROOT/node_modules" ] \
        && log_success "node_modules present" \
        || log_warning "node_modules missing — run: bun install"

    [ $ERRORS -eq 0 ] && log_success "Environment looks good." || exit 1
    exit 0
fi

# ── Main setup ────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════╗"
echo "║  ResQ — Environment Setup            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# 1. Nix
install_nix

# 2. Re-enter inside nix develop (Node 22, Bun)
ensure_nix_env "$@"

# 3. Docker (for containerised preview / self-hosting)
install_docker

# 4. Install JS dependencies
if command_exists bun; then
    log_info "Installing dependencies..."
    (cd "$PROJECT_ROOT" && bun install)
    log_success "Dependencies installed."
else
    log_warning "bun not found — run 'nix develop' then 'bun install'"
fi

# 5. Install canonical ResQ git hooks (backed by resq CLI)
if [ -x "$SCRIPT_DIR/install-hooks.sh" ]; then
    log_info "Installing canonical ResQ git hooks..."
    "$SCRIPT_DIR/install-hooks.sh" "$PROJECT_ROOT"
else
    log_warning "install-hooks.sh not found — skipping hook setup."
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✓ ResQ setup complete                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  nix develop                              # Enter dev shell"
echo "  bun dev                                  # Start dev server (port 3000)"
echo "  bun build                                # Production build"
echo "  docker build -t resq-landing .           # Build Docker image"
echo "  docker run -p 3000:3000 resq-landing     # Run container"
