#!/bin/bash
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
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
                sudo add-apt-repository \
                    "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
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
