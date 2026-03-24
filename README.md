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

### Platform

| Repo | What | Languages | Deploy |
|---|---|---|---|
| [`resQ`](https://github.com/resq-software/resQ) | Full platform monorepo — 7 services, 8 libs, 9 tools | Rust, TS, Python, C#, C++ | Docker / K8s |
| [`programs`](https://github.com/resq-software/programs) | Solana on-chain — airspace management, delivery proof | Rust (Anchor) | Solana devnet |
| [`resq-proto`](https://github.com/resq-software/resq-proto) | Canonical Protobuf definitions (6 .proto files) | Protobuf | Buf BSR |
| [`dotnet-sdk`](https://github.com/resq-software/dotnet-sdk) | .NET 9 client libraries — Core, Clients, Blockchain, Storage, Simulation | C# | NuGet |
| [`mcp`](https://github.com/resq-software/mcp) | FastMCP server connecting AI agents to ResQ | Python | PyPI / GHCR |
| [`cli`](https://github.com/resq-software/cli) | Rust CLI/TUI toolchain — 9 crates | Rust | crates.io |

### Frontend

| Repo | What | Languages | Deploy |
|---|---|---|---|
| [`ui`](https://github.com/resq-software/ui) | 56-component React design system (shadcn + Radix + Tailwind v4) | TypeScript | npm (`@resq-sw/ui`) |
| [`landing`](https://github.com/resq-software/landing) | Marketing site — i18n (5 languages), PWA | TypeScript (Next.js 15) | Cloudflare Pages |
| [`cms`](https://github.com/resq-software/cms) | Content management — posts, media, contacts | TypeScript (Payload CMS) | Cloudflare Workers |
| [`docs`](https://github.com/resq-sw/docs) | Documentation site — guides + API reference | MDX (Mintlify) | Mintlify |

### Infrastructure

| Repo | What |
|---|---|
| [`dev`](https://github.com/resq-software/dev) | This repo — install scripts, onboarding, org-wide conventions |

### How repos connect

```
resq-proto (source of truth)
  ├─ publish ──► Buf Schema Registry (private)
  ├─ auto-sync ► resQ/libs/protocols/
  └─ auto-sync ► dotnet-sdk/protos/

satellite repos (cli, ui, mcp, programs, dotnet-sdk, landing)
  └─ sync-to-mono ► resQ monorepo main

ui (@resq-sw/ui on npm)
  ├─ consumed by ► landing
  └─ consumed by ► resQ/services/web-dashboard
```

---

## Quick start per repo

Every repo uses Nix flakes for its dev environment. The pattern is always `cd <repo> && nix develop`, then use the commands from that repo's `AGENTS.md`.

### resQ (monorepo)

```bash
cd ~/resq/resQ && nix develop
make install          # Install all dependencies
make dev              # Start full stack (all services)
make test             # Run ~140+ tests across all languages
make build            # Build everything
make codegen          # Regenerate Protobuf bindings
```

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

### mcp (Python)

```bash
cd ~/resq/mcp && nix develop
uv run resq-mcp                         # Start server (STDIO)
uv run pytest                           # Tests (90% coverage gate)
uv run ruff check .                     # Lint
uv run mypy .                           # Type check (strict)
```

### cli (Rust)

```bash
cd ~/resq/cli && nix develop
cargo build                             # Build all 9 crates
cargo test                              # Run tests
cargo clippy --workspace -- -D warnings # Lint (pedantic)
```

### ui (React components)

```bash
cd ~/resq/ui && nix develop
bun build              # Build src/ → lib/
bun test               # Vitest
bun storybook          # Component browser on :6006
bun lint               # Biome check
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

**Repo-specific skills** go in that repo's `.agents/skills/`:

```
mcp/.agents/skills/
├── fastmcp-tools/SKILL.md       # How to write MCP tool handlers
├── pydantic-models/SKILL.md     # Model conventions for this project
└── testing-strategy/SKILL.md    # 90% coverage, hypothesis testing, no mocks

programs/.agents/skills/
├── anchor-accounts/SKILL.md     # PDA patterns, account validation
└── solana-testing/SKILL.md      # Local validator, integration test setup

ui/.agents/skills/
├── component-authoring/SKILL.md # shadcn patterns, cva variants, data-slot
└── storybook-stories/SKILL.md   # Story format, a11y, perf panels
```

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

The `resq` CLI runs a TUI-based pre-commit check on every commit:

- Copyright headers on all source files
- Large file detection (>10 MiB)
- Debug statement scanning
- Secret scanning (API keys, tokens, credentials)
- Security audit (OSV + npm audit-ci)
- Auto-formatting: Rust (`rustfmt`), TS (`biome`), Python (`ruff`), C++ (`clang-format`), C# (`dotnet format`)

## CI security workflows

| Workflow | Schedule | Engine |
|---|---|---|
| OSV vulnerability scan | On dependency changes | GitHub Actions |
| Dependency review | On PRs | GitHub Actions |
| Secrets analysis | Daily | Copilot (gh-aw) |
| Security compliance audit | Weekly | Copilot (gh-aw) |
| AI code auditor | On PRs | Copilot (gh-aw) |
| Breaking change checker | On PRs | Copilot (gh-aw) |

## Developer tools (resq CLI)

```
resq audit          Run security audits
resq clean          Clean build artifacts
resq deploy         Deploy services
resq dev kill-ports Free up bound ports
resq dev sync-env   Sync environment variables
resq dev upgrade    Upgrade dependencies
resq explore        Performance profiler / binary explorer
resq health         Service health checker
resq logs           Log viewer / aggregator
resq pre-commit     Run all pre-commit checks
```

## License

Apache License 2.0
