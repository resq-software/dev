#!/usr/bin/env bats
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
# The GIT_HOOKS_SKIP contract.
#
# Regression suite for the incident of 2026-08: an operator ran
# `GIT_HOOKS_SKIP=audit` four times believing it skipped only the security
# audit. The guard was `[ -n "${GIT_HOOKS_SKIP:-}" ] && exit 0`, so ANY
# non-empty value silently disabled the ENTIRE hook. Copyright, Large Files,
# Debug Stmts and — critically — the Secrets scan never ran, while the commit
# messages recorded that they had passed. The secret scan is this org's
# compensating control for not licensing GitHub Secret Protection, so a skip
# mechanism that looks selective but is total is a hole in that control.
#
# The contract these tests pin:
#
#   GIT_HOOKS_SKIP is a token list (comma, colon or space separated,
#   case-insensitive). The vocabulary is global across every canonical hook,
#   so a value exported once for a shell session cannot mean different things
#   in different hooks; a token owned by another hook is inert, not an error.
#
#     all | 1 | true | yes | on   disable this hook entirely (loud warning)
#     0 | false | no | off | none skip nothing (explicit no-op)
#     audit / format / versioning pre-commit steps
#     msg-format / wip-guard      commit-msg checks
#     force-push / branch-name    pre-push guards
#     notify                      post-merge, post-checkout lockfile notices
#     local                       the repo-local local-<hook> override
#
#   There is deliberately NO token for the secrets scan — it is reachable only
#   via the all-off value, which announces itself loudly.
#
#   Anything else FAILS CLOSED. On a gating hook (pre-commit, commit-msg) the
#   hook refuses to run at all; on a non-gating hook it discards the whole
#   variable and runs every check. Either way an unrecognized value never
#   causes a check to be skipped.
#
#   Every honoured skip is ANNOUNCED on stderr, naming what was skipped and
#   what still ran. A skip is never silent.
#
# WHY ASSERTIONS USE THE "✅ " PREFIX
# Announcing a skip means naming the disabled checks, so "Secrets scan" and
# "Security audit" appear in the hook's own output whether or not they ran.
# Only the pass marker separates "this check ran" from "this check was named
# in the announcement". Tests therefore assert on "✅ Secrets", not "Secrets".
# The marker comes from the fake resq backend in helpers.bash, which mirrors
# crates/resq-cli/src/commands/pre_commit.rs :: run_plain().
#
# WHICH HOOKS THIS DESCRIBES
# The templates come from the crates commit scripts/install-hooks.sh pins (see
# helpers.bash), i.e. the hooks a user is actually installed. The granular
# parser landed in resq-software/crates#206; any pin older than that carries the
# blanket guard and fails test 1 by construction.
#
# Known gap at the current pin: prepare-commit-msg has no GIT_HOOKS_SKIP
# handling at all — not even `all` or `local` stop its ticket prefix or its
# local-prepare-commit-msg dispatch. It gates nothing, so this suite does not
# pin that behaviour either way; the docs state the exception.

load helpers

setup() {
    REPO="$(mktemp -d)"
    init_repo_with_hooks "$REPO"
    install_fake_resq
    MSG="$REPO/.msg"
}

teardown() {
    remove_fake_resq
    rm -rf "$REPO"
}

write_msg() { printf '%s\n' "$1" > "$MSG"; }

# ── The incident: a granular skip must stay granular ─────────────────────────

@test "GIT_HOOKS_SKIP=audit still runs the secrets scan" {
    GIT_HOOKS_SKIP=audit run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Secrets"* ]]
}

@test "GIT_HOOKS_SKIP=audit does not run the security audit" {
    GIT_HOOKS_SKIP=audit run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"✅ Audit"* ]]
}

@test "GIT_HOOKS_SKIP=audit still runs copyright, large-file and debug checks" {
    # The four checks the incident's commit messages claimed had passed.
    GIT_HOOKS_SKIP=audit run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Copyright"* ]]
    [[ "$output" == *"✅ Large Files"* ]]
    [[ "$output" == *"✅ Debug Stmts"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
}

@test "GIT_HOOKS_SKIP=audit announces the skip rather than skipping silently" {
    GIT_HOOKS_SKIP=audit run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"GIT_HOOKS_SKIP"* ]]
    [[ "${output,,}" == *"skipped"* ]]
}

@test "GIT_HOOKS_SKIP=audit still dispatches to local-pre-commit" {
    cat > "$REPO/.git-hooks/local-pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "LOCAL_PRE_COMMIT_RAN"
EOF
    chmod +x "$REPO/.git-hooks/local-pre-commit"
    GIT_HOOKS_SKIP=audit run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_PRE_COMMIT_RAN"* ]]
}

# ── The other granular tokens ────────────────────────────────────────────────

@test "GIT_HOOKS_SKIP=format skips formatting but keeps the secrets scan" {
    GIT_HOOKS_SKIP=format run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"✅ Format Rust"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
    [[ "$output" == *"✅ Audit"* ]]
}

