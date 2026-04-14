#!/bin/bash
# Miscellaneous helpers — hashing, GitHub API, port checks.
# Requires log.sh + platform.sh.

md5sum_wrapper() {
    if   command_exists md5sum;  then md5sum "$@"
    elif command_exists md5;     then md5 -r "$@"
    elif command_exists certutil; then
        for file in "$@"; do
            certutil -hashfile "$file" MD5 | grep -v ":" | tr -d '[:space:]'
            echo "  $file"
        done
    else
        log_error "No MD5 command found"
        return 1
    fi
}

get_latest_github_release() {
    local repo="$1"
    curl -s "https://api.github.com/repos/${repo}/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/'
}

check_port_in_use() {
    local port="$1"
    if   command_exists lsof;    then lsof -i :"$port" >/dev/null 2>&1
    elif command_exists netstat; then netstat -tuln | grep -q ":$port "
    else grep -q "$(printf ":%04X" "$port")" /proc/net/tcp 2>/dev/null
    fi
}
