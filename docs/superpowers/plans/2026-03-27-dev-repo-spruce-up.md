# Dev Repo Spruce-Up Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite both installer scripts with best practices (modular functions, bash re-exec, structured logging, version checks, updated repo list) and add missing project files (AGENTS.md, CLAUDE.md).

**Architecture:** Single-file modular rewrite of install.sh and install.ps1. Scripts stay self-contained for curl-pipe UX. POSIX shebang with bash re-exec for enhanced error handling. All logging to stderr.

**Tech Stack:** POSIX sh, bash, PowerShell 5.1+, shellcheck

**Spec:** `docs/superpowers/specs/2026-03-27-dev-repo-spruce-up-design.md`

---

## Chunk 1: install.sh

### Task 1: Rewrite install.sh

**Files:**
- Rewrite: `install.sh`

- [ ] **Step 1: Write the complete install.sh**

Write the full script to `install.sh`. The script structure:

1. POSIX shebang + license header
2. Bash re-exec block (guard with `_RESQ_REEXEC`, exec bash if available)
3. Strict mode (`set -euo pipefail` under bash, `set -eu` under sh)
4. Constants: `SCRIPT_VERSION="0.2.0"`, ANSI colors, `NIX_INSTALL_URL`, `ORG`
5. Utility functions (all log to stderr):
   - `info()`, `ok()`, `warn()`, `fail()` — color-coded logging to stderr
   - `has()` — command existence check
   - `version_gte()` — compare two dotted version strings, returns 0 if $1 >= $2. Split on `.`, compare each segment numerically. POSIX-compatible (no arrays — use positional params via `IFS='.'`).
   - `require_version()` — args: `tool_name actual_version min_version url`. Calls `version_gte`, warns if too old with upgrade URL. Does NOT fail.
   - `confirm()` — prompt `[y/N]`, returns 0/1. Bypassed if `YES=1`.
6. Step functions:
   - `detect_platform()` — sets `OS` and `ARCH` from `uname`. Rejects unsupported OS.
   - `check_git()` — verifies git exists, prints version, calls `require_version "git" "$ver" "2.0" "https://git-scm.com/downloads"`
   - `install_gh()` — installs gh if missing (apt/dnf/pacman/brew). After install, calls `require_version "gh" "$ver" "2.0" "https://cli.github.com"`.
   - `authenticate_gh()` — checks `gh auth status`, runs `gh auth login` if needed
   - `install_nix()` — `confirm` before install. Runs Determinate Systems installer. Sources nix profile. Verifies nix in PATH.
   - `choose_repo()` — prints menu (10 repos), reads choice, sets `REPO`
   - `clone_repo()` — sets `TARGET_DIR`. If exists, `confirm` then pull. Else clone via `gh repo clone`.
   - `post_clone_setup()` — runs `nix develop` if flake.nix exists, runs setup-hooks.sh if present
   - `print_repo_info()` — repo-specific "what's included" blocks. Updated names: pypi (was mcp), crates (was cli), npm (was ui). New blocks for vcpkg, cms, docs.
7. `main()` — banner with version, then calls each step function in order.

The 10-repo menu:

```
  1  resQ          Platform monorepo (private)
  2  programs      Solana/Anchor on-chain programs
  3  dotnet-sdk    .NET client libraries
  4  pypi          Python packages (MCP + DSA)
  5  crates        Rust workspace (CLI + DSA)
  6  npm           TypeScript packages (UI + DSA)
  7  vcpkg         C++ libraries
  8  landing       Marketing site
  9  cms           Content management
 10  docs          Documentation site
```

