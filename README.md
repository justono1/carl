# CARL

**Coding Agent Runtime Layer**

<p><span style="font-size:1.25em;">🚨⚠️</span> <strong><span style="color:#b00020;">WARNING:</span></strong> This repository can provision SSH-accessible environments and transfer secrets over SSH. It is intended for controlled/private environments, not internet-exposed hardening.</p>

CARL builds consistent developer environments across cloud and local machines by:

- bootstrapping cloud environments (currently DigitalOcean droplets)
- bootstrapping fresh local environments (currently macOS arm64)
- applying shared agent/tool configs from canonical files in this repo

## Current Status

This repository is in an early phase.
It handles DigitalOcean droplet provisioning, macOS baseline bootstrap, shared Codex/Claude config bootstrapping, and secrets transfer.

## Configuration Model

CARL uses a **domain-driven config layout** with two file types per domain:

1. `env` files: CARL-owned non-secret key/value config used by scripts and rendering.
2. Canonical tool config files: real files copied to target machines (for example `codex/config.toml`, `claude/settings.json`).

Top-level root `.env` is no longer used.

See [docs/config-architecture.md](docs/config-architecture.md) for load model and ownership boundaries.

## Repository Layout

### Lifecycle and scripts

- `digitalOcean/create-droplet.sh`: create and initialize a droplet
- `digitalOcean/destroy-last-droplet.sh`: tear down the droplet recorded in state
- `digitalOcean/push-secrets-to-last-droplet.sh`: push local secrets to the last created droplet
- `scripts/render-bootstrap-artifacts.sh`: renders Linux/macOS bootstrap artifacts from domain config
- `scripts/load-domain-env.sh`: shared loader for domain `env` files
- `scripts/push-secrets.sh`: pushes repo-local secrets to droplets/remote hosts
- `scripts/carl-notify.sh`: shared Slack notifier for Codex/Claude attention events
- `scripts/configure-codex-notify.sh`: installs canonical Codex config + configures notify command
- `scripts/configure-claude-notify.sh`: installs canonical Claude settings + configures hooks

### Rendered bootstrap artifacts

- `linux/cloud-init.yaml.in`: cloud-init template
- `linux/cloud-init.yaml`: rendered cloud-init artifact consumed by droplet provisioning
- `macos/bootstrap-mac.sh.in`: macOS bootstrap template
- `macos/bootstrap-mac.sh`: rendered macOS bootstrap artifact
- `macos/update-checksums.sh`: helper for checksum regeneration/verification
- `macos/bootstrap-mac.sh.sha256`: checksum file for pinned-source bootstrap verification

### Domain config directories

- `runtime/env`: shared runtime settings (`STATE_FILE`)
- `digitalOcean/env`: droplet defaults (`DROPLET_NAME`, `REGION`, `IMAGE`, `SIZE`, `CLOUD_INIT_FILE`)
- `node/env`, `node/.nvmrc`: Node bootstrap version + canonical nvm file
- `npm/env`, `npm/.npmrc`: npm domain env + canonical npmrc
- `pnpm/env`: pnpm pinned version
- `playwright/env`: Playwright pinned versions
- `br/env`: `br` pinned version
- `codex/env`, `codex/config.toml`: Codex CLI version + canonical config
- `claude/env`, `claude/settings.json`, `claude/keybindings.json`, `claude/mcp.json`: Claude installer target + canonical settings/keybindings/mcp config
- `notify/env`: non-secret notifier defaults
- `shell/env`, `shell/core.zsh`: shared shell defaults and canonical Zsh core helpers

### Documentation and CI

- `docs/config-architecture.md`: config system design and ownership
- `docs/adding-a-service.md`: contributor guide for adding new service domains
- `docs/secrets.md`: secrets policy and transfer workflows
- `.github/workflows/checksums.yml`: CI guard for render/checksum drift
- `.github/workflows/secret-scan.yml`: CI secret scanning with gitleaks

## Prerequisites

- DigitalOcean account and `doctl` installed/authenticated
- Local tools: `jq`, `nc`, `sed`, `base64`, `ssh`, `scp`
- SSH key available in DigitalOcean

Authenticate `doctl` first:

```bash
doctl auth init
```

## Quick Start

Run these commands from repository root.

1. Review/edit domain config files if needed:

```bash
${EDITOR:-vi} digitalOcean/env
${EDITOR:-vi} node/env
${EDITOR:-vi} codex/env
${EDITOR:-vi} claude/env
${EDITOR:-vi} pnpm/env
${EDITOR:-vi} playwright/env
${EDITOR:-vi} br/env
${EDITOR:-vi} notify/env
${EDITOR:-vi} shell/env
```

