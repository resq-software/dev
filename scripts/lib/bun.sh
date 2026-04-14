#!/bin/bash
# Bun installer. Requires log.sh + platform.sh.

install_bun() {
    if command_exists bun; then return 0; fi

    log_info "Installing Bun..."
    case "$OS_TYPE" in
        linux|macos)
            curl -fsSL https://bun.sh/install | bash
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
            ;;
        windows)
            if command_exists powershell.exe; then
                powershell.exe -Command "irm bun.sh/install.ps1 | iex"
            else
                log_error "PowerShell required for Bun installation on Windows."
                return 1
            fi
            ;;
    esac
    log_success "Bun installed."
}