"What's included" blocks:
- **resQ**: unchanged (toolchain, quality gates, security workflows, dev tools)
- **programs**: unchanged (Solana CLI, Anchor, Rust)
- **pypi** (was mcp): `Python 3.11-3.13, uv, ruff, mypy. Packages: resq-mcp, resq-dsa. 90% coverage gate.`
- **crates** (was cli): `Rust toolchain, clippy, cargo-deny. Workspace: 9+ crates including CLI tools and resq-dsa.`
- **npm** (was ui): `Bun, TypeScript, React 19, Storybook, Chromatic. Packages: @resq-sw/ui (55+ components), @resq-sw/dsa. Biome linter.`
- **vcpkg**: `C++ toolchain, CMake, clang-format. Header-only library: resq-common.`
- **cms**: `TypeScript, pnpm, Wrangler. Deploys to Cloudflare Workers.`
- **docs**: `Mintlify docs site. npx mint dev for local preview.`
- **landing**, **dotnet-sdk**: generic (just cd + nix develop + make help)

- [ ] **Step 2: Lint with shellcheck**

Run: `shellcheck install.sh`
Expected: No errors. Warnings about ANSI escape codes in printf are acceptable (SC2059).

- [ ] **Step 3: Verify shebang and re-exec**

Run: `head -20 install.sh`
Expected: `#!/bin/sh` on line 1, re-exec block within first 15 lines.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(install.sh): modular rewrite with bash re-exec, structured logging, version checks

- Bash re-exec for pipefail when available, falls back to POSIX sh
- All logging to stderr (curl-pipe safe)
- Version checks for git >= 2.0 and gh >= 2.0
- confirm() prompts before Nix install and existing dir operations
- Repo menu expanded to 10 repos with new names (pypi, crates, npm, vcpkg, cms, docs)
- Updated 'what's included' blocks for renamed repos"
```

---

## Chunk 2: install.ps1

### Task 2: Rewrite install.ps1

**Files:**
- Rewrite: `install.ps1`

- [ ] **Step 1: Write the complete install.ps1**

Full parity rewrite. Structure mirrors install.sh:

1. License header + `#Requires -Version 5.1` + `Set-StrictMode` + `$ErrorActionPreference = 'Stop'`
2. Constants: `$ScriptVersion = '0.2.0'`, `$Org`, `$NixInstallUrl`
3. Platform detection: compute `$IsNativeWindows` once at top:
   ```powershell
   $IsNativeWindows = $IsWindows -or (-not $IsLinux -and -not $IsMacOS -and
       [System.Environment]::OSVersion.Platform -eq 'Win32NT')
   ```
4. Utility functions:
   - `Write-Info`, `Write-Ok`, `Write-Warn` — `Write-Host` with color
   - `Write-Fail` — `Write-Host` red + `exit 1`
   - `Test-Command` — `Get-Command` with `-ErrorAction SilentlyContinue`
   - `Test-MinVersion` — params `$Tool`, `$Actual`, `$Minimum`, `$Url`. Splits on `.`, compares segments. Warns if too old.
   - `Confirm-Action` — params `$Message`. Returns `$true/$false`. Bypassed if `$env:YES -eq '1'`.
5. Step functions (same logic as .sh, PS idioms):
   - `Get-Platform` — sets script-scope `$Platform`, `$Arch`, `$IsWSL`. WSL detection: `Test-Path /proc/version` then `Select-String 'microsoft|WSL'`.
   - `Assert-Git` — check/install (winget on Windows), version check
   - `Install-GitHubCLI` — check/install (winget/brew/apt/dnf/pacman), version check
   - `Connect-GitHub` — `gh auth status` in try/catch, `gh auth login` if needed
   - `Install-Nix` — `Confirm-Action` before install. Skip on native Windows with info message. Sources nix profile.
   - `Select-Repo` — same 10-repo menu, `Read-Host`, switch statement
   - `Clone-Repo` — `$BaseDir` from `$env:RESQ_DIR` or `~/resq`. Confirm if exists.
   - `Initialize-Repo` — nix develop + hooks
   - `Show-RepoInfo` — same blocks as .sh
6. `Main` — banner with version, calls each step

- [ ] **Step 2: Verify syntax**

