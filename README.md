<div align="center">
  <h1>🛠 ResQ Dev Setup</h1>
  <p><em>One command to bootstrap the entire ResQ development environment.</em></p>

  [![License](https://img.shields.io/badge/license-Apache--2.0-blue?style=flat-square)](LICENSE)
  [![Shell](https://img.shields.io/badge/Shell-bash-4EAA25?style=flat-square)](#)
  [![Nix](https://img.shields.io/badge/Nix-flakes-5277C3?style=flat-square)](#)
  [![Make](https://img.shields.io/badge/GNU-Make-A42E2B?style=flat-square)](#)
</div>

---

## ⚡ Onboarding in one curl

```bash
# Default clone target is ~/resq; override with RESQ_DIR=...
curl -fsSL https://get.resq.software | sh
```

This endpoint is not a redirect to `main`. It serves one pinned commit and
SHA-256 verifies every byte before sending it; on mismatch it returns 502 with a
shell snippet that exits non-zero, never installer bytes.

Merging to `main` does not by itself change what you get here. What you receive
is decided by the pinned digests in `worker/src/index.ts`, so it changes only
when a reviewed pin bump merges and deploys. Cutting a release does not move
this endpoint either: the release publishes the artifacts, and a separate
reviewed pull request repoints the pins at them.

You do not have to take that on faith. Verify against a single immutable
release, so the installer and the digest list cannot describe different
versions:

```bash
REL=https://get.resq.software/v0.4.0

curl -fsSL "$REL/SHA256SUMS"
curl -fsSL "$REL/install.sh" | sha256sum   # must match the install.sh line

# Or just read it before running it
curl -fsSL "$REL/install.sh" -o install.sh
less install.sh && sh install.sh
```

The unversioned paths work too, but a deploy landing between the two requests
would leave you comparing an installer from one release against digests from
another.

Pin to an exact release, which never changes:

```bash
curl -fsSL https://get.resq.software/v0.4.0/install.sh | sh
```

What happens, in order:

1. Installs `gh` (GitHub CLI) if missing
2. Authenticates with GitHub
3. Installs [Nix](https://nixos.org) via the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer) for reproducible toolchains
4. Lets you choose which repo to clone
5. Runs `nix develop` to build the dev environment
6. Installs the canonical git hooks (delegating to `resq pre-commit`)
7. Offers to scaffold a repo-type-specific `local-pre-push` (auto-detects Rust / Python / Node / .NET / C++ / Nix)

Run unattended (CI / provisioning):

```bash
REPO=npm YES=1 RESQ_DIR=/srv/work \
  curl -fsSL https://get.resq.software | sh
```

For provisioning, prefer a version-pinned URL so a later release cannot change
what your machines install without you deciding to:

```bash
REPO=npm YES=1 curl -fsSL https://get.resq.software/v0.4.0/install.sh | sh
```

---

## 📦 Repositories

| Repo | What | Languages |
|---|---|---|
| [`programs`](https://github.com/resq-software/programs) | Solana on-chain programs | Rust (Anchor) |
| [`dotnet-sdk`](https://github.com/resq-software/dotnet-sdk) | .NET client libraries | C# |
| [`pypi`](https://github.com/resq-software/pypi) | Python packages (MCP + DSA) | Python |
| [`crates`](https://github.com/resq-software/crates) | Rust workspace (CLI + DSA + `resq` binary) | Rust |
| [`npm`](https://github.com/resq-software/npm) | TypeScript packages (UI + DSA) | TypeScript |
| [`vcpkg`](https://github.com/resq-software/vcpkg) | C++ libraries | C++ |
| [`viz`](https://github.com/resq-software/viz) | 3D visualization — Three.js/Cesium web + Unity | TypeScript / C# |
| [`docs`](https://github.com/resq-software/docs) | Documentation site | MDX |
| [`dev`](https://github.com/resq-software/dev) | This repo — install scripts and onboarding | Shell / PowerShell |

Public repos sync to the monorepo automatically.

This table is the public, non-archived, non-fork set (excluding `.github`), and
it is the same list the installers offer. `landing` used to appear here and in the installer
menu; it is now private, so choosing it failed at clone time. The rule is
mechanical on purpose — `repo-drift.yml` re-derives it from the GitHub API and
fails when this list and reality disagree, so the next such change is caught by
CI rather than by whoever runs the installer next.

---

## 🛠 Standalone scripts

Each script can be run on its own without going through the full onboarding flow.

| Script | Use case | Bootstrap |
|---|---|---|
| `install.sh` / `install.ps1` | Full onboarding — installs prereqs, clones a repo, sets up dev env + hooks | `curl -fsSL https://get.resq.software \| sh` |
| `install-hooks.sh` / `install-hooks.ps1` | Drop the canonical git hooks into any repo. Asks to scaffold `local-pre-push` if `resq` is on PATH | `cd <repo> && curl -fsSL https://get.resq.software/hooks.sh \| sh` |
| `install-resq.sh` | Install the `resq` CLI binary from the latest GitHub Release (SHA256-verified). Falls back to `cargo install --git --rev <pinned commit>` when no release asset matches — today that fallback is the only path, since no `resq-cli-v*` release exists yet | `curl -fsSL https://get.resq.software/resq.sh \| sh` |

Every one of these is served pinned and hash-verified, and each has a
version-locked form — `https://get.resq.software/v0.4.0/hooks.sh` and so on.
`https://get.resq.software/SHA256SUMS` lists the digest of all of them, keyed
by the route name you fetch, so it works directly with `sha256sum -c`:

```sh
curl -fsSLO https://get.resq.software/SHA256SUMS
curl -fsSLO https://get.resq.software/install.sh
curl -fsSLO https://get.resq.software/hooks.sh
sha256sum --ignore-missing -c SHA256SUMS
```

Be clear about what that check is worth, because it is easy to overstate.

`SHA256SUMS` and the artifacts both come from `get.resq.software`. Comparing
them detects a truncated download or corruption in transit; it does **not**
detect a compromised endpoint, because anything able to alter the artifact can
serve a manifest that agrees with it. Two files from one origin are one source,
not two, and this check has no independent trust anchor.

The pinning described above defends a different hop. The Worker verifies what
GitHub returns against digests baked into its deploy, so a tampered
`raw.githubusercontent.com` response — or anything altered between the Worker
and GitHub — is refused before a byte reaches you. That is real, and it is not
the same as protecting you from us.

Closing the remaining gap needs a signature verifiable offline against a public
key rather than against our word. Tracked in
[#58](https://github.com/resq-software/dev/issues/58); until it lands, treat
these digests as an integrity check, not proof of origin.

Common env vars across all of them:
- `YES=1` — skip prompts (CI / provisioning)
- `GIT_HOOKS_SKIP=1` — disable installed hooks for a session
- `RESQ_SKIP_LOCAL_SCAFFOLD=1` — opt out of the `local-pre-push` scaffold prompt

To pin a revision, use a version-locked URL rather than an environment
variable. (This section previously documented `RESQ_DEV_REF=<sha|tag>`; no
script has ever implemented it, so it silently did nothing.)

`install.sh` additionally honours `REPO`, `RESQ_DIR`, `RESQ_BIN_DIR`,
`SKIP_RESQ_CLI` and `NO_COLOR` — run `sh install.sh --help` for the current
list.

---

## 🚀 Quick Start per Repo

| Repo | Language | Setup |
|------|----------|-------|
| programs | Rust / Anchor | `anchor build` |
| dotnet | C# / .NET 9 | `dotnet restore` |
| dotnet-sdk | C# / .NET 9 | `dotnet restore` |
| pypi | Python | `uv sync` |
| crates | Rust | `cargo build` |
| npm | TypeScript | `bun install` |
| vcpkg | C++ | `cmake --preset default` |
| viz | TypeScript / C# | `bun install` · `dotnet restore` |
| docs | MDX / Mintlify | `mintlify dev` |
| dev | Shell / PowerShell | `shellcheck install.sh` · `node worker/test/index.test.mjs` |


## 🏷 Releasing

One authored value, one action:

```bash
echo 0.4.1 > VERSION
sh bin/stamp.sh          # propagates VERSION + hook digests into both installers
# open a PR, merge it — that is the release
```

**Do not tag by hand.** Merging a `VERSION` change to `main` is what releases:
CI validates it, creates the tag itself, publishes the Release and
`SHA256SUMS`, and opens a pin-bump PR. Merging *that* is what changes the bytes
`https://get.resq.software` serves.

Two gates, both ordinary code review:

| merging | changes |
|---|---|
| a `VERSION` bump | what is published as a release |
| the pin-bump PR | what users actually receive |

Everything else is generated. `bin/stamp.sh --check` runs on every pull
request and verifies by regeneration, so a stamped value cannot be forgotten —
forgetting it is a diff. Values marked `GENERATED` should never be hand-edited.

No Cloudflare credential is stored in GitHub. Deployment is Cloudflare Workers
Builds pulling from this repository, and `worker-live` afterwards checks that
the endpoint serves exactly what `main` declares — hashing the bytes on the
wire, not trusting the Worker's own claim about them.

`AGENTS.md` has the full reasoning, including why tagging is an output of the
release rather than its trigger.

## Contributor guide

Every ResQ repo ships an `AGENTS.md` at the root — the canonical plain-text dev guide. That's where the build/test/lint commands, architecture notes, and standards for that specific repo live. Read it first.

Org-wide guidance (onboarding, hooks contract, commit format, PR process) lives in the `.github` org repo: [CONTRIBUTING.md](https://github.com/resq-software/.github/blob/main/CONTRIBUTING.md), [SECURITY.md](https://github.com/resq-software/.github/blob/main/SECURITY.md), [CODE_OF_CONDUCT.md](https://github.com/resq-software/.github/blob/main/CODE_OF_CONDUCT.md). Every public repo falls back to those automatically.


## 🔧 Toolchain

Everything is pinned via Nix flakes. No "works on my machine" issues.

| Language | Tools |
|---|---|
| Rust | `rustc`, `cargo`, `clippy`, `rustfmt`, `cargo-deny` |
| TypeScript | `bun`, `node`, `turbo` |
| Python | `python 3.12`, `uv`, `ruff`, `mypy` |
| C# | `dotnet 9` |
| C++ | `gcc`, `cmake`, `clang-format` |
| Protobuf | `buf`, `protoc` |
| Solana | `solana-cli`, `anchor` |

## ✅ Quality gates — canonical git hooks

Six hook shims live in [`resq-software/crates`](https://github.com/resq-software/crates/tree/master/crates/resq-cli/templates/git-hooks) — embedded in the `resq` binary *and* served at a stable raw URL. `install-hooks.sh` picks the best path automatically:

1. **`resq` on PATH** → calls `resq hooks install`, which scaffolds the 6 canonical hooks from the templates embedded in the binary. Offline, versioned with the installed `resq`.
2. **No `resq`** → falls back to `curl` from `resq-software/crates/master/.../templates/git-hooks/`.

The hooks delegate logic back to the `resq` binary (`resq pre-commit`, etc.), so updates roll out via `cargo install --git` (or `install-resq.sh`) without editing every repo.

| Hook | What it gates |
|---|---|
| `pre-commit` | `resq pre-commit` — copyright, secrets, audit, polyglot format |
| `commit-msg` | Conventional Commits + `!` marker; blocks `WIP:` / `fixup!` / `squash!` on main |
| `prepare-commit-msg` | Prepends `[TICKET-123]` from branch name |
| `pre-push` | Force-push guard, branch-naming convention (`feat/`, `fix/`, …, `changeset-release/*` allowed) |
| `post-checkout` / `post-merge` | Notifies on lock-file changes (Cargo, bun, uv, flake) |

Each hook then dispatches to `.git-hooks/local-<hook-name>` (if executable) — the **only** place a repo commits hook customization. Generate one with the right language template:

```bash
resq hooks scaffold-local --kind auto    # detects rust/python/node/dotnet/cpp/nix
```

`resq hooks doctor` reports drift, `resq hooks update` re-syncs from the embedded canonical, `resq hooks status` prints a one-line shell-friendly summary.

The canonical content lives in exactly one place: [`crates/resq-cli/templates/git-hooks/`](https://github.com/resq-software/crates/tree/master/crates/resq-cli/templates/git-hooks). The crates repo's own `.git-hooks/` (for dog-fooding) is kept identical via `hooks-sync.yml`. The `dev/` repo used to ship a third copy and was retired in Phase 4 — `install-hooks.sh` now fetches from the crates source (or lets `resq hooks install` do it offline). Bats + Rust integration tests cover the hook behavior end-to-end.

## 📄 License

Apache License 2.0
