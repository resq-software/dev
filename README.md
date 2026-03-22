# ResQ Developer Setup

One command to get started with any ResQ repository.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh | sh
```

Or inspect the script first:

```bash
curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh -o install.sh
less install.sh
sh install.sh
```

## What it does

1. Checks for `git` and installs `gh` (GitHub CLI) if missing
2. Authenticates with GitHub (if not already)
3. Installs [Nix](https://nixos.org) via the [Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer)
4. Lets you choose which repo to clone
5. Drops you into a reproducible dev environment via `nix develop`

## Requirements

- Linux or macOS
- Internet connection

Everything else is installed by the script.

## Repositories

| Repo | Description | Access |
|---|---|---|
| `resQ` | Full platform monorepo | Private (org members) |
| `programs` | Solana/Anchor on-chain programs | Public |
| `dotnet-sdk` | .NET client libraries | Public |
| `mcp` | MCP server for AI clients | Public |
| `cli` | Rust CLI/TUI tools | Public |
| `ui` | React component library | Public |
| `landing` | Marketing site | Public |

## Configuration

Set `RESQ_DIR` to change where repos are cloned (default: `~/resq`):

```bash
RESQ_DIR=/path/to/workspace curl -fsSL https://raw.githubusercontent.com/resq-software/dev/main/install.sh | sh
```

## License

Apache License 2.0
