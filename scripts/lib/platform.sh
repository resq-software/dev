#!/bin/bash
# Platform detection — OS and architecture normalization.

detect_os() {
    case "$(uname -s)" in
        Linux*)                 echo "linux" ;;
        Darwin*)                echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*)   echo "windows" ;;
        *)                      echo "unknown" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "amd64" ;;
        arm64|aarch64)  echo "arm64" ;;
        armv7l)         echo "arm" ;;
        *)              echo "unknown" ;;
    esac
}

OS_TYPE="${OS_TYPE:-$(detect_os)}"
ARCH_TYPE="${ARCH_TYPE:-$(detect_arch)}"
export OS_TYPE ARCH_TYPE

command_exists() {
    command -v "$1" >/dev/null 2>&1
}
