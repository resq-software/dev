#!/bin/bash
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
# Nix install + flake re-exec. Requires log.sh + platform.sh + packages.sh.

install_nix() {
    if command_exists nix; then return 0; fi

    log_info "Nix not found. Attempting to install Nix..."
    local sudo_cmd="sudo"
    [[ "$EUID" -eq 0 ]] && sudo_cmd=""

    # Prefer native pacman on Arch — integrates with system services.
    if [[ -f /etc/arch-release ]]; then
        log_info "Arch Linux detected. Attempting native install via pacman..."
        if install_package nix; then
            log_info "Configuring Nix daemon..."
            $sudo_cmd mkdir -p /etc/nix
            if ! grep -q "flakes" /etc/nix/nix.conf 2>/dev/null; then
                echo "experimental-features = nix-command flakes" \
                    | $sudo_cmd tee -a /etc/nix/nix.conf >/dev/null
            fi
            $sudo_cmd systemctl enable --now nix-daemon
            if ! groups | grep -q "nix-users"; then
                $sudo_cmd usermod -aG nix-users "$USER"
            fi
            # shellcheck source=/dev/null
            [ -f /etc/profile.d/nix.sh ] && . /etc/profile.d/nix.sh
            if command_exists nix; then
                log_success "Native Nix installed successfully!"
                return 0
            fi
        fi
        log_warning "Native pacman install failed. Falling back to official installer..."
    fi

    # Pinned, downloaded and digest-checked before execution — matching what
    # install.sh does. This used to pipe nixos.org/nix/install straight into sh
    # with no -f, so a 4xx body would have been executed as a script.
    #
    # Determinate's versioned URL rather than nixos.org's rolling one, because
    # it is the only one of the two that can be pinned at all, and install.sh
    # already installs Nix from it. Two different installers for the same tool
    # in one repo was its own problem.
    #
    # Bump both lines together; required.yml re-checks the digest.
    local nix_url="https://install.determinate.systems/nix/tag/v3.21.9"
    local nix_sha="ed6067b13423cfd36c50e5b156b9e08eb3a7bea4dde8cb1c8d997d757b37b7f6"

    # Download, verify and run inside a subshell with an EXIT trap rather than a
    # RETURN trap in this function.
    #
    # A RETURN trap set inside a function is not confined to it. Verified: with
    # `set -T` (functrace) it persists and fires on unrelated later returns; it
    # silently replaces any RETURN trap the caller had installed; and under
    # `set -u` the now-out-of-scope temp variable makes it abort with "unbound
    # variable". These are library functions meant to be sourced, so a caller
    # enabling functrace is a realistic thing to break.
    #
    # A subshell EXIT trap cannot escape, and takes the temp directory with it.
    log_info "Downloading pinned Nix installer..."
    if ! (
        set -e
        nix_tmp="$(mktemp -d)"
        trap 'rm -rf "$nix_tmp"' EXIT

        if ! curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
            "$nix_url" -o "$nix_tmp/nix-installer.sh"; then
            log_error "Could not download the Nix installer."
            exit 1
        fi
        if command_exists sha256sum; then
            nix_got="$(sha256sum "$nix_tmp/nix-installer.sh" | cut -d' ' -f1)"
        else
            nix_got="$(shasum -a 256 "$nix_tmp/nix-installer.sh" | cut -d' ' -f1)"
        fi
        if [ "$nix_got" != "$nix_sha" ]; then
            log_error "Nix installer checksum mismatch — refusing to run it."
            log_error "  expected $nix_sha"
            log_error "  got      $nix_got"
            exit 1
        fi

        log_info "Running official Nix multi-user install script..."
        sh "$nix_tmp/nix-installer.sh" install --no-confirm
    ); then
        log_error "Nix installation failed."
        return 1
    fi

    # The installer succeeded; bring Nix onto PATH for the rest of this process.
    for profile in \
        "/etc/profile.d/nix.sh" \
        "$HOME/.nix-profile/etc/profile.d/nix.sh" \
        "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"; do
        if [ -f "$profile" ]; then
            log_info "Activating Nix environment from $profile..."
            # shellcheck source=/dev/null
            . "$profile"
            break
        fi
    done
    if command_exists nix; then
        log_success "Nix installed and activated via official script!"
        return 0
    fi

    log_error "All Nix installation methods failed. Install manually: https://nixos.org/download.html"
    return 1
}

# Re-execs the current script inside `nix develop` if a flake is present.
ensure_nix_env() {
    if [[ -n "${IN_NIX_SHELL:-}" ]] || [[ -n "${RESQ_NIX_RECURSION:-}" ]] || ! command_exists nix; then
        return 0
    fi
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
    if [[ ! -f "$project_root/flake.nix" ]]; then
        return 0
    fi

    log_info "Nix detected. Entering development environment via flake.nix..."
    export RESQ_NIX_RECURSION=1

    if [[ -f "$0" ]]; then
        exec nix develop "$project_root" --command "$0" "$@"
    else
        if [[ "${RESQ_SILENT_NIX_WARNING:-0}" -ne 1 ]]; then
            log_warning "Could not re-execute environment automatically (sourced or subshell)."
            log_info "Run 'nix develop' manually if tools are missing."
        fi
        return 0
    fi
}
