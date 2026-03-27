# CLAUDE.md

See AGENTS.md for the canonical guide. This file adds Claude-specific context.

## Tool permissions

- Shell commands: sh, bash, pwsh, shellcheck, git, gh
- No destructive operations without confirmation

## Working conventions

- This repo is two scripts — prefer editing over creating new files
- Test changes by running install.sh in a clean environment
- The install scripts are curl-piped, so stdout must stay clean (log to stderr)
