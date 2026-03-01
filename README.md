# CARL

**Code Automation and Runtime Layer**

<p><span style="font-size:1.25em;">🚨⚠️</span> <strong><span style="color:#b00020;">WARNING:</span></strong> This repository can enable macOS Remote Login (SSH) during bootstrap and is intended for controlled/private environments, not internet-exposed hardening.</p>

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
- Bootstraps core tooling on first boot (Node, Codex CLI, pnpm, Playwright tooling, `br`, build tools, etc.)
- Bootstraps a fresh macOS arm64 environment with Homebrew + npm-global CLI tooling
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

## macOS Bootstrap (arm64)

This path is intentionally simple: one manual command to bootstrap tooling on a fresh Apple Silicon Mac.
The script can enable macOS Remote Login (SSH sharing) during setup. No SSH hardening, fail2ban, or background management agents are installed in this flow.

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
- Script installs `br` (beads) from GitHub release assets using the pinned rendered version.
- Toolchain verification is required before completion (`brew`, `node`, `npm`, `pnpm`, `codex`, `playwright`, `br`).
- Script prompts for Git `user.name` and `user.email` in an interactive terminal session.
- Script prompts to enable Remote Login (SSH sharing); default is Yes (`[Y/n]`).
- Set `ENABLE_REMOTE_LOGIN_DEFAULT=0` to make the Remote Login prompt default to No (`[y/N]`).
- If Remote Login enablement fails, bootstrap logs a warning and continues; manual fallback is `sudo systemsetup -setremotelogin on`.
- `BOOTSTRAP_SOURCE_REF` is optional and only used for marker metadata.
- Marker file is written to `~/.bootstrap_done` with timestamp + metadata; installs remain idempotent and do not rely on marker state alone.

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

`create-droplet.sh` runtime controls:

- `WAIT_FOR_CLOUD_INIT` (default `1`): wait for remote cloud-init completion over SSH before returning.
- `CLOUD_INIT_WAIT_TIMEOUT_SECONDS` (default `1800`): max wait time when `WAIT_FOR_CLOUD_INIT=1`.
- `CLOUD_INIT_POLL_INTERVAL_SECONDS` (default `10`): polling interval for cloud-init status checks.

## Notes

- Top-level `.env` is the canonical config source for rendering bootstrap artifacts.
- Top-level `.env` is non-secret by policy; keep secret values in untracked `./.secrets/secrets.env`.
- `digitalOcean/create-droplet.sh` writes a rendered cloud-init file to `/tmp` for traceability (Git identity injection only).
- This README intentionally documents both present functionality and future intent.
