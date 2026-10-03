#!/bin/sh
# Copyright 2026 ResQ Systems, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# The release-binary path of scripts/install-resq.sh: which release it picks,
# what it refuses, and what it leaves behind.
#
# Hermetic. curl, gh and cargo are stubs serving fixtures built here; every
# other tool is reached through a toolbox of symlinks, so no real gh, cargo or
# network is involved. Each case runs under `env -i` with its own HOME,
# XDG_CONFIG_HOME and install dir — the script writes an install receipt, and
# a test must never write one into the real ~/.config.
#
# Run from the repository root:  sh tests/installers/release-path.sh
set -eu
SCRIPT="${1:-scripts/install-resq.sh}"
[ -f "$SCRIPT" ] || { printf 'fail  %s not found — run from the repository root\n' "$SCRIPT" >&2; exit 1; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

pass=0
fail=0
check() {
    if [ "$2" = "0" ]; then
        pass=$((pass + 1)); printf '  PASS  %s\n' "$1"
    else
        fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"
        [ -z "${3:-}" ] || printf '%s\n' "$3" | sed 's/^/        /'
    fi
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
FIX="$ROOT/fix"
mkdir -p "$FIX/assets" "$ROOT/tools" "$ROOT/stubs/base" "$ROOT/stubs/gh"

# ── Toolbox: only the real tools the script needs ───────────────────────────
for t in sh sed awk grep sort tail head mktemp tar gzip find install cp mv rm \
         mkdir cat basename dirname date uname cut tr chmod env sha256sum shasum; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    ln -s "$p" "$ROOT/tools/$t"
done

# ── Fixtures ────────────────────────────────────────────────────────────────
TARGETS="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-apple-darwin aarch64-apple-darwin"

# Stock macOS has shasum but not sha256sum; both print "<hash>  <name>".
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# release <version> <version its binary reports>
release() {
    _assets=""
    for _t in $TARGETS; do
        _name="resq-cli-resq-cli-v$1-$_t.tar.gz"
        _stage="$(mktemp -d)"
        printf '#!/bin/sh\necho "resq %s"\n' "$2" > "$_stage/resq"
        chmod +x "$_stage/resq"
        tar -czf "$FIX/assets/$_name" -C "$_stage" resq
        rm -rf "$_stage"
        _assets="$_assets $_name"
    done
    # shellcheck disable=SC2086
    (cd "$FIX/assets" && sha256 $_assets > "SHA256SUMS-$1")
    {
        printf '{\n  "tag_name": "resq-cli-v%s",\n  "prerelease": false,\n  "assets": [\n' "$1"
        for _a in $_assets "SHA256SUMS-$1"; do
            printf '    { "browser_download_url": "https://dl.invalid/%s" },\n' "$_a"
        done
        printf '  ]\n}\n'
    } > "$FIX/release-resq-cli-v$1.json"
}
release 0.5.9  0.5.9
release 0.5.10 0.5.10
release 0.5.11 0.0.1          # binary lies about its version
release 0.5.12 0.5.12
# 0.5.12's checksum file names the right asset with the wrong digest.
sed 's/^[0-9a-f]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' \
    "$FIX/assets/SHA256SUMS-0.5.12" > "$FIX/assets/x" && mv "$FIX/assets/x" "$FIX/assets/SHA256SUMS-0.5.12"

# The list, in the API's creation-date order: 0.5.9 created last, so a
# first-match picker takes it; 0.6.0 is a pre-release; resq-tui is another crate.
cat > "$FIX/releases.json" <<'JSON'
[
  {
    "tag_name": "resq-cli-v0.5.9",
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "resq-tui-v9.9.9",
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "resq-cli-v0.6.0",
    "draft": false,
    "prerelease": true
  },
  {
    "tag_name": "resq-cli-v0.5.10",
    "draft": false,
    "prerelease": false
  }
]
JSON

# ── Stubs ───────────────────────────────────────────────────────────────────
cat > "$ROOT/stubs/base/curl" <<'STUB'
#!/bin/sh
out=""; url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *)  url="$1"; shift ;;
    esac
done
echo "$url" >> "$FIX/curl.log"
case "$url" in
    *"/releases?per_page=100")
        [ "${CURL_API_FAIL:-0}" = 1 ] && exit 22
        src="$FIX/releases.json" ;;
    *"/releases/tags/"*) src="$FIX/release-${url##*/}.json" ;;
    https://dl.invalid/*) src="$FIX/assets/${url##*/}" ;;
    *) exit 22 ;;