2. Render bootstrap artifacts:

```bash
./scripts/render-bootstrap-artifacts.sh
```

3. Create a droplet:

```bash
./digitalOcean/create-droplet.sh
```

This command waits for cloud-init bootstrap completion by default (set `WAIT_FOR_CLOUD_INIT=0` to skip).

4. (Optional) Push local secrets to the last created droplet:

```bash
./digitalOcean/push-secrets-to-last-droplet.sh
```

5. Destroy the last created droplet:

```bash
./digitalOcean/destroy-last-droplet.sh
```

## Secrets Management (v1)

CARL supports a repo-local secrets source while keeping secret values out of git history.

- Local source of truth on this machine: `./.secrets/secrets.env` (untracked)
- Canonical destination on target machines: `~/.config/carl/secrets.env`
- Required file mode: `0600` for source and destination
- Do not pass secrets via cloud-init user-data

Initialize local source file:

```bash
mkdir -p .secrets
touch .secrets/secrets.env
chmod 600 .secrets/secrets.env
```

Push to an explicit SSH target:

```bash
./scripts/push-secrets.sh --ssh user@host
```

Push to the last created DigitalOcean droplet:

```bash
./scripts/push-secrets.sh --do-state
```

For a GUI-only macOS VM (no SSH), transfer `./.secrets/secrets.env` to `/tmp/carl.secrets.env` and run:

```bash
mkdir -p ~/.config/carl && install -m 600 /tmp/carl.secrets.env ~/.config/carl/secrets.env && rm -f /tmp/carl.secrets.env
```

See [docs/secrets.md](docs/secrets.md) for full workflows and troubleshooting.

## Agent Attention Notifications (Slack)

CARL installs one shared `carl-notify` script and wires:

- Codex `notify` command
- Claude `Notification` and `Stop` hooks

Both invoke the same script, which posts to a Slack Incoming Webhook with source/event/session context and optional message snippet.

### Slack setup

1. In Slack, create or edit an app and enable **Incoming Webhooks**.
2. Create a webhook for your target channel.
3. Add the webhook URL to local `./.secrets/secrets.env`:

```dotenv
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

Push secrets to the target machine:

```bash
./scripts/push-secrets.sh --do-state
# or
./scripts/push-secrets.sh --ssh user@host
```

### Non-secret notifier settings

Edit `notify/env`:

```dotenv
NOTIFY_ENABLED=1
NOTIFY_MIN_INTERVAL_SEC=120
NOTIFY_INCLUDE_SNIPPET=1
```

### Manual test on a target machine

```bash
"$(command -v carl-notify)" codex '{"event":"manual-test","message":"CARL Slack test"}'
```

## macOS Bootstrap (arm64)

CARL standardizes interactive shell UX on Zsh for the bootstrap user while keeping automation scripts on Bash. Shared aliases/functions are installed to `~/.config/carl/zsh/core.zsh` and sourced from `~/.zshrc`.

### Option A: Run from local checkout

```bash
./macos/bootstrap-mac.sh
```

### Option B: One command from pinned source URL (recommended)

Replace placeholders with your repository and immutable commit SHA.

```bash
sudo -v && \
curl -fsSL "https://raw.githubusercontent.com/<owner>/<repo>/<commit-sha>/macos/bootstrap-mac.sh" -o /tmp/bootstrap-mac.sh && \
bash /tmp/bootstrap-mac.sh
```

Optional (only if you want source metadata in marker file):

```bash
BOOTSTRAP_SOURCE_REF="<commit-sha>" bash /tmp/bootstrap-mac.sh
```

## Rendering and Checksums

After editing any domain `env` file, canonical config file, or bootstrap template:

```bash
./scripts/render-bootstrap-artifacts.sh
```

To verify checksum state explicitly:

```bash
./macos/update-checksums.sh --check
```

## Runtime Controls

`create-droplet.sh` runtime controls:

- `WAIT_FOR_CLOUD_INIT` (default `1`): wait for remote cloud-init completion over SSH before returning.
- `CLOUD_INIT_WAIT_TIMEOUT_SECONDS` (default `1800`): max wait time when `WAIT_FOR_CLOUD_INIT=1`.
- `CLOUD_INIT_POLL_INTERVAL_SECONDS` (default `10`): polling interval for cloud-init status checks.

## Adding New Services

To add a new tool/service domain, follow:

- [docs/adding-a-service.md](docs/adding-a-service.md)

This includes naming rules, required files, wiring checklist, and validation checklist.
