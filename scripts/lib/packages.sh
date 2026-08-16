#!/bin/bash
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
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

    # Reject anything that is not a package name. Every caller in this repo
    # passes a literal, so this is defence in depth rather than a live fix —
    # but this is a library function whose argument lands on a sudo command
    # line, and the cost of being wrong about "nobody will ever pass input
    # here" is arbitrary execution as root.
    if [[ ! "$package" =~ ^[A-Za-z0-9._+-]+$ ]]; then
        log_error "Refusing to install '$package': not a valid package name."
        return 1
    fi

    pkg_mgr=$(get_package_manager)

    # Name which of the two failure modes it is. This used to fall through to
    # a bare `return 1`, so a caller reported "install failed" whether the
    # package manager was missing or the install itself broke.
    case "$pkg_mgr" in
        unknown) log_error "No supported package manager found; cannot install $package."; return 1 ;;
        none)    log_error "No package manager available on this $OS_TYPE; install one first, then re-run."; return 1 ;;
    esac

    local sudo_cmd="sudo"
    if [[ "$EUID" -eq 0 ]]; then
        sudo_cmd=""
    elif [[ "${YES:-0}" == "1" ]]; then
        # Unattended mode. The README documents YES=1 for CI and provisioning,
        # and plain `sudo` there waits forever on a password prompt nobody is
        # present to answer — the run hangs until the job timeout with no
        # output explaining why. `-n` turns that into an immediate, legible
        # failure instead.
        sudo_cmd="sudo -n"
    fi

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
