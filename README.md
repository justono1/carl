# CARL

**Coding Agent Runtime Layer**

<p><span style="font-size:1.25em;">🚨⚠️</span> <strong><span style="color:#b00020;">WARNING:</span></strong> This repository can provision SSH-accessible environments and transfer secrets over SSH. It is intended for controlled/private environments, not internet-exposed hardening.</p>

CARL is a utility for building consistent developer environments across cloud and local machines by:

- bootstrapping cloud environments (currently DigitalOcean droplets)
- bootstrapping fresh local environments (currently macOS arm64)
- moving toward developer-specific configuration sync (dotfiles, aliases, and related preferences)

## Current Status

This repository is in an early phase.  
It already handles DigitalOcean droplet provisioning and macOS baseline bootstrap, but it does **not yet** fully manage local developer config syncing (dotfiles, shell aliases, etc.) end-to-end.

## What CARL Does Today

- Creates a DigitalOcean droplet via `doctl`
- Uses generated bootstrap artifacts rendered from canonical version pins in top-level `.env`
- Bootstraps core tooling on first boot (Node, Codex CLI, Claude Code CLI via native installer, pnpm, Playwright tooling, `br`, `tmux`, build tools, etc.)
- Bootstraps a fresh macOS arm64 environment with Homebrew + npm-global CLI tooling
- Ensures machine-local SSH keys exist for general use (`/root/.ssh/id_ed25519` on droplets, `~/.ssh/id_ed25519` on macOS) without overwriting existing keys
- Installs shared notification wiring so Codex + Claude can send Slack alerts when user input is needed
- Applies basic hardening (SSH settings + fail2ban)
- Saves droplet state to `.do-droplet.json` for lifecycle management
- Destroys the most recently created droplet using saved state

## What CARL Is Meant To Become

The intended direction for this repository includes:

- Brokering local developer config into remote environments
- Managing dotfiles and shell ergonomics (aliases, prompt/profile setup, git defaults, etc.)
- Supporting repeatable developer profiles across droplets
- Keeping cloud dev environments fast to create, easy to tear down, and consistent across runs

## Repository Layout

- `digitalOcean/create-droplet.sh`: create and initialize a droplet
- `digitalOcean/destroy-last-droplet.sh`: tear down the droplet recorded in state
- `digitalOcean/push-secrets-to-last-droplet.sh`: push local secrets to the last created droplet
- `.env`: canonical pinned tool versions + default droplet/runtime settings
- `linux/cloud-init.yaml.in`: cloud-init template
- `linux/cloud-init.yaml`: rendered cloud-init artifact consumed by droplet provisioning
- `macos/bootstrap-mac.sh.in`: macOS bootstrap template
- `macos/bootstrap-mac.sh`: rendered macOS bootstrap artifact
- `scripts/render-bootstrap-artifacts.sh`: renders Linux/macOS artifacts from top-level `.env`
- `scripts/push-secrets.sh`: pushes repo-local secrets to droplets/remote hosts
- `scripts/carl-notify.sh`: shared Slack notifier for Codex/Claude attention events
- `scripts/configure-codex-notify.sh`: idempotently configures Codex notify command
- `scripts/configure-claude-notify.sh`: idempotently configures Claude `Notification` + `Stop` hooks
- `macos/update-checksums.sh`: helper for regenerating/verifying checksum files
- `macos/bootstrap-mac.sh.sha256`: checksum file for pinned-source bootstrap verification
- `docs/secrets.md`: secrets policy and transfer workflows
- `.github/workflows/checksums.yml`: CI guard for checksum drift
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

Run these commands from the repository root.

1. Review/edit top-level `.env` if needed:

```bash
${EDITOR:-vi} .env
```

2. Create a droplet:

```bash
./digitalOcean/create-droplet.sh
```

This command waits for cloud-init bootstrap completion by default (set `WAIT_FOR_CLOUD_INIT=0` to skip).

3. (Optional) Push local secrets to the last created droplet:

```bash
./digitalOcean/push-secrets-to-last-droplet.sh
```

4. Destroy the last created droplet:

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

See [docs/secrets.md](docs/secrets.md) for full workflows, macOS VM guidance, and troubleshooting.

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

### Non-secret notifier settings (top-level `.env`)

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

This path is intentionally simple: one manual command to bootstrap tooling on a fresh Apple Silicon Mac.
The script does not enable macOS Remote Login (SSH sharing). If you need inbound SSH access (for example, to use `push-secrets.sh --ssh`), enable it manually in System Settings. No SSH hardening, fail2ban, or background management agents are installed in this flow.

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

Optional (only if you want source metadata in the marker file):

```bash
BOOTSTRAP_SOURCE_REF="<commit-sha>" bash /tmp/bootstrap-mac.sh
```

