#!/usr/bin/env bats
# Ticket-prefix injection in the canonical prepare-commit-msg hook.

load helpers

setup() {
    REPO="$(mktemp -d)"
    init_repo_with_hooks "$REPO"
    MSG="$REPO/.msg"
}

teardown() {
    rm -rf "$REPO"
}

@test "prepends ticket from branch name" {
    git -C "$REPO" checkout -q -b feat/ABC-123-do-the-thing
    printf 'feat: do the thing\n' > "$MSG"
    run run_hook "$REPO" prepare-commit-msg "$MSG"
    [ "$status" -eq 0 ]
    grep -q "^\[ABC-123\] feat: do the thing$" "$MSG"
}

@test "leaves message untouched on branch with no ticket" {
    git -C "$REPO" checkout -q -b feat/no-ticket
    printf 'feat: nothing to prefix\n' > "$MSG"
    run run_hook "$REPO" prepare-commit-msg "$MSG"
    [ "$status" -eq 0 ]
    grep -q "^feat: nothing to prefix$" "$MSG"
}

@test "does not double-prepend when ticket already in message" {
    git -C "$REPO" checkout -q -b feat/ABC-123-thing
    printf '[ABC-123] feat: already there\n' > "$MSG"
    run run_hook "$REPO" prepare-commit-msg "$MSG"
    [ "$status" -eq 0 ]
    # Should still be exactly one occurrence
    [ "$(grep -c 'ABC-123' "$MSG")" -eq 1 ]
}

@test "skips on merge source" {
    git -C "$REPO" checkout -q -b feat/ABC-123
    printf 'Merge pull request #1\n' > "$MSG"
    run run_hook "$REPO" prepare-commit-msg "$MSG" merge
    [ "$status" -eq 0 ]
    grep -q "^Merge pull request" "$MSG"
    ! grep -q "ABC-123" "$MSG"
}

@test "skips on commit source" {
    git -C "$REPO" checkout -q -b feat/ABC-123
    printf 'feat: something\n' > "$MSG"
    run run_hook "$REPO" prepare-commit-msg "$MSG" commit
    [ "$status" -eq 0 ]
    ! grep -q "ABC-123" "$MSG"
}