@test "GIT_HOOKS_SKIP=versioning asks resq to skip versioning and keeps the secrets scan" {
    # resq's plain-mode runner has no versioning step to observe, so assert on
    # what the hook controls: the flag it passes, and what it announces.
    GIT_HOOKS_SKIP=versioning run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"resq-args: "*"--skip-versioning"* ]]
    [[ "$output" == *"SKIPPED: "*"Versioning"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
}

@test "each pre-commit token passes exactly its own flag to resq" {
    GIT_HOOKS_SKIP=audit run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"resq-args: "*"--skip-audit"* ]]
    [[ "$output" != *"--skip-format"* ]]
    [[ "$output" != *"--skip-versioning"* ]]
}

@test "GIT_HOOKS_SKIP accepts a comma-separated list and keeps the secrets scan" {
    GIT_HOOKS_SKIP=audit,format run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"✅ Audit"* ]]
    [[ "$output" != *"✅ Format Rust"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
}

@test "GIT_HOOKS_SKIP accepts a colon-separated list" {
    GIT_HOOKS_SKIP=audit:format run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"✅ Audit"* ]]
    [[ "$output" != *"✅ Format Rust"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
}

@test "GIT_HOOKS_SKIP accepts a space-separated list" {
    GIT_HOOKS_SKIP="audit format" run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"✅ Audit"* ]]
    [[ "$output" != *"✅ Format Rust"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
}

@test "GIT_HOOKS_SKIP=local skips local-pre-commit but not the canonical checks" {
    cat > "$REPO/.git-hooks/local-pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "LOCAL_PRE_COMMIT_RAN"
EOF
    chmod +x "$REPO/.git-hooks/local-pre-commit"
    GIT_HOOKS_SKIP=local run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"LOCAL_PRE_COMMIT_RAN"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
}

@test "a token owned by another hook is inert, and says nothing was disabled" {
    GIT_HOOKS_SKIP=msg-format run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"disables nothing"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
    [[ "$output" == *"✅ Audit"* ]]
}

@test "GIT_HOOKS_SKIP=msg-format accepts a non-conventional subject" {
    write_msg "wat: this is not a type"
    GIT_HOOKS_SKIP=msg-format run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: "*"Conventional Commits"* ]]
}

@test "GIT_HOOKS_SKIP=wip-guard allows a WIP commit on main" {
    checkout_branch "$REPO" main
    write_msg "WIP: still working"
    GIT_HOOKS_SKIP=wip-guard,msg-format run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: "*"WIP guard"* ]]
}

@test "GIT_HOOKS_SKIP=branch-name allows a badly named branch push" {
    LOCAL=$(git -C "$REPO" rev-parse HEAD)
    LINE="refs/heads/nope/bad-prefix $LOCAL refs/heads/nope/bad-prefix 0000000000000000000000000000000000000000"
    GIT_HOOKS_SKIP=branch-name run bash -c "cd '$REPO' && printf '%s\n' '$LINE' | bash .git-hooks/pre-push origin git@example"
    [ "$status" -eq 0 ]
    [[ "$output" != *"does not follow naming convention"* ]]
    [[ "$output" == *"SKIPPED: "*"Branch naming"* ]]
}

@test "GIT_HOOKS_SKIP=force-push allows a force push to main, and announces it" {
    checkout_branch "$REPO" main
    LOCAL=$(git -C "$REPO" rev-parse HEAD)
    LINE="refs/heads/main $LOCAL refs/heads/main 0000000000000000000000000000000000000001"
    GIT_HOOKS_SKIP=force-push run bash -c "cd '$REPO' && printf '%s\n' '$LINE' | bash .git-hooks/pre-push origin git@example"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Force push to main is not allowed"* ]]
    [[ "$output" == *"SKIPPED: "*"orce"* ]]
}

@test "GIT_HOOKS_SKIP=notify silences the post-checkout lock-file notice" {
    PREV=$(git -C "$REPO" rev-parse HEAD)
    printf 'lock\n' > "$REPO/Cargo.lock"
    git -C "$REPO" add Cargo.lock
    commit_no_hooks "$REPO" "feat: lock"
    NEW=$(git -C "$REPO" rev-parse HEAD)
    GIT_HOOKS_SKIP=notify run run_hook "$REPO" post-checkout "$PREV" "$NEW" 1
    [ "$status" -eq 0 ]
    [[ "$output" != *"Cargo.lock changed"* ]]
}

@test "GIT_HOOKS_SKIP=0 is an explicit no-op, not a skip" {
    # Under the old `[ -n "${GIT_HOOKS_SKIP:-}" ] && exit 0` guard the literal
    # string "0" was non-empty, so it disabled every check — the exact
    # opposite of what anyone writing it would intend.
    GIT_HOOKS_SKIP=0 run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Secrets"* ]]
    [[ "$output" == *"✅ Audit"* ]]
}

@test "GIT_HOOKS_SKIP=false is an explicit no-op, not a skip" {
    GIT_HOOKS_SKIP=false run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Secrets"* ]]
    [[ "$output" == *"✅ Audit"* ]]
}

@test "GIT_HOOKS_SKIP is case-insensitive" {
    GIT_HOOKS_SKIP=AUDIT run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"✅ Audit"* ]]
    [[ "$output" == *"✅ Secrets"* ]]
}