esac
[ -f "$src" ] || exit 22
if [ -n "$out" ]; then cp "$src" "$out"; else cat "$src"; fi
STUB
cat > "$ROOT/stubs/base/cargo" <<'STUB'
#!/bin/sh
echo "$*" >> "$FIX/cargo.log"
STUB
cat > "$ROOT/stubs/gh/gh" <<'STUB'
#!/bin/sh
echo "$*" >> "$FIX/gh.log"
case "$1 ${2:-}" in
    "attestation verify")
        case " $* " in
            *" --help "*)
                # gh 2.49-2.67 has the subcommand but not these flags.
                [ "${GH_OLD:-0}" = 1 ] || echo "  --source-digest string   --source-ref string"
                exit 0 ;;
        esac
        exit "${GH_VERIFY_RC:-0}" ;;
    "auth status") exit 0 ;;
    api\ *)
        case "$2" in
            */commits/*) echo "${GH_TAG_SHA:-0123456789abcdef0123456789abcdef01234567}" ;;
            */compare/*) echo "${GH_COMPARE:-behind}" ;;
        esac
        exit 0 ;;
esac
exit 1
STUB
chmod +x "$ROOT"/stubs/*/*

# run_case [WITH_GH=1] [VAR=value ...] [-- script args...]
# Sets OUT, RC and C (the case dir: dest/, config/resq/install.json).
run_case() {
    C="$(mktemp -d "$ROOT/case.XXXXXX")"
    mkdir -p "$C/dest" "$C/home" "$C/config"
    rm -f "$FIX/curl.log" "$FIX/gh.log" "$FIX/cargo.log"
    _path="$ROOT/stubs/base:$ROOT/tools"
    _envs=""
    _args=""
    _in_args=0
    for _a in "$@"; do
        if [ "$_in_args" = 1 ]; then _args="$_args $_a"; continue; fi
        case "$_a" in
            --) _in_args=1 ;;
            WITH_GH=1) _path="$ROOT/stubs/gh:$_path" ;;
            *) _envs="$_envs $_a" ;;
        esac
    done
    set +e
    # shellcheck disable=SC2086
    OUT="$(cd "$C" && env -i PATH="$_path" HOME="$C/home" XDG_CONFIG_HOME="$C/config" \
        RESQ_INSTALL_DIR="$C/dest" FIX="$FIX" $_envs sh "$SCRIPT" $_args 2>&1)"
    RC=$?
    set -e
}
has() { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
receipt() { cat "$C/config/resq/install.json" 2>/dev/null || true; }

printf '\n== install-resq.sh release path ==\n'

# 1. An API failure is an error, not "no releases": no silent source build.
run_case CURL_API_FAIL=1
r=1; [ "$RC" -ne 0 ] && has "GitHub API request failed" && [ ! -f "$FIX/cargo.log" ] && r=0
check "a failed API request stops the install instead of building from source" "$r" "rc=$RC
$OUT"

# 2. Highest stable version by number, not first-created, not a pre-release.
run_case
r=1; grep -q '/releases/tags/resq-cli-v0.5.10$' "$FIX/curl.log" && r=0
check "picks the highest stable resq-cli version (0.5.10), not first-listed or pre-release" "$r" "$(cat "$FIX/curl.log")"

# 3. Without gh: installs on the checksum, says provenance was not checked.
r=1; [ "$RC" -eq 0 ] && has "provenance NOT checked" \
    && [ "$("$C/dest/resq" --version)" = "resq 0.5.10" ] && r=0
check "without gh: installs on SHA256SUMS and warns provenance was not checked" "$r" "rc=$RC
$OUT"
r=1; receipt | grep -q '"method": "release"' && receipt | grep -q '"provenance": "unchecked"' \
    && receipt | grep -q "\"path\": \"$C/dest/resq\"" && receipt | grep -q '"ref": "resq-cli-v0.5.10"' && r=0
check "writes a release receipt recording provenance=unchecked" "$r" "$(receipt)"

# 4. With gh: exact signer identity, source ref and digest, hosted runners only.
run_case WITH_GH=1 GH_TAG_SHA=abcabcabcabcabcabcabcabcabcabcabcabcabca
v="$(grep '^attestation verify ' "$FIX/gh.log" | grep -v -- '--help' || true)"
r=1; [ "$RC" -eq 0 ] \
    && case "$v" in *"--cert-identity https://github.com/resq-software/crates/.github/workflows/release.yml@refs/tags/resq-cli-v0.5.10"*) true ;; *) false ;; esac \
    && case "$v" in *"--cert-oidc-issuer https://token.actions.githubusercontent.com"*) true ;; *) false ;; esac \
    && case "$v" in *"--source-ref refs/tags/resq-cli-v0.5.10"*) true ;; *) false ;; esac \
    && case "$v" in *"--source-digest abcabcabcabcabcabcabcabcabcabcabcabcabca"*) true ;; *) false ;; esac \
    && case "$v" in *"--deny-self-hosted-runners"*) true ;; *) false ;; esac \
    && case "$v" in *"--signer-workflow"*) false ;; *) true ;; esac && r=0
