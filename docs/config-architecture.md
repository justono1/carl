# CARL Config Architecture

## Purpose

CARL uses a domain-driven configuration model so each tool/service owns its configuration surface in a predictable location.

## Two Config Types

Each domain can contain:

1. `env` (CARL-owned, non-secret key/value config)
2. Canonical tool config files (real file names copied to target machines)

Examples:

- `codex/env` and `codex/config.toml`
- `claude/env`, `claude/settings.json`, `claude/keybindings.json`, and `claude/mcp.json`
- `node/env` and `node/.nvmrc`
- `npm/env` and `npm/.npmrc`

## Ownership Boundaries

- `runtime/`: CARL runtime paths and shared script state.
- `digitalOcean/`: cloud provisioning defaults.
- `node`, `npm`, `pnpm`, `playwright`, `br`: tool/runtime versions and canonical files.
- `codex`, `claude`: agent install versions and canonical configs.
- `notify`: non-secret notification defaults.
- `.secrets/`: local-only secret values (untracked), pushed separately.

## Loading and Precedence

### Shared loader

`scripts/load-domain-env.sh` exposes:

- `carl_load_env_file <path> [required=1]`
- `carl_require_env_keys <KEY ...>`
- `carl_to_repo_root_path <path>`

### Effective behavior

- Scripts source only required domain `env` files.
- Missing required files/keys fail fast.
- Root `.env` is not part of the model.

## Render Pipeline

`./scripts/render-bootstrap-artifacts.sh` is the only renderer for:

- `linux/cloud-init.yaml`
- `macos/bootstrap-mac.sh`

Render inputs:

- domain `env` values (versions/defaults)
- canonical config files (`codex/config.toml`, `claude/settings.json`, `npm/.npmrc`, `node/.nvmrc`)
  plus `claude/keybindings.json` and `claude/mcp.json`

The canonical config files are embedded into rendered artifacts (base64) and installed on target machines during bootstrap.

## Bootstrap Behavior

### Linux cloud-init

- Installs toolchain versions from domain `env` values.
- Writes canonical configs to:
  - `/root/.codex/config.toml`
  - `/root/.claude/settings.json`
  - `/root/.claude/keybindings.json`
  - `/root/.claude/mcp.json`
  - `/root/.npmrc`
  - `/root/.nvmrc`
  - `/workspace/main/.nvmrc`
- Applies notifier wiring for Codex/Claude after baseline files are installed.

### macOS bootstrap

- Installs toolchain versions from rendered values.
- Writes canonical configs to:
  - `~/.codex/config.toml`
  - `~/.claude/settings.json`
  - `~/.claude/keybindings.json`
  - `~/.claude/mcp.json`
  - `~/.npmrc`
  - `~/.nvmrc`
- Applies notifier wiring for Codex/Claude after baseline files are installed.

## Policy

- Domain `env` files are non-secret and committed.
- Tool auth keys and webhooks remain in `./.secrets/secrets.env` only.
- Any config change that affects templates or canonical files must be followed by render + checksum update.
