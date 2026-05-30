# CARL

**Coding Agent Runtime Layer** — macOS edition.

CARL is a single-machine bootstrap and update tool. It produces a reproducible developer environment on Apple Silicon Macs for running AI coding agents (Codex CLI and Claude Code) alongside a normal terminal/Node/VS Code workflow. Everything is pinned in version-controlled files in this repo; the same script handles initial setup and subsequent updates.

## What it does

Running `./bootstrap.sh` from a checkout of this repo will, idempotently:

1. Verify you're on macOS arm64.
2. Load and validate version pins from `<domain>/env` files (no `latest` allowed).
3. Prompt for Git identity (skipped on re-runs if already configured).
4. Install Xcode Command Line Tools, Homebrew, and the embedded Brewfile.
5. Install canonical configs into `~/.codex`, `~/.claude`, `~/.npmrc`, `~/.nvmrc`, and `~/.config/carl/zsh/core.zsh`.
6. Wire `~/.zshrc` to source `core.zsh` (idempotent, marker-bounded).
7. Set `zsh` as the default shell.
8. Install pinned npm globals: Codex CLI, Playwright, `@playwright/mcp`.
9. Install Claude Code via the native installer and link it onto PATH.
10. Install `br` and `bv` (beads) from GitHub releases, with a `bd → br` shim.
11. Install Playwright browsers (default: Chromium).
12. Verify everything is on PATH and write `~/.bootstrap_done` with a versions snapshot.

## Quick start

```bash
git clone <this repo> && cd CARL
./bootstrap.sh
```

That's it. After it finishes, open a new terminal (or `hash -r`) so the new PATH takes effect.

## Updating

Edit a version in the relevant `<domain>/env` file, commit it, then on the target Mac:

```bash
git pull
./bootstrap.sh
```

The script detects already-satisfied installs and only does the work needed for whatever changed.

## Repository layout

```
.
├── bootstrap.sh           single idempotent install/update script
├── br/env                 BR_VERSION
├── bv/env                 BV_VERSION
├── claude/
│   ├── env                CLAUDE_CODE_VERSION (or 'stable')
│   ├── settings.json      canonical Claude Code settings
│   ├── keybindings.json   canonical Claude Code keybindings
│   └── mcp.json           canonical Claude Code MCP servers
├── codex/
│   ├── env                CODEX_VERSION
│   └── config.toml        canonical Codex CLI config
├── node/
│   ├── env                NODE_MAJOR
│   └── .nvmrc             canonical project default
├── npm/
│   ├── env                (placeholder)
│   └── .npmrc             canonical npm settings
├── playwright/env         PLAYWRIGHT_VERSION + PLAYWRIGHT_MCP_VERSION
├── shell/
│   ├── env                (placeholder)
│   └── core.zsh           shared zsh aliases/functions
└── docs/
    ├── config-architecture.md
    └── adding-a-service.md
```

Every tool/service has its own directory containing a non-secret `env` file (with version pins or settings) and any canonical config files copied verbatim into `~/` during bootstrap. See [docs/config-architecture.md](docs/config-architecture.md).

## Adding or updating a tool

See [docs/adding-a-service.md](docs/adding-a-service.md).

## Version pinning

Every version in a domain `env` file must be an exact pin. The script rejects both `latest` and `stable` for every version variable. The Claude Code installer itself accepts `stable`/`latest`, but CARL forbids them so the machine is always reproducible from the repo.

The `@playwright/mcp` version is single-sourced from `playwright/env`. At install time, `bootstrap.sh` rewrites the `@playwright/mcp@<v>` suffix inside the installed `~/.codex/config.toml` and `~/.claude/mcp.json` to match `PLAYWRIGHT_MCP_VERSION`. The committed copies of those files are kept in sync as a convenience, but the env file is authoritative.

## Marker file

`~/.bootstrap_done` records the script version, source git ref, Brewfile hash, and every pinned version installed. Useful for inspecting "what did this machine actually get."

## Automated version updates

This repo is set up so [Renovate](https://docs.renovatebot.com/) keeps the version pins current.

- `renovate.json` defines custom regex managers that map each `<TOOL>_VERSION` env variable to its upstream source (npm or GitHub releases).
- `.github/workflows/validate.yml` runs `bootstrap.sh --validate` on every push/PR to verify pins are exact versions and JSON configs parse.
- `packageRules` in `renovate.json` auto-merge patch and minor bumps when CI passes; major bumps stay manual and get labeled `major-bump`.

To activate it on a fresh fork:

1. Install the [Renovate GitHub App](https://github.com/apps/renovate) on the repo.
2. In **Settings → General**, enable "Allow auto-merge".
3. In **Settings → Branches**, add a branch protection rule for `main` that requires the `validate` status check. Without this, auto-merge has nothing to wait for.

Renovate will open a "Configure Renovate" onboarding PR first, then start opening dependency PRs on the schedule (`before 6am on monday`, by default — change in `renovate.json`).

## Local validation

```bash
./bootstrap.sh --validate
```

Runs the same checks CI does. Useful before pushing changes to env files or JSON configs.
