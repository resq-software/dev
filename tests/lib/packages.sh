#!/bin/bash
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Tests for scripts/lib/platform.sh and scripts/lib/packages.sh — OS detection
# and package-manager selection.
#
# These libraries had no tests at all, which is how several defects survived in
# them: an MD5 helper nobody called, a function shadowing a built-in cmdlet on
# the PowerShell side, and `sudo` with no non-interactive path in a mode the
# README advertises for CI.
#
# Everything is stubbed on PATH — no package manager is invoked, nothing is
# installed, and no sudo is required. Run directly:
#
#     bash tests/lib/packages.sh

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASH_BIN="$(command -v bash)"
pass=0
fail=0

check() {
    if [ "$2" = "0" ]; then
        pass=$((pass + 1)); printf '  PASS  %s\n' "$1"
    else
        fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"
        if [ -n "${3:-}" ]; then printf '        %s\n' "$3"; fi
    fi
}

# Run a snippet against the libraries with a synthetic PATH containing only the
# named stubs, so selection depends on what "exists" and nothing else.
with_stubs() {
    _stubs="$1"
    _snippet="$2"
    _t="$(mktemp -d)"
    mkdir -p "$_t/bin"
    for _s in $_stubs; do
        printf '#!/bin/sh\nexit 0\n' > "$_t/bin/$_s"
        chmod +x "$_t/bin/$_s"
    done
    # The real coreutils the libraries genuinely need, linked INTO the sandbox
    # rather than by putting /usr/bin on PATH — that distinction is the whole
    # isolation. platform.sh calls uname; the assertions below use grep.
    for _real in uname grep; do
        _p="$(command -v "$_real" 2>/dev/null)" && ln -sf "$_p" "$_t/bin/$_real"
    done
    # The CHILD's PATH is only the stub directory, but bash is launched by
    # absolute path so it can still be found.
    #
    # Two failed attempts are worth recording. Including /usr/bin made every
    # case report 'pacman', because the host is Arch and the cascade found the
    # real one — the suite was measuring the machine, not the code. Removing it
    # without an absolute bash then produced "bash: command not found" for
    # every case. Both failures looked like library bugs and were the harness.
    PATH="$_t/bin" "$BASH_BIN" -c "
        set -u
        . '$ROOT/scripts/lib/log.sh'
        . '$ROOT/scripts/lib/platform.sh'
        OS_TYPE='${OS_TYPE_OVERRIDE:-linux}'
        . '$ROOT/scripts/lib/packages.sh'
        $_snippet
    " 2>&1
    rm -rf "$_t"
}

printf '\n== platform + package-manager selection ==\n'

# Precedence, not merely "finds something": apt must win over dnf when both
# exist, or a Debian box with dnf installed takes the wrong branch.
r="$(with_stubs "apt-get dnf" 'get_package_manager')"
check "apt wins over dnf when both exist" "$([ "$r" = apt ] && echo 0 || echo 1)" "got '$r'"

r="$(with_stubs "dnf yum" 'get_package_manager')"
check "dnf wins over yum" "$([ "$r" = dnf ] && echo 0 || echo 1)" "got '$r'"

r="$(with_stubs "pacman" 'get_package_manager')"
check "pacman detected" "$([ "$r" = pacman ] && echo 0 || echo 1)" "got '$r'"

r="$(with_stubs "apk" 'get_package_manager')"
check "apk detected" "$([ "$r" = apk ] && echo 0 || echo 1)" "got '$r'"

r="$(with_stubs "" 'get_package_manager')"
check "no manager reports 'unknown', not empty" "$([ "$r" = unknown ] && echo 0 || echo 1)" "got '$r'"

r="$(OS_TYPE_OVERRIDE=macos with_stubs "" 'get_package_manager')"
check "macOS without brew reports 'none'" "$([ "$r" = none ] && echo 0 || echo 1)" "got '$r'"

printf '\n== install_package guards ==\n'

# The package name is the one argument that reaches a sudo command line.
r="$(with_stubs "apt-get sudo" 'install_package "foo; rm -rf /" >/dev/null 2>&1; echo $?')"
check "rejects a package name containing a command" "$([ "$r" = 1 ] && echo 0 || echo 1)" "exit '$r'"

r="$(with_stubs "apt-get sudo" 'install_package "osv-scanner" >/dev/null 2>&1; echo $?')"
check "accepts a normal package name" "$([ "$r" = 0 ] && echo 0 || echo 1)" "exit '$r'"

r="$(with_stubs "" 'install_package "osv-scanner" 2>&1 | grep -c "No supported package manager" || true')"
check "names the missing-package-manager case" "$([ "${r:-0}" -ge 1 ] 2>/dev/null && echo 0 || echo 1)" "matches '$r'"

# The one that hangs a CI job rather than failing it.
r="$(grep -c 'sudo -n' "$ROOT/scripts/lib/packages.sh" || true)"
check "unattended path uses sudo -n" "$([ "${r:-0}" -ge 1 ] && echo 0 || echo 1)" "occurrences: $r"

printf '\n%s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
