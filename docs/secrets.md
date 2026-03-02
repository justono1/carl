# Secrets Management (v1)

CARL keeps secret values out of git history while still letting this repository define the workflow.

## Policy

- Store local secret values in this repo at `./.secrets/secrets.env`.
- `./.secrets/` must stay untracked.
- Never place secrets in `.env`, cloud-init templates, or committed scripts.
- Destination path on all target machines is `~/.config/carl/secrets.env`.

## Local Source Setup

Run from repo root:

```bash
mkdir -p .secrets
touch .secrets/secrets.env
chmod 600 .secrets/secrets.env
```

Dotenv format example:

```dotenv
OPENAI_API_KEY=...
GITHUB_TOKEN=...
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

`SLACK_WEBHOOK_URL` is used by `carl-notify` for Codex/Claude attention notifications.

## Commands

### Push to last created DigitalOcean droplet

```bash
./digitalOcean/push-secrets-to-last-droplet.sh
```

Equivalent direct call:

```bash
./scripts/push-secrets.sh --do-state
```

### Push to explicit SSH target

```bash
./scripts/push-secrets.sh --ssh user@host
```

### Validate required keys during install

```bash
./scripts/push-secrets.sh --ssh user@host --required-keys OPENAI_API_KEY,GITHUB_TOKEN
```

## macOS VM Workflows

Use one destination path regardless of transfer method.

SSH access and SSH key generation are separate:
- Enabling Remote Login controls whether the Mac accepts inbound SSH connections.
- A local `~/.ssh/id_ed25519` key only enables outbound auth/signing and does not enable inbound SSH access.

### GUI transfer (Parallels / screen share)

1. Transfer your local file to `/tmp/carl.secrets.env` on the VM.
2. Run:

```bash
mkdir -p ~/.config/carl && install -m 600 /tmp/carl.secrets.env ~/.config/carl/secrets.env && rm -f /tmp/carl.secrets.env
```

### Enable SSH on macOS (for SSH/SCP transfer)

1. Open **System Settings > General > Sharing**.
2. Turn on **Remote Login**.
3. Choose allowed users.

Verify the SSH service from Terminal:

```bash
sudo systemsetup -getremotelogin
nc -vz localhost 22
```

Find the connectable IP address:

```bash
ipconfig getifaddr en0
ipconfig getifaddr en1
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### SSH/SCP transfer

```bash
./scripts/push-secrets.sh --ssh user@host
# Example:
./scripts/push-secrets.sh --ssh myuser@192.168.1.50
```

## Rotation

1. Edit `./.secrets/secrets.env`.
2. Re-run the relevant push command.
3. Restart only the processes that consume changed keys.

## Troubleshooting

- `Source mode must be 600`: run `chmod 600 ./.secrets/secrets.env`.
- `Could not resolve droplet.ip`: recreate/persist state with `create-droplet.sh`.
- `Permission denied` over SSH/SCP: verify user, host, and key auth.
- Keys missing with `--required-keys`: ensure dotenv entries exist and are non-empty.
- `SLACK_WEBHOOK_URL is required`: add webhook URL to `./.secrets/secrets.env` and push again.
