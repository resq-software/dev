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

## What happens

1. Installs `gh` (GitHub CLI) if missing
2. Authenticates with GitHub
3. Installs [Nix](https://nixos.org) via the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer) for reproducible toolchains
4. Lets you choose which repo to clone
5. Configures git hooks and dev environment automatically

## What you get

### Toolchain (via Nix flake)

Everything is pinned and reproducible. No "works on my machine" issues.

| Language | Tools |
|---|---|
| Rust | `rustc`, `cargo`, `clippy`, `rustfmt`, `cargo-deny` |
| TypeScript | `bun`, `node`, `turbo` |
| Python | `python 3.12`, `uv`, `ruff`, `mypy` |
| C# | `dotnet 9` |
| C++ | `gcc`, `cmake`, `clang-format` |
| Protobuf | `buf`, `protoc` |
| Solana | `solana-cli`, `anchor` |

### Quality gates (automatic on every commit)

The `resq` CLI runs a TUI-based pre-commit check:

- Copyright headers on all source files
- Large file detection (>10 MiB)
- Debug statement scanning
- Secret scanning (API keys, tokens, credentials)
- Security audit (OSV + npm audit-ci)
- Auto-formatting: Rust (`rustfmt`), TS (`biome`), Python (`ruff`), C++ (`clang-format`), C# (`dotnet format`)

### Security workflows (CI)

| Workflow | Schedule | Engine |
|---|---|---|
| OSV vulnerability scan | On dependency changes | GitHub Actions |
| Dependency review | On PRs | GitHub Actions |
| Secrets analysis | Daily | Copilot (gh-aw) |
| Security compliance audit | Weekly | Copilot (gh-aw) |
| AI code auditor | On PRs | Copilot (gh-aw) |
| Breaking change checker | On PRs | Copilot (gh-aw) |

### Developer tools (resq CLI)

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

## Repositories

| Repo | What | Access | Languages |
|---|---|---|---|
| [`resQ`](https://github.com/resq-software/resQ) | Full platform monorepo | Private | Rust, TS, Python, C#, C++ |
| [`programs`](https://github.com/resq-software/programs) | Solana/Anchor on-chain programs | Public | Rust |
| [`dotnet-sdk`](https://github.com/resq-software/dotnet-sdk) | .NET client libraries | Public | C# |
| [`mcp`](https://github.com/resq-software/mcp) | MCP server for AI clients | Public | Python |
| [`cli`](https://github.com/resq-software/cli) | Rust CLI/TUI tools | Public | Rust |
| [`ui`](https://github.com/resq-software/ui) | React component library | Public | TypeScript |
| [`landing`](https://github.com/resq-software/landing) | Marketing site | Public | TypeScript |

Public repos sync automatically to the monorepo. Changes flow: satellite repo → monorepo main.

## Configuration

```bash
# Change clone directory (default: ~/resq)
RESQ_DIR=/path/to/workspace curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh | sh
```

## Inspect first

```bash
curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh -o install.sh
less install.sh
sh install.sh
```

## License

Apache License 2.0