check "with gh: verifies the exact release.yml@tag identity, source ref and digest" "$r" "rc=$RC verify call: $v
$OUT"
r=1; receipt | grep -q '"provenance": "verified"' && r=0
check "a verified install records provenance=verified" "$r" "$(receipt)"

# 5. A failed verification is fatal and installs nothing.
run_case WITH_GH=1 GH_VERIFY_RC=1
r=1; [ "$RC" -ne 0 ] && has "verification FAILED" && [ ! -e "$C/dest/resq" ] && r=0
check "a failed attestation refuses the install" "$r" "rc=$RC
$OUT"

# 6. A tag on a commit that is not on master is refused before verifying.
run_case WITH_GH=1 GH_COMPARE=diverged
r=1; [ "$RC" -ne 0 ] && has "not on resq-software/crates master" && [ ! -e "$C/dest/resq" ] && r=0
check "a release tag on unmerged code is refused" "$r" "rc=$RC
$OUT"

# 7. Provenance can be made mandatory.
run_case RESQ_REQUIRE_PROVENANCE=1
r=1; [ "$RC" -ne 0 ] && [ ! -e "$C/dest/resq" ] && r=0
check "RESQ_REQUIRE_PROVENANCE=1 without gh refuses" "$r" "rc=$RC
$OUT"

# 8. RESQ_ALLOW_UNVERIFIED skips the check deliberately, and says so.
run_case WITH_GH=1 RESQ_ALLOW_UNVERIFIED=1
r=1; [ "$RC" -eq 0 ] && has "NOT checked (RESQ_ALLOW_UNVERIFIED=1)" \
    && ! grep -qs '^attestation verify .*--cert-identity' "$FIX/gh.log" && r=0
check "RESQ_ALLOW_UNVERIFIED=1 skips provenance loudly" "$r" "rc=$RC
$OUT"

# 8b. Asking for both is a contradiction, not a silent win for "unverified".
run_case WITH_GH=1 RESQ_ALLOW_UNVERIFIED=1 RESQ_REQUIRE_PROVENANCE=1
r=1; [ "$RC" -ne 0 ] && has "contradict" && [ ! -e "$C/dest/resq" ] && r=0
check "RESQ_REQUIRE_PROVENANCE=1 with RESQ_ALLOW_UNVERIFIED=1 refuses" "$r" "rc=$RC
$OUT"

# 8c. A gh too old for --source-digest is "cannot check", not "check failed".
run_case WITH_GH=1 GH_OLD=1
r=1; [ "$RC" -eq 0 ] && has "provenance NOT checked" && ! has "verification FAILED" \
    && ! grep -qs '^attestation verify .*--cert-identity' "$FIX/gh.log" && r=0
check "gh without --source-digest (2.49-2.67) installs unchecked instead of failing" "$r" "rc=$RC
$OUT"

# 9. A binary that misreports its version never replaces the current one.
run_case -- 0.5.11
r=1; [ "$RC" -ne 0 ] && has "reports 'resq 0.0.1'" && [ ! -e "$C/dest/resq" ] && r=0
check "a binary reporting the wrong version is refused" "$r" "rc=$RC
$OUT"

# 10. A checksum mismatch is still fatal (regression guard).
run_case -- 0.5.12
r=1; [ "$RC" -ne 0 ] && has "SHA256 mismatch" && [ ! -e "$C/dest/resq" ] && r=0
check "a SHA256 mismatch still refuses the install" "$r" "rc=$RC
$OUT"

# 11. The replaced binary is kept as resq.prev; no staging file is left behind.
run_case -- 0.5.9
first="$C"
r=1
if [ "$RC" -eq 0 ]; then
    set +e
    OUT="$(cd "$first" && env -i PATH="$ROOT/stubs/base:$ROOT/tools" HOME="$first/home" \
        XDG_CONFIG_HOME="$first/config" RESQ_INSTALL_DIR="$first/dest" FIX="$FIX" \
        sh "$SCRIPT" 0.5.10 2>&1)"
    RC=$?
    set -e
    [ "$RC" -eq 0 ] && [ "$("$first/dest/resq" --version)" = "resq 0.5.10" ] \
        && [ "$("$first/dest/resq.prev" --version)" = "resq 0.5.9" ] \
        && [ -z "$(find "$first/dest" -name '.resq.new.*')" ] && r=0
fi
check "an upgrade keeps the previous binary as resq.prev and leaves no staging file" "$r" "rc=$RC
$OUT"

printf '\n%s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
