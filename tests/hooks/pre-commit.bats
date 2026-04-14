#!/usr/bin/env bats
# Soft-skip + local dispatch behavior in the canonical pre-commit hook.
# (The full `resq pre-commit` checks are exercised by resq-cli's own tests;
# here we verify wiring only.)

load helpers

setup() {
    REPO="$(mktemp -d)"
    init_repo_with_hooks "$REPO"
}

teardown() {
    rm -rf "$REPO"
}

@test "soft-skip with hint when resq is missing" {
    # Run with PATH that excludes any resq + override $HOME to a clean dir
    # so ~/.cargo/bin/resq isn't found either.
    EMPTY="$(mktemp -d)"
    PATH="/usr/bin:/bin" HOME="$EMPTY" run bash -c "cd '$REPO' && bash .git-hooks/pre-commit"
    rm -rf "$EMPTY"
    [ "$status" -eq 0 ]
    [[ "$output" == *"resq not found"* ]]
}

@test "GIT_HOOKS_SKIP=1 short-circuits before the resq lookup" {
    EMPTY="$(mktemp -d)"
    GIT_HOOKS_SKIP=1 PATH="/usr/bin:/bin" HOME="$EMPTY" run bash -c "cd '$REPO' && bash .git-hooks/pre-commit"
    rm -rf "$EMPTY"
    [ "$status" -eq 0 ]
    [[ "$output" != *"resq not found"* ]]
}

@test "dispatches to local-pre-commit even when resq is missing" {
    cat > "$REPO/.git-hooks/local-pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "LOCAL_PRE_COMMIT_RAN"
EOF
    chmod +x "$REPO/.git-hooks/local-pre-commit"
    EMPTY="$(mktemp -d)"
    PATH="/usr/bin:/bin" HOME="$EMPTY" run bash -c "cd '$REPO' && bash .git-hooks/pre-commit"
    rm -rf "$EMPTY"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_PRE_COMMIT_RAN"* ]]
}
