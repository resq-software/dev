#!/bin/bash
# Bun installer. Requires log.sh + platform.sh.

install_bun() {
    if command_exists bun; then return 0; fi

    log_info "Installing Bun..."
    case "$OS_TYPE" in
        linux|macos)
            # --proto/--proto-redir pin the whole redirect chain to https, to
            # match what install.sh does for its own vendor installer.
            curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
                https://bun.sh/install | bash
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
            ;;
        windows)
            if command_exists powershell.exe; then
                # Scheme spelled out. This read `irm bun.sh/install.ps1`, and a
                # bare host lets the request begin as plaintext http — for a
                # response piped straight into iex.
                powershell.exe -Command "irm https://bun.sh/install.ps1 | iex"
            else
                log_error "PowerShell required for Bun installation on Windows."
                return 1
            fi
            ;;
    esac
    log_success "Bun installed."
}
