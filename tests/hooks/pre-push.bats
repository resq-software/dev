#!/usr/bin/env bats
# Branch naming, force-push guard, stdin propagation in the canonical pre-push hook.

load helpers

setup() {
    REPO="$(mktemp -d)"
    init_repo_with_hooks "$REPO"
}

teardown() {
    rm -rf "$REPO"
}

# Generates a fake "git push" stdin line for one ref.
# Args: local_ref local_sha remote_ref remote_sha
push_line() { printf '%s %s %s %s\n' "$1" "$2" "$3" "$4"; }

@test "accepts feat/ branch name" {
    git -C "$REPO" checkout -q -b feat/add-thing
    run bash -c "cd '$REPO' && bash .git-hooks/pre-push origin git@example </dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pre-push checks passed"* ]]
}

@test "rejects bad branch name" {
    git -C "$REPO" checkout -q -b nope/bad-prefix
    run bash -c "cd '$REPO' && bash .git-hooks/pre-push origin git@example </dev/null"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not follow naming convention"* ]]
}

@test "skips check on main" {
    checkout_branch "$REPO" main
    run bash -c "cd '$REPO' && bash .git-hooks/pre-push origin git@example </dev/null"
    [ "$status" -eq 0 ]
}

@test "skips check on changeset-release/* branches" {
    git -C "$REPO" checkout -q -b changeset-release/main
    run bash -c "cd '$REPO' && bash .git-hooks/pre-push origin git@example </dev/null"
    [ "$status" -eq 0 ]
}

@test "GIT_HOOKS_SKIP=1 short-circuits" {
    git -C "$REPO" checkout -q -b nope/bad
    GIT_HOOKS_SKIP=1 run bash -c "cd '$REPO' && bash .git-hooks/pre-push origin git@example </dev/null"
    [ "$status" -eq 0 ]
}

@test "local-pre-push receives the push refs on stdin" {
    git -C "$REPO" checkout -q -b feat/x
    cat > "$REPO/.git-hooks/local-pre-push" <<'EOF'
#!/usr/bin/env bash
# Echo what's on stdin so the test can verify propagation.
echo "LOCAL_STDIN_BEGIN"
cat
echo "LOCAL_STDIN_END"
EOF
    chmod +x "$REPO/.git-hooks/local-pre-push"

    LINE="$(push_line refs/heads/feat/x abc1234 refs/heads/feat/x def5678)"
    run bash -c "cd '$REPO' && printf '%s\n' '$LINE' | bash .git-hooks/pre-push origin git@example"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_STDIN_BEGIN"* ]]
    [[ "$output" == *"$LINE"* ]]
    [[ "$output" == *"LOCAL_STDIN_END"* ]]
}

@test "force push to main is rejected" {
    checkout_branch "$REPO" main
    # local sha (HEAD) and a fake remote sha that isn't an ancestor → force push.
    LOCAL=$(git -C "$REPO" rev-parse HEAD)
    REMOTE="0000000000000000000000000000000000000001"  # arbitrary non-zero sha
    LINE="$(push_line refs/heads/main "$LOCAL" refs/heads/main "$REMOTE")"
    run bash -c "cd '$REPO' && printf '%s\n' '$LINE' | bash .git-hooks/pre-push origin git@example"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Force push"* ]]
}

@test "fast-forward push to main is allowed" {
    checkout_branch "$REPO" main
    OLD=$(git -C "$REPO" rev-parse HEAD)
    commit_no_hooks "$REPO" "feat: more"
    NEW=$(git -C "$REPO" rev-parse HEAD)
    LINE="$(push_line refs/heads/main "$NEW" refs/heads/main "$OLD")"
    run bash -c "cd '$REPO' && printf '%s\n' '$LINE' | bash .git-hooks/pre-push origin git@example"
    [ "$status" -eq 0 ]
}

@test "branch starting with - does not break grep here-string handling" {
    # `git checkout -b -foo` is rejected by git itself, so we target the
    # naming-convention check only — the regex must handle a `-` safely.
    # Use a name that begins with a normal prefix but contains tricky chars.
    git -C "$REPO" checkout -q -b "feat/-leading-dash"
    run bash -c "cd '$REPO' && bash .git-hooks/pre-push origin git@example </dev/null"
    [ "$status" -eq 0 ]
}
