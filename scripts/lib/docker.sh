#!/bin/bash
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
# Docker installer. Requires log.sh + platform.sh + packages.sh + prompt.sh.

install_docker() {
    if command_exists docker; then return 0; fi

    require_sudo
    log_info "Attempting to install Docker..."

    case "$OS_TYPE" in
        linux)
            if command_exists apt-get; then
                sudo apt-get update -y
                sudo apt-get install -y \
                    apt-transport-https ca-certificates curl \
                    software-properties-common lsb-release
                # A keyring file scoped with signed-by, not `apt-key add`.
                # apt-key installs into the global trusted set, where the key
                # can sign packages for *every* repository on the system — a
                # Docker key vouching for anything apt fetches. It is deprecated
                # for exactly that reason.
                # Docker publishes separate suites for Debian and Ubuntu, and the
                # codename has to come from the matching one. Hardcoding ubuntu
                # with `lsb_release -cs` breaks on Debian: it yields e.g.
                # "bookworm", which the ubuntu suite does not publish, so apt
                # either errors or silently finds no candidate.
                local dk_id dk_like dk_repo dk_codename
                dk_id="$(. /etc/os-release && echo "${ID:-}")"
                dk_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
                case "$dk_id" in
                    ubuntu) dk_repo=ubuntu
                            dk_codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")" ;;
                    debian) dk_repo=debian
                            dk_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")" ;;
                    *)
                        # Derivatives (Mint, Pop!_OS, Kali) report their own ID;
                        # ID_LIKE names the upstream whose suite they track, and
                        # UBUNTU_CODENAME/DEBIAN_CODENAME carry the right suite.
                        case "$dk_like" in
                            *ubuntu*) dk_repo=ubuntu
                                      dk_codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-}")" ;;
                            *debian*) dk_repo=debian
                                      dk_codename="$(. /etc/os-release && echo "${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}")" ;;
                            *) log_error "Unrecognised apt distribution '$dk_id'. Install Docker manually: https://docs.docker.com/engine/install/"
                               return 1 ;;
                        esac
                        ;;
                esac
                if [ -z "$dk_codename" ]; then
                    log_error "Could not determine the distribution codename for '$dk_id'."
                    log_error "Install Docker manually: https://docs.docker.com/engine/install/"
                    return 1
                fi

                sudo install -m 0755 -d /usr/share/keyrings
                curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
                    "https://download.docker.com/linux/$dk_repo/gpg" \
                    | sudo gpg --dearmor --yes -o /usr/share/keyrings/docker.gpg
                sudo chmod a+r /usr/share/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/$dk_repo $dk_codename stable" \
                    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt-get update -y
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io
                sudo usermod -aG docker "$USER"
            elif command_exists dnf || command_exists yum; then
                local pkg_mgr
                pkg_mgr=$(get_package_manager)
                sudo "$pkg_mgr" install -y yum-utils
                sudo "${pkg_mgr}-config-manager" --add-repo \
                    https://download.docker.com/linux/centos/docker-ce.repo
                sudo "$pkg_mgr" install -y docker-ce docker-ce-cli containerd.io
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker "$USER"
            elif command_exists pacman; then
                sudo pacman -S --noconfirm docker
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker "$USER"
            else
                log_error "Automatic Docker install not supported for this distribution."
                return 1
            fi
            ;;
        macos)
            if command_exists brew; then
                brew install --cask docker
            else
                log_error "Homebrew not found. Install Docker Desktop manually."
                return 1
            fi
            ;;
        *)
            log_error "Docker installation not supported for $OS_TYPE"
            return 1
            ;;
    esac
    log_success "Docker installed successfully."
}
