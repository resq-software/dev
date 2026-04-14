#!/usr/bin/env bats
# Conventional Commits validation in the canonical commit-msg hook.

load helpers

setup() {
    REPO="$(mktemp -d)"
    init_repo_with_hooks "$REPO"
    MSG="$REPO/.msg"
}

teardown() {
    rm -rf "$REPO"
}

write_msg() { printf '%s\n' "$1" > "$MSG"; }

@test "accepts feat: subject" {
    write_msg "feat: add the thing"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts feat(scope): subject" {
    write_msg "feat(api): add /v2/foo"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts feat!: breaking change marker" {
    write_msg "feat!: drop legacy endpoint"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts feat(scope)!: breaking with scope" {
    write_msg "feat(api)!: drop legacy endpoint"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
}

@test "accepts ticket-prefixed message" {
    write_msg "[ABC-123] feat: add ticket prefix"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
}

@test "rejects unknown type" {
    write_msg "wat: this is not a type"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid commit message"* ]]
}

@test "rejects missing subject after type" {
    write_msg "feat:"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -ne 0 ]
}

@test "rejects WIP on main" {
    checkout_branch "$REPO" main
    write_msg "WIP: still working"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not allowed on main"* ]]
}

@test "rejects fixup! on master" {
    checkout_branch "$REPO" master
    write_msg "fixup! feat: thing"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -ne 0 ]
}

@test "GIT_HOOKS_SKIP=1 short-circuits even on bad input" {
    write_msg "garbage that would normally fail"
    GIT_HOOKS_SKIP=1 run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
}

@test "subject starting with - does not break here-string handling" {
    # Branch where head: was an `echo $X | grep` ate `-` as flag
    write_msg "feat: -fix typo in flag handling"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
}

@test "dispatches to local-commit-msg when present and executable" {
    cat > "$REPO/.git-hooks/local-commit-msg" <<'EOF'
#!/usr/bin/env bash
echo "LOCAL_FIRED"
EOF
    chmod +x "$REPO/.git-hooks/local-commit-msg"
    write_msg "feat: trigger local"
    run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_FIRED"* ]]
}