# ── Fail closed on anything unrecognized ─────────────────────────────────────

@test "GIT_HOOKS_SKIP=typo fails closed instead of skipping everything" {
    GIT_HOOKS_SKIP=typo run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -ne 0 ]
    [[ "$output" == *"typo"* ]]
}

@test "GIT_HOOKS_SKIP=typo names the accepted values" {
    GIT_HOOKS_SKIP=typo run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -ne 0 ]
    [[ "$output" == *"audit"* ]]
    [[ "$output" == *"format"* ]]
    [[ "$output" == *"versioning"* ]]
}

@test "a typo'd token inside an otherwise valid list still fails closed" {
    # The dangerous shape: one good token lends the whole list credibility.
    GIT_HOOKS_SKIP=audit,tpyo run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -ne 0 ]
    [[ "$output" == *"tpyo"* ]]
}

@test "the secrets scan has no token of its own" {
    # Asking for it by name is refused, and says why.
    GIT_HOOKS_SKIP=secrets run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -ne 0 ]
    [[ "${output,,}" == *"secret"* ]]
    [[ "$output" != *"✅ Copyright"* ]]
}

@test "an unrecognized value never skips a commit-msg check" {
    # Holds whether the hook hard-fails on the bad token or discards the
    # variable and runs everything: either way the bad message is rejected.
    write_msg "wat: this is not a type"
    GIT_HOOKS_SKIP=typo run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"typo"* ]]
}

# ── Granular tokens must not disarm unrelated hooks ──────────────────────────

@test "GIT_HOOKS_SKIP=audit still rejects a bad commit message" {
    write_msg "wat: this is not a type"
    GIT_HOOKS_SKIP=audit run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid commit message"* ]]
}

@test "GIT_HOOKS_SKIP=audit still enforces the branch naming convention" {
    # The rule reads the ref being pushed to (stdin), not the checked-out
    # branch, so the push line has to name the bad branch.
    LOCAL=$(git -C "$REPO" rev-parse HEAD)
    LINE="refs/heads/nope/bad-prefix $LOCAL refs/heads/nope/bad-prefix 0000000000000000000000000000000000000000"
    GIT_HOOKS_SKIP=audit run bash -c "cd '$REPO' && printf '%s\n' '$LINE' | bash .git-hooks/pre-push origin git@example"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not follow naming convention"* ]]
}

@test "GIT_HOOKS_SKIP=audit still blocks a force push to main" {
    checkout_branch "$REPO" main
    LOCAL=$(git -C "$REPO" rev-parse HEAD)
    REMOTE="0000000000000000000000000000000000000001"
    LINE="refs/heads/main $LOCAL refs/heads/main $REMOTE"
    GIT_HOOKS_SKIP=audit run bash -c "cd '$REPO' && printf '%s\n' '$LINE' | bash .git-hooks/pre-push origin git@example"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Force push"* ]]
}

# ── The blunt instrument still works, but says so ────────────────────────────

@test "GIT_HOOKS_SKIP=1 still skips every check" {
    GIT_HOOKS_SKIP=1 run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" != *"✅ Copyright"* ]]
    [[ "$output" != *"✅ Secrets"* ]]
    [[ "$output" != *"✅ Audit"* ]]
}

@test "GIT_HOOKS_SKIP=1 warns that it disabled the hooks" {
    GIT_HOOKS_SKIP=1 run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"GIT_HOOKS_SKIP=1"* ]]
    [[ "${output,,}" == *"disabled"* ]]
}

@test "GIT_HOOKS_SKIP=1 names the secret scan as one of the disabled controls" {
    # The incident's real cost: commit messages claimed a scan that never ran.
    # The operator must be told, by name, that the scanner is off.
    GIT_HOOKS_SKIP=1 run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "${output,,}" == *"secret"* ]]
}

@test "GIT_HOOKS_SKIP=1 warns from commit-msg as well" {
    write_msg "garbage that would normally fail"
    GIT_HOOKS_SKIP=1 run run_hook "$REPO" commit-msg "$MSG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GIT_HOOKS_SKIP=1"* ]]
}

# ── Unset / empty must remain a full, quiet run ──────────────────────────────

@test "unset GIT_HOOKS_SKIP runs every check" {
    run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Secrets"* ]]
    [[ "$output" == *"✅ Audit"* ]]
}

@test "empty GIT_HOOKS_SKIP runs every check and announces nothing" {
    GIT_HOOKS_SKIP= run run_hook_with_resq "$REPO" pre-commit
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Secrets"* ]]
    [[ "$output" == *"✅ Audit"* ]]
    [[ "$output" != *"GIT_HOOKS_SKIP"* ]]
}
