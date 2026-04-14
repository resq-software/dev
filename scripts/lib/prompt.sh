#!/bin/bash
# Interactive prompts and privilege guards. Requires log.sh + platform.sh.

prompt() {
    local msg="$1" default="${2:-}"
    if [[ "${YES:-0}" -eq 1 ]]; then
        log_info "$msg (auto-yes)"
        return 0
    fi
    if [ ! -e /dev/tty ]; then
        return 1
    fi
    local prompt_str="(y/n)"
    if [[ "$default" == "y" ]]; then prompt_str="([y]/n)"
    elif [[ "$default" == "n" ]]; then prompt_str="(y/[n])"
    fi
    read -p "${COLOR_YELLOW}?${COLOR_NC} $msg $prompt_str " -n 1 -r < /dev/tty
    echo
    if [[ -z "$REPLY" && -n "$default" ]]; then REPLY="$default"; fi
    [[ $REPLY =~ ^[Yy]$ ]]
}

require_sudo() {
    if [[ $EUID -ne 0 ]]; then
        if command_exists sudo; then
            log_warning "Some operations require root. You may be prompted for your password."
        else
            log_error "This script requires root privileges or sudo."
            exit 1
        fi
    fi
}

get_high_res_time() {
    if [[ "$OS_TYPE" == "macos" ]]; then
        python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s
    else
        date +%s.%N 2>/dev/null || date +%s
    fi
}