### macOS Bootstrap Notes

- Script enforces `Darwin` + `arm64`.
- Script installs Xcode Command Line Tools and Homebrew if needed.
- The recommended command downloads the script to `/tmp` and executes it (instead of `curl | bash`) so interactive install prompts behave correctly.
- Homebrew package list is embedded in the script (single fixed profile; no alternate Brewfile path).
- Claude Code is installed via the official native installer (`claude.ai/install.sh`); npm install is deprecated upstream.
- Script ensures `~/.local/bin` is on PATH for current and future zsh/bash sessions.
- Script installs `br` (beads) from GitHub release assets using the pinned rendered version.
- Toolchain verification is required before completion (`brew`, `node`, `npm`, `tmux`, `pnpm`, `codex`, `claude`, `playwright`, `br`).
- Script prompts for Git `user.name` and `user.email` in an interactive terminal session.
- Script ensures `~/.ssh/id_ed25519` exists for the current user (creates it only when missing).
- SSH key generation and SSH access are different concerns: generating `~/.ssh/id_ed25519` does not enable inbound SSH access to the Mac.
- If you need inbound SSH access, enable Remote Login manually in macOS UI.
- `BOOTSTRAP_SOURCE_REF` is optional and only used for marker metadata.
- Marker file is written to `~/.bootstrap_done` with timestamp + metadata; installs remain idempotent and do not rely on marker state alone.

### Manual Remote Login (SSH) Setup on macOS

Enable SSH server access in macOS UI:

1. Open **System Settings**.
2. Go to **General > Sharing**.
3. Turn on **Remote Login**.
4. Choose which users are allowed to connect.

Verify SSH is enabled from Terminal:

```bash
sudo systemsetup -getremotelogin
nc -vz localhost 22
```

Find the Mac IP address to connect to:

```bash
ipconfig getifaddr en0
ipconfig getifaddr en1
ifconfig | grep "inet " | grep -v 127.0.0.1
```

Use that address with CARL secrets push:

```bash
./scripts/push-secrets.sh --ssh <mac-user>@<ip-address>
```

### SSH Public Key Output

Existing SSH private keys are preserved. To copy public keys for GitHub or other services:

```bash
# On a droplet:
cat /root/.ssh/id_ed25519.pub

# On macOS:
cat ~/.ssh/id_ed25519.pub
```

### Artifact Rendering

After editing `.env`, `linux/cloud-init.yaml.in`, or `macos/bootstrap-mac.sh.in`, render artifacts and refresh checksum:

```bash
./scripts/render-bootstrap-artifacts.sh
```

`digitalOcean/create-droplet.sh` expects `linux/cloud-init.yaml` to be rendered already and will fail if non-Git placeholders remain.
It also requires an interactive terminal to collect Git `user.name` and `user.email` before provisioning.

To verify current files match committed checksum:

```bash
./macos/update-checksums.sh --check
```

## Configuration

Top-level `.env` controls:

- droplet settings (`DROPLET_NAME`, `REGION`, `IMAGE`, `SIZE`)
- state file and SSH key selection (`STATE_FILE`, `SSH_KEY_ID`, `SSH_KEY_NAME_MATCH`)

Bootstrap/tool versions are pinned in top-level `.env` and compiled into rendered artifacts.

Pinned bootstrap tool variables include:

- `NODE_MAJOR`
- `CODEX_VERSION`
- `CLAUDE_CODE_VERSION`
- `BR_VERSION`
- `PNPM_VERSION`
- `PLAYWRIGHT_MCP_VERSION`
- `PLAYWRIGHT_VERSION`
- `NOTIFY_ENABLED`
- `NOTIFY_MIN_INTERVAL_SEC`
- `NOTIFY_INCLUDE_SNIPPET`

`CLAUDE_CODE_VERSION` accepts a Claude installer target (`stable` or a specific version string).

`create-droplet.sh` runtime controls:

- `WAIT_FOR_CLOUD_INIT` (default `1`): wait for remote cloud-init completion over SSH before returning.
- `CLOUD_INIT_WAIT_TIMEOUT_SECONDS` (default `1800`): max wait time when `WAIT_FOR_CLOUD_INIT=1`.
- `CLOUD_INIT_POLL_INTERVAL_SECONDS` (default `10`): polling interval for cloud-init status checks.

## Notes

- Top-level `.env` is the canonical config source for rendering bootstrap artifacts.
- Top-level `.env` is non-secret by policy; keep secret values in untracked `./.secrets/secrets.env`.
- `digitalOcean/create-droplet.sh` writes a rendered cloud-init file to `/tmp` for traceability (Git identity injection only).
- This README intentionally documents both present functionality and future intent.
