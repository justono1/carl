# CARL

**Code Automation and Runtime Layer**

CARL is intended to broker the relationship between a developer and a cloud droplet by:

- standing up a consistent remote development environment
- applying developer-specific configuration to that machine (dotfiles, aliases, common quality-of-life setup, and related preferences)

## Current Status

This repository is in an early phase.  
It already handles droplet provisioning and baseline machine bootstrap, but it does **not yet** fully manage local developer config syncing (dotfiles, shell aliases, etc.) end-to-end.

## What CARL Does Today

- Creates a DigitalOcean droplet via `doctl`
- Renders `linux/cloud-init.yaml` from template variables (version pins + optional Git identity)
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
- `linux/cloud-init.yaml`: machine bootstrap and runtime setup
- `macos/Brewfile`: Homebrew package list for macOS bootstrap
- `macos/bootstrap-mac.sh`: idempotent macOS arm64 bootstrap script
- `macos/update-checksums.sh`: helper for regenerating/verifying checksum files
- `macos/*.sha256`: checksum files for pinned-source bootstrap verification
- `.github/workflows/checksums.yml`: CI guard for checksum drift
- `.github/workflows/secret-scan.yml`: CI secret scanning with gitleaks
- `.env.sample`: optional configuration overrides

## Prerequisites

- DigitalOcean account and `doctl` installed/authenticated
- Local tools: `jq`, `nc`, `sed`, `base64`
- SSH key available in DigitalOcean

Authenticate `doctl` first:

```bash
doctl auth init
```

## Quick Start

Run these commands from the repository root.

1. (Optional) Create local overrides:

```bash
cp .env.sample .env
```

2. Create a droplet:

```bash
./digitalOcean/create-droplet.sh
```

3. Destroy the last created droplet:

```bash
./digitalOcean/destroy-last-droplet.sh
```

## macOS Bootstrap (arm64)

This path is intentionally simple: one manual command to bootstrap tooling on a fresh Apple Silicon Mac.
No SSH hardening, fail2ban, or background management agents are installed in this flow.

### Option A: Run from local checkout

```bash
./macos/bootstrap-mac.sh --brewfile ./macos/Brewfile
```

### Option B: One command from pinned source URL + checksums

Replace placeholders with your repository and immutable commit SHA.

```bash
RAW_BASE="https://raw.githubusercontent.com/<owner>/<repo>/<commit-sha>/macos"; TMP_DIR="$(mktemp -d)" && \
curl -fsSL "$RAW_BASE/bootstrap-mac.sh" -o "$TMP_DIR/bootstrap-mac.sh" && \
curl -fsSL "$RAW_BASE/bootstrap-mac.sh.sha256" -o "$TMP_DIR/bootstrap-mac.sh.sha256" && \
curl -fsSL "$RAW_BASE/Brewfile" -o "$TMP_DIR/Brewfile" && \
curl -fsSL "$RAW_BASE/Brewfile.sha256" -o "$TMP_DIR/Brewfile.sha256" && \
(cd "$TMP_DIR" && shasum -a 256 -c bootstrap-mac.sh.sha256 && shasum -a 256 -c Brewfile.sha256) && \
BOOTSTRAP_SOURCE_REF="<commit-sha>" bash "$TMP_DIR/bootstrap-mac.sh" --brewfile "$TMP_DIR/Brewfile"
```

### macOS Bootstrap Notes

- Script enforces `Darwin` + `arm64`.
- Script installs Xcode Command Line Tools and Homebrew if needed.
- Toolchain verification is required before completion (`brew`, `node`, `npm`, `pnpm`, `codex`, `playwright`).
- Marker file is written to `~/.bootstrap_done` with timestamp + metadata; installs remain idempotent and do not rely on marker state alone.

### Checksum Maintenance

After editing `macos/bootstrap-mac.sh` or `macos/Brewfile`, refresh checksums before push:

```bash
./macos/update-checksums.sh
```

To verify current files match committed checksums:

```bash
./macos/update-checksums.sh --check
```

## Configuration

Use `.env` to override defaults from `.env.sample`, including:

- droplet settings (`DROPLET_NAME`, `REGION`, `IMAGE`, `SIZE`)
- bootstrap/tool versions (`NODE_MAJOR`, `CODEX_VERSION`, `PNPM_VERSION`, etc.)
- optional Git identity injection (`GIT_USER_NAME`, `GIT_USER_EMAIL`)
- state file and SSH key selection (`STATE_FILE`, `SSH_KEY_ID`, `SSH_KEY_NAME_MATCH`)

## Notes

- `.env` is optional; scripts run with built-in defaults.
- `digitalOcean/create-droplet.sh` writes a rendered cloud-init file to `/tmp` for traceability.
- This README intentionally documents both present functionality and future intent.
