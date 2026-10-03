#!/usr/bin/env bats
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
# Which hooks scripts/install-hooks.sh installs, by resq version.
#
# Path 1 (`resq hooks install`) writes the templates embedded in the binary,
# so an old resq installs old hooks — before resq-cli 0.4.3 that meant the
# blanket GIT_HOOKS_SKIP guard, under which GIT_HOOKS_SKIP=audit also disabled
# the secret scan. Below the floor, or when the version can't be read, the
# installer must take path 2: the pinned, digest-verified templates.

load helpers

INSTALLER="$BATS_TEST_DIRNAME/../../scripts/install-hooks.sh"

setup() {
    REPO="$(mktemp -d)"
    git -C "$REPO" init -q
    FAKE_BIN="$(mktemp -d)"
    FAKE_HOME="$(mktemp -d)"
    CALLS="$FAKE_BIN/calls"
    : > "$CALLS"
    cat > "$FAKE_BIN/resq" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
[ "${1:-}" = "--version" ] && echo "$FAKE_RESQ_VERSION_LINE"
exit 0
STUB
    chmod +x "$FAKE_BIN/resq"
}

teardown() {
    rm -rf "$REPO" "$FAKE_BIN" "$FAKE_HOME"
}

# run_installer <version line resq --version prints>
run_installer() {
    run env PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$FAKE_HOME" CALLS="$CALLS" \
        FAKE_RESQ_VERSION_LINE="$1" RESQ_SKIP_LOCAL_SCAFFOLD=1 \
        sh "$INSTALLER" "$REPO"
}

used_resq_templates() { grep -qxE 'hooks install|dev install-hooks' "$CALLS"; }

installed_pinned_hooks() {
    local h
    for h in $HOOK_NAMES; do
        [ "$(_hook_sha256 "$REPO/.git-hooks/$h")" = "$(_pinned_hook_digest "$h")" ] || return 1
    done
}

@test "resq below the floor installs the pinned hooks, not its embedded ones" {
    run_installer "resq 0.1.0"
    [ "$status" -eq 0 ]
    ! used_resq_templates
    installed_pinned_hooks
    [[ "$output" == *"0.1.0"* ]]
    [[ "$output" == *"predate the granular"* ]]
}

@test "resq one patch below the floor still falls back" {
    run_installer "resq 0.4.2"
    [ "$status" -eq 0 ]
    ! used_resq_templates
    installed_pinned_hooks
}

@test "an unreadable resq version falls back rather than trusting the binary" {
    run_installer "something unexpected"
    [ "$status" -eq 0 ]
    ! used_resq_templates
    installed_pinned_hooks
    [[ "$output" == *"<unreadable>"* ]]
}

@test "resq at the floor installs its own embedded hooks" {
    run_installer "resq 0.4.3"
    [ "$status" -eq 0 ]
    used_resq_templates
    [[ "$output" != *"predate the granular"* ]]
}

@test "versions compare numerically, not as strings" {
    # "0.10.0" < "0.4.3" as a string; it is newer as a version.
    run_installer "resq 0.10.0"
    [ "$status" -eq 0 ]
    used_resq_templates
}
