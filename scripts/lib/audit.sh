#!/bin/bash
# Audit-tool bootstrap (osv-scanner, audit-ci).
# Requires log.sh + platform.sh + packages.sh + prompt.sh.

ensure_audit_tools() {
    local missing=() project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

    if ! command_exists osv-scanner; then
        missing+=("osv-scanner")
    fi
    if ! command_exists audit-ci && [[ ! -f "$project_root/node_modules/.bin/audit-ci" ]]; then
        missing+=("audit-ci")
    fi
    [[ ${#missing[@]} -eq 0 ]] && return 0

    if command_exists nix && [[ -f "$project_root/flake.nix" ]] && [[ -z "${IN_NIX_SHELL:-}" ]]; then
        log_info "Attempting to locate tools in Nix environment..."
        if nix eval "$project_root#devShells.$(nix eval --raw "nixpkgs#system").default.nativeBuildInputs" --json 2>/dev/null | grep -q "osv-scanner"; then
            log_info "Auditing tools found in Nix flake. Run 'nix develop' to activate."
        fi
    fi

    log_warning "Missing auditing tools: ${missing[*]}"

    if [[ "${YES:-0}" -eq 1 ]] || prompt "Install missing auditing tools?"; then
        for tool in "${missing[@]}"; do
            case "$tool" in
                osv-scanner)
                    log_info "Installing osv-scanner via system package manager..."
                    if ! install_osv_scanner; then
                        log_info "System install failed. Falling back to Go install..."
                        if command_exists go; then
                            go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest
                            PATH="$(go env GOPATH)/bin:$PATH"
                            export PATH
                        else
                            log_error "Go not found. Cannot install osv-scanner."
                            return 1
                        fi
                    fi
                    ;;
                audit-ci)
                    log_info "Installing audit-ci via Bun..."
                    (cd "$project_root" && bun install)
                    ;;
            esac
        done
    else
        log_error "Auditing tools required. Install manually."
        return 1
    fi
}
