# CARL Config Architecture

## Premise

CARL targets a single use case: bootstrapping and updating one Apple Silicon Mac so it runs AI coding agents and a normal developer toolchain identically each time. Configuration is domain-driven — every tool gets its own directory — and `bootstrap.sh` reads those directories directly. There is no template language, no render step, and no remote state.

## Domain directories

Each tool/service in CARL has a top-level directory containing one or both of:

1. An `env` file with CARL-managed non-secret key/value pairs (version pins, flags).
2. Canonical tool config files using their real names (`config.toml`, `settings.json`, `.npmrc`, `.nvmrc`, `core.zsh`).

Current domains:

- `node/` — `NODE_MAJOR` + `.nvmrc`
- `npm/` — `.npmrc`
- `playwright/` — `PLAYWRIGHT_VERSION`, `PLAYWRIGHT_MCP_VERSION`
- `codex/` — `CODEX_VERSION` + `config.toml`
- `claude/` — `CLAUDE_CODE_VERSION` + `settings.json` + `keybindings.json` + `mcp.json`
- `br/` — `BR_VERSION`
- `bv/` — `BV_VERSION`
- `shell/` — `core.zsh` (zsh aliases/functions sourced from `~/.zshrc`)

## Loading and validation

`bootstrap.sh` sources every domain `env` file at startup with `set -a; source <file>; set +a`, then validates required version pins. Both `latest` and `stable` are rejected for every version variable, so the bootstrap output is always reproducible from the repo state.

## Install model

Canonical config files are installed directly from the checkout into their target locations using `install -m 0644`. JSON files are validated with `jq -e` after install.

| Source                         | Destination                                  |
| ------------------------------ | -------------------------------------------- |
| `codex/config.toml`            | `~/.codex/config.toml`                       |
| `claude/settings.json`         | `~/.claude/settings.json`                    |
| `claude/keybindings.json`      | `~/.claude/keybindings.json`                 |
| `claude/mcp.json`              | `~/.claude/mcp.json`                         |
| `npm/.npmrc`                   | `~/.npmrc`                                   |
| `node/.nvmrc`                  | `~/.nvmrc`                                   |
| `shell/core.zsh`               | `~/.config/carl/zsh/core.zsh`                |

`~/.zshrc` is patched with a marker-bounded block (`# >>> CARL ZSH CORE >>>` ... `# <<< CARL ZSH CORE <<<`) that sources `core.zsh`. Personal overrides go after the block.

After install, `bootstrap.sh` rewrites the `@playwright/mcp@<version>` suffix inside `~/.codex/config.toml` and `~/.claude/mcp.json` to match `PLAYWRIGHT_MCP_VERSION`. This makes `playwright/env` the single source of truth for the MCP version even though the same string appears inside the canonical configs.

## Idempotency

Every step in `bootstrap.sh` is safe to re-run:

- Homebrew uses `brew bundle check` before `brew bundle install`.
- npm globals check installed version before `npm install -g`.
- `br`/`bv` parse `--version` and skip if it matches `BR_VERSION`/`BV_VERSION`.
- Claude Code is skipped if `claude --version` already matches `CLAUDE_CODE_VERSION` (or if the target is `stable`/`latest`).
- The zshrc block is awk-rewritten in place; no duplicates.
- Config installs always overwrite to a known-good state.

## Policy

- Domain `env` files are non-secret and committed.
- Any secrets you need belong in `~/.config/carl/secrets.env` on the target machine (CARL does not manage them).
- Changing a version pin or canonical config: edit the file, commit, run `./bootstrap.sh`.
