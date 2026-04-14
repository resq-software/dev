#!/usr/bin/env bats
# Lock-file change notices and local dispatch for post-checkout/post-merge.

load helpers

setup() {
    REPO="$(mktemp -d)"
    init_repo_with_hooks "$REPO"
}

teardown() {
    rm -rf "$REPO"
}

@test "post-checkout notifies on Cargo.lock change" {
    PREV=$(git -C "$REPO" rev-parse HEAD)
    printf 'lock\n' > "$REPO/Cargo.lock"
    git -C "$REPO" add Cargo.lock
    git -C "$REPO" -c "core.hooksPath=" commit -q -m "feat: lock"
    NEW=$(git -C "$REPO" rev-parse HEAD)
    run run_hook "$REPO" post-checkout "$PREV" "$NEW" 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cargo.lock changed"* ]]
}

@test "post-checkout silent when no lockfile changed" {
    PREV=$(git -C "$REPO" rev-parse HEAD)
    git -C "$REPO" commit --allow-empty -q -m "feat: nothing"
    NEW=$(git -C "$REPO" rev-parse HEAD)
    run run_hook "$REPO" post-checkout "$PREV" "$NEW" 1
    [ "$status" -eq 0 ]
    [[ "$output" != *"changed"* ]]
}

@test "post-checkout dispatches to local-post-checkout" {
    cat > "$REPO/.git-hooks/local-post-checkout" <<'EOF'
#!/usr/bin/env bash
echo "LOCAL_POST_CHECKOUT_RAN"
EOF
    chmod +x "$REPO/.git-hooks/local-post-checkout"
    PREV=$(git -C "$REPO" rev-parse HEAD)
    commit_no_hooks "$REPO" "x"
    NEW=$(git -C "$REPO" rev-parse HEAD)
    run run_hook "$REPO" post-checkout "$PREV" "$NEW" 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_POST_CHECKOUT_RAN"* ]]
}

@test "GIT_HOOKS_SKIP=1 short-circuits post-checkout" {
    cat > "$REPO/.git-hooks/local-post-checkout" <<'EOF'
#!/usr/bin/env bash
echo "SHOULD_NOT_RUN"
EOF
    chmod +x "$REPO/.git-hooks/local-post-checkout"
    PREV=$(git -C "$REPO" rev-parse HEAD)
    commit_no_hooks "$REPO" "x"
    NEW=$(git -C "$REPO" rev-parse HEAD)
    GIT_HOOKS_SKIP=1 run run_hook "$REPO" post-checkout "$PREV" "$NEW" 1
    [ "$status" -eq 0 ]
    [[ "$output" != *"SHOULD_NOT_RUN"* ]]
}
