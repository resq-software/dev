#!/bin/sh
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Run every test suite in this repository. Exit 0 iff all of them pass.
#
#     sh tests/run_all.sh
#
# Until now there was no such command. The suites existed but were reachable
# only through three different workflow files — bats in hooks-tests.yml, the
# installer pinning test in required.yml, the worker suite in required.yml and
# release.yml — so the only way to run everything was to push and wait.
#
# The idea is borrowed from WomB0ComB0/ralph's tests/run_all.sh, specifically
# the part that matters:
#
#   A suite passes only if it EXITED 0 *and* its output proves zero failures.
#
# Those are independent facts and both have failed separately in this repo. A
# suite can exit 0 while printing a failure — the bats "rejects bad branch name"
# case asserted on a hook that never ran — and a check can die before printing
# anything, as the copyright check did by exiting non-zero with no output
# because `grep -L` returns 1 when every file is compliant. Checking one
# condition would have missed one of those.
#
# What is NOT borrowed: ralph runs each suite in a throwaway cwd, which works
# because its suites are hermetic. Ours are deliberately repo-root-relative —
# bin/stamp.sh and tests/installers/pinning.sh both refuse to run elsewhere and
# say so. Copying that mechanism made all three fail on the first run. Suites
# therefore run from the repository root.
#
# A missing tool SKIPS its suite and says so. Counting a skip as a pass is the
# defect this repo has now found four separate times in its own CI.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

failures=0
skipped=0

# $1 name, $2 command, $3 extended regex the output must match to count as pass
run_suite() {
    _name="$1"
    _cmd="$2"
    _proof="$3"

    _out="$(eval "$_cmd" 2>&1)"
    _rc=$?

    if [ "$_rc" -eq 0 ] && printf '%s\n' "$_out" | grep -qE "$_proof"; then
        printf '  PASS  %-12s %s\n' "$_name" "$(printf '%s\n' "$_out" | grep -oE "$_proof" | tail -1)"
        return
    fi

    printf '  FAIL  %-12s (exit %s)\n' "$_name" "$_rc"
    printf '%s\n' "$_out" | grep -iE 'fail|error|not ok' | head -8 | sed 's/^/          /'
    failures=$((failures + 1))
}

# bats emits raw TAP: a `1..N` plan and `ok`/`not ok` lines, with no summary
# line to grep for. So success is "the plan was printed AND nothing said
# not ok" — which is the same two-condition rule, expressed for TAP.
run_bats() {
    _out="$(bats "$ROOT/tests/hooks/" 2>&1)"
    _rc=$?
    _plan="$(printf '%s\n' "$_out" | grep -cE '^1\.\.[0-9]+' || true)"
    _bad="$(printf '%s\n' "$_out" | grep -cE '^not ok' || true)"
    _n="$(printf '%s\n' "$_out" | grep -cE '^ok ' || true)"

    if [ "$_rc" -eq 0 ] && [ "$_plan" -ge 1 ] && [ "$_bad" -eq 0 ]; then
        printf '  PASS  %-12s %s tests, 0 failures\n' "hooks" "$_n"
        return
    fi
    printf '  FAIL  %-12s (exit %s, %s not-ok)\n' "hooks" "$_rc" "$_bad"
    printf '%s\n' "$_out" | grep -E '^not ok' | head -8 | sed 's/^/          /'
    failures=$((failures + 1))
}

skip_suite() {
    printf '  SKIP  %-12s %s\n' "$1" "$2"
    skipped=$((skipped + 1))
}

printf '\nResQ dev test suites\n\n'

# Installer pinning. Stubs cargo; touches no network and no toolchain.
run_suite "installers" "sh tests/installers/pinning.sh" '[0-9]+ passed, 0 failed'

# Canonical git hooks. bats fetches the hook templates once per session.
if command -v bats >/dev/null 2>&1; then
    run_bats
else
    skip_suite "hooks" "bats not installed"
fi

# The Worker. Needs Node 23.6+ for native type stripping, and reaches
# raw.githubusercontent.com deliberately, so a rotted pin fails here rather
# than in production.
if command -v node >/dev/null 2>&1; then
    run_suite "worker" "node worker/test/index.test.mjs" '[0-9]+ passed, 0 failed'
else
    skip_suite "worker" "node not installed"
fi

# Not a test suite, but the check most easily forgotten locally, and cheap.
run_suite "stamp" "sh bin/stamp.sh --check" 'in sync'

printf '\n'
if [ "$failures" -eq 0 ]; then
    printf 'all suites passed'
    if [ "$skipped" -gt 0 ]; then printf ' (%s skipped)' "$skipped"; fi
    printf '\n\n'
    exit 0
fi
printf '%s suite(s) failed\n\n' "$failures"
exit 1
