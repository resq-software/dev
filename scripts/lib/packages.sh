#!/bin/bash
# Package-manager abstraction. Requires log.sh + platform.sh.

get_package_manager() {
    case "$OS_TYPE" in
        linux)
            if   command_exists apt-get; then echo "apt"
            elif command_exists dnf;     then echo "dnf"
            elif command_exists yum;     then echo "yum"
            elif command_exists pacman;  then echo "pacman"
            elif command_exists zypper;  then echo "zypper"
            elif command_exists apk;     then echo "apk"
            else echo "unknown"; fi
            ;;
        macos)
            if command_exists brew; then echo "brew"; else echo "none"; fi
            ;;
        windows)
            if   command_exists scoop;  then echo "scoop"
            elif command_exists winget; then echo "winget"
            elif command_exists choco;  then echo "choco"
            else echo "none"; fi
            ;;
        *) echo "unknown" ;;
    esac
}

install_package() {
    local package="$1" pkg_mgr
    pkg_mgr=$(get_package_manager)
    local sudo_cmd="sudo"
    [[ "$EUID" -eq 0 ]] && sudo_cmd=""

    case "$pkg_mgr" in
        apt)    $sudo_cmd apt-get update -y && $sudo_cmd apt-get install -y "$package" ;;
        dnf)    $sudo_cmd dnf install -y "$package" ;;
        yum)    $sudo_cmd yum install -y "$package" ;;
        pacman) $sudo_cmd pacman -Sy --noconfirm "$package" ;;
        zypper) $sudo_cmd zypper install -y "$package" ;;
        apk)    $sudo_cmd apk add --no-cache "$package" ;;
        brew)   brew install --quiet "$package" ;;
        choco)  choco install -y "$package" ;;
        scoop)  scoop install "$package" ;;
        winget) winget install --silent --accept-source-agreements --accept-package-agreements --id "$package" ;;
        *)      return 1 ;;
    esac
}

install_osv_scanner() {
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    log_info "Attempting to install osv-scanner via $pkg_mgr..."
    case "$pkg_mgr" in
        winget) install_package "Google.OSVScanner" ;;
        *)      install_package "osv-scanner" ;;
    esac
}
