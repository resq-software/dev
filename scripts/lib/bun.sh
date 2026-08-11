#!/bin/bash
# Bun installer. Requires log.sh + platform.sh.

install_bun() {
    if command_exists bun; then return 0; fi

    log_info "Installing Bun..."
    case "$OS_TYPE" in
        linux|macos)
            # Bun's own installer, pinned to a tag and digest-checked before it
            # runs. bun.sh/install is byte-identical to this tagged path today,
            # so pinning costs nothing.
            #
            # Running their script rather than reimplementing the download is
            # deliberate: it does CPU baseline detection (bun-linux-x64 vs
            # -baseline for machines without AVX2). Getting that wrong installs
            # a binary that dies with SIGILL on older hardware — a worse and
            # far more confusing failure than the one this guards against.
            #
            # Bump both lines together; required.yml re-checks the digest.
            local bun_url="https://raw.githubusercontent.com/oven-sh/bun/bun-v1.3.14/src/cli/install.sh"
            local bun_sha="bab8acfb046aac8c72407bdcce903957665d655d7acaa3e11c7c4616beae68dd"
            local bun_tmp bun_got
            bun_tmp="$(mktemp -d)" || { log_error "Could not create a temporary directory."; return 1; }
            trap 'rm -rf "$bun_tmp"' RETURN

            if ! curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
                "$bun_url" -o "$bun_tmp/install.sh"; then
                log_error "Could not download the Bun installer."
                return 1
            fi
            if command_exists sha256sum; then
                bun_got="$(sha256sum "$bun_tmp/install.sh" | cut -d' ' -f1)"
            else
                bun_got="$(shasum -a 256 "$bun_tmp/install.sh" | cut -d' ' -f1)"
            fi
            if [ "$bun_got" != "$bun_sha" ]; then
                log_error "Bun installer checksum mismatch — refusing to run it."
                log_error "  expected $bun_sha"
                log_error "  got      $bun_got"
                return 1
            fi
            bash "$bun_tmp/install.sh"
            export BUN_INSTALL="$HOME/.bun"
            export PATH="$BUN_INSTALL/bin:$PATH"
            ;;
        windows)
            if command_exists powershell.exe; then
                # Delegate to bun.ps1, which pins and verifies the Windows
                # installer. This used to be `irm bun.sh/install.ps1 | iex` —
                # unverified, and until recently schemeless as well, so the
                # request could have begun over plaintext http.
                local _bun_lib
                _bun_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bun.ps1"
                powershell.exe -NoProfile -Command ". '$_bun_lib'; Install-Bun"
            else
                log_error "PowerShell required for Bun installation on Windows."
                return 1
            fi
            ;;
    esac
    log_success "Bun installed."
}