Run: `pwsh -NoProfile -Command "& { \$null = [System.Management.Automation.Language.Parser]::ParseFile('$(pwd)/install.ps1', [ref]\$null, [ref]\$errors); \$errors }"`
Expected: No parse errors. (If pwsh not available, skip — syntax is validated by reading the script.)

- [ ] **Step 3: Commit**

```bash
git add install.ps1
git commit -m "feat(install.ps1): full parity rewrite matching install.sh improvements

- Platform detection cleaned up ($IsNativeWindows extracted once)
- Test-MinVersion for git/gh version checks
- Confirm-Action prompts before Nix install and existing dir operations
- Proper try/catch around gh auth
- Same 10-repo menu with new names
- Updated 'what's included' blocks"
```

---

## Chunk 3: Project Files

### Task 3: Create AGENTS.md

**Files:**
- Create: `AGENTS.md`

- [ ] **Step 1: Write AGENTS.md**

Content matches spec section 4 verbatim (the full markdown block). Follows the contract format documented in the README.

Success criterion: file contains all 5 sections (Mission, Workspace Layout, Commands, Architecture, Standards) with content matching the spec.

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs: add AGENTS.md following the contract format"
```

### Task 4: Create CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write CLAUDE.md**

Content matches spec section 5 verbatim. References AGENTS.md, adds Claude-specific tool permissions and working conventions.

Success criterion: file contains Tool permissions and Working conventions sections matching the spec.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md with Claude-specific extensions"
```

### Task 5: Update CODEOWNERS

**Files:**
- Modify: `CODEOWNERS`

- [ ] **Step 1: Add install.ps1 line**

Add `install.ps1 @WomB0ComB0` as a new line after `install.sh @WomB0ComB0`.

- [ ] **Step 2: Commit**

```bash
git add CODEOWNERS
git commit -m "chore: add install.ps1 to CODEOWNERS"
```

### Task 6: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update repo table**

Find the markdown table starting with `| Repo | What | Languages |` and replace entries:
- `mcp` → `pypi` with description "Python packages (MCP + DSA)"
- `cli` → `crates` with description "Rust workspace (CLI + DSA)"
- `ui` → `npm` with description "TypeScript packages (UI + DSA)"
- Add `vcpkg` row: C++ libraries, C++
- Fix `docs` link: `resq-sw/docs` → `resq-software/docs`

- [ ] **Step 2: Update quick start sections**

Find each `###` header and update:
- `### mcp (Python)` → `### pypi (Python)`, path `~/resq/mcp` → `~/resq/pypi`
- `### cli (Rust)` → `### crates (Rust)`, path `~/resq/cli` → `~/resq/crates`
- `### ui (React components)` → `### npm (TypeScript packages)`, path `~/resq/ui` → `~/resq/npm`
- Add `### vcpkg (C++)` section after npm:
  ```bash
  cd ~/resq/vcpkg && nix develop
  cmake --build build            # Build libraries
  ctest --test-dir build         # Run tests
  clang-format --dry-run src/**  # Style check
  ```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(README): update repo names and add vcpkg quick start

Reflects renames: cli→crates, mcp→pypi, ui→npm. Adds vcpkg.
Fixes docs org slug."
```

### Task 7: Final verification

- [ ] **Step 1: Verify all files exist and are consistent**

Run: `ls -la install.sh install.ps1 AGENTS.md CLAUDE.md CODEOWNERS README.md`
Expected: All 6 files present.

Run: `grep -c 'pypi\|crates\|npm\|vcpkg' install.sh install.ps1 README.md`
Expected: Each file references the new repo names.

Run: `shellcheck install.sh`
Expected: Clean (or only SC2059 printf format warnings).

- [ ] **Step 2: Verify repo count consistency**

Run: `grep -c '^\s*[0-9]\+)' install.sh`
Expected: 10 (menu choices 1-10)

Run: `grep -c "^        '[0-9]\+'" install.ps1`
Expected: 10 (switch cases)

Run: `grep -c '| \[' README.md`
Expected: 12 (10 menu repos + resq-proto + dev)
