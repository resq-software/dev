#!/bin/bash
# Logging helpers — colors and log_info/success/warning/error.
# Safe to source multiple times (no readonly vars).

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_MAGENTA='\033[0;35m'
    COLOR_CYAN='\033[0;36m'
    COLOR_NC='\033[0m'
else
    COLOR_RED=''; COLOR_GREEN=''; COLOR_YELLOW=''
    COLOR_BLUE=''; COLOR_MAGENTA=''; COLOR_CYAN=''; COLOR_NC=''
fi
export COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_MAGENTA COLOR_CYAN COLOR_NC

_log_message() {
    local color="$1" level="$2"
    shift 2
    printf '%b[%s]%b %s\n' "$color" "$level" "$COLOR_NC" "$*" >&2
}

log_info()    { _log_message "$COLOR_BLUE"   "INFO"    "$@"; }
log_success() { _log_message "$COLOR_GREEN"  "SUCCESS" "$@"; }
log_warning() { _log_message "$COLOR_YELLOW" "WARNING" "$@"; }
log_error()   { _log_message "$COLOR_RED"    "ERROR"   "$@"; }
