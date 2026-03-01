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
