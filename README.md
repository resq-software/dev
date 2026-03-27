# ResQ Developer Setup

One command to get started with any ResQ repository.

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/resq-software/dev/main/install.ps1 | iex
```

Or inspect before running:

```bash
curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh -o install.sh
less install.sh
sh install.sh
```

## What happens

1. Installs `gh` (GitHub CLI) if missing
2. Authenticates with GitHub
3. Installs [Nix](https://nixos.org) via the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer) for reproducible toolchains
4. Lets you choose which repo to clone
5. Runs `nix develop` to build the dev environment
6. Configures git hooks automatically

```bash
# Change clone directory (default: ~/resq)
RESQ_DIR=/path/to/workspace curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh | sh
```

---

## Repositories

| Repo | What | Languages |
|---|---|---|
| [`resQ`](https://github.com/resq-software/resQ) | Platform monorepo | Polyglot (private) |
| [`programs`](https://github.com/resq-software/programs) | Solana on-chain programs | Rust (Anchor) |
| [`resq-proto`](https://github.com/resq-software/resq-proto) | Shared Protobuf definitions | Protobuf |
| [`dotnet-sdk`](https://github.com/resq-software/dotnet-sdk) | .NET client libraries | C# |
| [`pypi`](https://github.com/resq-software/pypi) | Python packages (MCP + DSA) | Python |
| [`crates`](https://github.com/resq-software/crates) | Rust workspace (CLI + DSA) | Rust |
| [`npm`](https://github.com/resq-software/npm) | TypeScript packages (UI + DSA) | TypeScript |
| [`vcpkg`](https://github.com/resq-software/vcpkg) | C++ libraries | C++ |
| [`landing`](https://github.com/resq-software/landing) | Marketing site | TypeScript |
| [`cms`](https://github.com/resq-software/cms) | Content management | TypeScript |
| [`docs`](https://github.com/resq-software/docs) | Documentation site | MDX |
| [`dev`](https://github.com/resq-software/dev) | This repo — install scripts and onboarding | Shell |

Public repos sync to the monorepo automatically.

---

## Quick start per repo

Every repo uses Nix flakes for its dev environment. The pattern is always `cd <repo> && nix develop`, then use the commands from that repo's `AGENTS.md`.

### resQ (monorepo)

```bash
cd ~/resq/resQ && nix develop
make help             # See available commands
```

See the repo's `AGENTS.md` for full details (private).

### programs (Solana)

```bash
cd ~/resq/programs && nix develop
anchor build                            # Compile .so artifacts
anchor test                             # Run against local validator
cargo clippy --workspace -- -D warnings # Lint
```

### dotnet-sdk

```bash
cd ~/resq/dotnet-sdk && nix develop
dotnet build -c Release
dotnet test -c Release
dotnet format --verify-no-changes       # Style check
```

### pypi (Python)

```bash
cd ~/resq/pypi && nix develop
uv run resq-mcp                         # Start MCP server (STDIO)
uv run pytest                           # Tests (90% coverage gate)
uv run ruff check .                     # Lint
uv run mypy .                           # Type check (strict)
```

### crates (Rust)

```bash
cd ~/resq/crates && nix develop
cargo build                             # Build all workspace crates
cargo test                              # Run tests
cargo clippy --workspace -- -D warnings # Lint (pedantic)
```

### npm (TypeScript packages)

```bash
cd ~/resq/npm && nix develop
bun build              # Build packages
bun test               # Vitest
bun storybook          # Component browser on :6006
bun lint               # Biome check
```

### vcpkg (C++)

```bash
cd ~/resq/vcpkg && nix develop
cmake --build build            # Build libraries
ctest --test-dir build         # Run tests
clang-format --dry-run src/**  # Style check
```

### landing

```bash
cd ~/resq/landing && nix develop
bun dev                # Dev server on :3000 (Turbopack)
bun build              # Production build
bun test --coverage    # Vitest
bun lint               # Biome check
```

### cms

```bash
cd ~/resq/cms
pnpm install
pnpm dev               # Dev server with Wrangler bindings
pnpm build             # Production build
pnpm test              # Integration + E2E tests
pnpm deploy            # Deploy to Cloudflare Workers
```

### docs

```bash
cd ~/resq/docs
npx mint dev           # Local preview on :3000
# Deployment is automatic via Mintlify GitHub App on push to main
```

---

## AI-assisted development

Every ResQ repo is structured for AI-assisted development. Human developers and AI tools (Claude Code, Cursor, Codex, Gemini, GitHub Copilot) share the same context through a standardized directory layout and canonical guidance files.

### The convention

Inspired by [lobehub/lobehub](https://github.com/lobehub/lobehub), every repo follows this structure:

```
repo/
├── .agents/
│   └── skills/                        # Source of truth for all AI skills
│       ├── <skill-name>/
│       │   └── SKILL.md               # Self-contained skill definition
│       └── ...
│
├── .claude/                           # Claude Code
│   ├── skills → ../.agents/skills     # Symlink — shares skills
│   ├── commands/                      # Slash commands (/command-name)
│   ├── prompts/                       # Reusable prompt templates
│   └── settings.local.json            # Permissions and tool config
│
├── .codex/                            # OpenAI Codex
│   └── skills → ../.agents/skills     # Symlink — shares skills
│
├── .cursor/                           # Cursor IDE
│   ├── rules/                         # Cursor-specific rules
│   └── docs/                          # Reference docs for Cursor indexing
│
├── .gemini/                           # Google Gemini
│
├── .github/
│   ├── agents/                        # GitHub Copilot agent personas
│   ├── commands/                      # Copilot slash commands
│   ├── rules/                         # Copilot coding rules
│   ├── workflows/                     # CI/CD pipelines
│   └── copilot-instructions.md        # Copilot workspace instructions
│
├── .vscode/                           # VS Code workspace settings
│
├── AGENTS.md                          # Canonical dev guide — THE source of truth
└── CLAUDE.md                          # Claude-specific (mirrors or extends AGENTS.md)
```

### Why `.agents/skills/` exists

Without it, the same skill gets copy-pasted into `.claude/skills/`, `.github/skills/`, `.cursor/skills/`, and `.codex/skills/`. They drift. Someone updates one, forgets the others. Now Claude knows about a pattern that Copilot doesn't.

`.agents/skills/` is the single authoring location. Each tool's directory symlinks to it:

```bash
# Every repo sets this up once
ln -s ../.agents/skills .claude/skills
ln -s ../.agents/skills .codex/skills
```

One edit, all tools see it.

### AGENTS.md contract

Every repo's `AGENTS.md` must contain these sections in this order:

```markdown
# <Repo Name> — Agent Guide

## Mission
One paragraph: what this repo does and why it exists.

## Workspace Layout
Directory tree with one-line descriptions of each top-level directory.

## Commands
The 5-8 commands a developer needs daily: build, test, lint, dev, deploy.

## Architecture
Key design decisions: frameworks, patterns, data flow, boundaries.

## Standards
Conventions that apply to this repo: commit format, naming, linting rules,
what's forbidden (e.g., unsafe code, any types, mocks in integration tests).
```

`CLAUDE.md` can extend `AGENTS.md` with Claude-specific additions (tool permissions, slash commands, memory notes) but must not contradict it.

### Writing a skill

Skills live in `.agents/skills/<skill-name>/SKILL.md`. Each skill is a self-contained document that teaches an AI tool how to handle a specific domain or task.

```markdown
# <Skill Name>

## When to use
Describe the trigger: what task or file pattern activates this skill.

## Context
Background knowledge the AI needs before acting.

## Rules
Concrete, testable rules. Not vibes — things you can grep for in a diff.

## Examples
Before/after pairs or code snippets showing correct application.
```

**Repo-specific skills** go in that repo's `.agents/skills/`. For example, a UI library might have `component-authoring/SKILL.md` and `storybook-stories/SKILL.md`, while a Solana repo might have `anchor-accounts/SKILL.md`.

### Keeping things in sync

Every repo with both `AGENTS.md` and `CLAUDE.md` includes an `agent-sync.sh` script:

```bash
./agent-sync.sh --check   # Verify they're in sync (CI runs this)
./agent-sync.sh            # Sync CLAUDE.md from AGENTS.md
```

### Supported tools

| Tool | Config directory | Reads `AGENTS.md`? | Skill source |
|---|---|---|---|
| Claude Code | `.claude/` | Yes (via `CLAUDE.md`) | `.claude/skills → .agents/skills` |
| OpenAI Codex | `.codex/` | Yes | `.codex/skills → .agents/skills` |
| Cursor | `.cursor/` | Yes (via rules) | `.cursor/rules/` |
| Google Gemini | `.gemini/` | Yes | `.gemini/` |
| GitHub Copilot | `.github/` | Yes (via `copilot-instructions.md`) | `.github/agents/`, `.github/rules/` |

---

## Toolchain

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

## Quality gates

Git hooks enforce formatting, linting, secret scanning, and license headers on every commit. Each repo's `AGENTS.md` documents its specific checks.

## License

Apache License 2.0
