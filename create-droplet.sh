#!/usr/bin/env bash
set -euo pipefail

# ---- Config ----
DROPLET_NAME="${DROPLET_NAME:-devbox-1}"
REGION="${REGION:-nyc3}"
IMAGE="${IMAGE:-ubuntu-24-04-x64}"
SIZE="${SIZE:-s-1vcpu-2gb}"
CLOUD_INIT_FILE="${CLOUD_INIT_FILE:-./cloud-init.yaml}"

# State file written by this script (used by destroy script)
STATE_FILE="${STATE_FILE:-./.do-droplet.json}"

# SSH key selection:
# - Prefer setting SSH_KEY_ID explicitly
# - Or set SSH_KEY_NAME_MATCH to match a key name
SSH_KEY_NAME_MATCH="${SSH_KEY_NAME_MATCH:-}"
SSH_KEY_ID="${SSH_KEY_ID:-}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }

need_cmd doctl
need_cmd jq
need_cmd nc

# Ensure doctl is authenticated
if ! doctl account get >/dev/null 2>&1; then
  echo "doctl is not authenticated. Run: doctl auth init"
  exit 1
fi

# Ensure cloud-init exists
if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
  echo "Cloud-init file not found: $CLOUD_INIT_FILE"
  exit 1
fi

# Resolve SSH key id
if [[ -z "$SSH_KEY_ID" ]]; then
  keys_json="$(doctl compute ssh-key list --output json)"

  if [[ -n "$SSH_KEY_NAME_MATCH" ]]; then
    SSH_KEY_ID="$(echo "$keys_json" | jq -r --arg m "$SSH_KEY_NAME_MATCH" '
      (map(select((.name // "") | test($m; "i")))[0].id) // empty
    ')"
  else
    SSH_KEY_ID="$(echo "$keys_json" | jq -r '.[0].id // empty')"
  fi
fi

if [[ -z "$SSH_KEY_ID" ]]; then
  echo "Could not determine SSH_KEY_ID."
  echo "Set SSH_KEY_ID=... or SSH_KEY_NAME_MATCH=..."
  echo "Available keys:"
  doctl compute ssh-key list
  exit 1
fi

echo "Creating droplet:"
echo "  name:      $DROPLET_NAME"
echo "  region:    $REGION"
echo "  image:     $IMAGE"
echo "  size:      $SIZE"
echo "  ssh key:   $SSH_KEY_ID"
echo "  user-data: $CLOUD_INIT_FILE"
echo "  state:     $STATE_FILE"
echo

create_json="$(doctl compute droplet create "$DROPLET_NAME" \
  --region "$REGION" \
  --image "$IMAGE" \
  --size "$SIZE" \
  --ssh-keys "$SSH_KEY_ID" \
  --user-data-file "$CLOUD_INIT_FILE" \
  --enable-monitoring \
  --wait \
  --output json)"

droplet_id="$(echo "$create_json" | jq -r '.[0].id')"

# Fetch public IPv4 (retry because networks can be slow to populate)
ip=""
for _ in {1..10}; do
  ip="$(doctl compute droplet get "$droplet_id" --output json \
    | jq -r '.[0].networks.v4 // [] | .[] | select(.type=="public") | .ip_address' \
    | head -n1 || true)"
  [[ -n "$ip" && "$ip" != "null" ]] && break
  sleep 3
done

# Wait for SSH port to become reachable (avoids early "connection refused" flapping)
if [[ -n "$ip" && "$ip" != "null" ]]; then
  echo "Waiting for SSH (port 22) to become reachable..."
  for _ in {1..60}; do
    if nc -z "$ip" 22 >/dev/null 2>&1; then
      echo "SSH is reachable."
      break
    fi
    sleep 2
  done
fi

# Write state file for later destruction
created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq -n \
  --arg id "$droplet_id" \
  --arg name "$DROPLET_NAME" \
  --arg region "$REGION" \
  --arg image "$IMAGE" \
  --arg size "$SIZE" \
  --arg ip "${ip:-}" \
  --arg created_at "$created_at" \
  '{
    droplet: {
      id: $id,
      name: $name,
      region: $region,
      image: $image,
      size: $size,
      ip: $ip,
      created_at: $created_at
    }
  }' > "$STATE_FILE"

echo
echo "✅ Droplet created: $DROPLET_NAME (id: $droplet_id)"
if [[ -n "$ip" && "$ip" != "null" ]]; then
  echo "🌐 Public IP: $ip"
  echo "Connect:"
  echo "  ssh root@$ip"
else
  echo "⚠️ Public IP not available yet. Try:"
  echo "  doctl compute droplet get $droplet_id"
fi
echo
echo "State saved to: $STATE_FILE"