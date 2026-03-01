#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

to_repo_root_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$REPO_ROOT/$path"
  fi
}

# Load optional .env file for local machine/runtime settings.
# If the file is missing, defaults below are used.
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
ENV_FILE="$(to_repo_root_path "$ENV_FILE")"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# ---- Config ----
DROPLET_NAME="${DROPLET_NAME:-devbox-1}"
REGION="${REGION:-nyc3}"
IMAGE="${IMAGE:-ubuntu-24-04-x64}"
SIZE="${SIZE:-s-1vcpu-2gb}"
CLOUD_INIT_FILE="${CLOUD_INIT_FILE:-$REPO_ROOT/linux/cloud-init.yaml}"
CLOUD_INIT_FILE="$(to_repo_root_path "$CLOUD_INIT_FILE")"
GIT_USER_NAME=""
GIT_USER_EMAIL=""

# State file written by this script (used by destroy script)
STATE_FILE="${STATE_FILE:-$REPO_ROOT/.do-droplet.json}"
STATE_FILE="$(to_repo_root_path "$STATE_FILE")"

# SSH key selection:
# - Prefer setting SSH_KEY_ID explicitly
# - Or set SSH_KEY_NAME_MATCH to match a key name
SSH_KEY_NAME_MATCH="${SSH_KEY_NAME_MATCH:-}"
SSH_KEY_ID="${SSH_KEY_ID:-}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

b64_no_newline() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

prompt_required_value() {
  local label current value
  label="$1"
  current="$2"

  while true; do
    if [[ -n "$current" ]]; then
      read -r -p "${label} [${current}]: " value
      value="${value:-$current}"
    else
      read -r -p "${label}: " value
    fi

    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi

    echo "${label} is required." >&2
  done
}

resolve_git_identity() {
  local default_name default_email

  if [[ ! -t 0 ]]; then
    echo "Interactive terminal required to collect Git identity." >&2
    echo "Run this script in a TTY session." >&2
    exit 1
  fi

  default_name=""
  default_email=""
  if command -v git >/dev/null 2>&1; then
    default_name="$(git config --global --get user.name 2>/dev/null || true)"
    default_email="$(git config --global --get user.email 2>/dev/null || true)"
  fi

  echo
  echo "Git identity is required for cloud bootstrap."
  GIT_USER_NAME="$(prompt_required_value "Git user.name" "$default_name")"
  GIT_USER_EMAIL="$(prompt_required_value "Git user.email" "$default_email")"
}

assert_cloud_init_is_rendered() {
  local unresolved
  unresolved="$(grep -nE '@[A-Z0-9_]+@' "$CLOUD_INIT_FILE" || true)"

  if [[ -z "$unresolved" ]]; then
    return
  fi

  if printf '%s\n' "$unresolved" | grep -vE '@GIT_USER_NAME_B64@|@GIT_USER_EMAIL_B64@' >/dev/null 2>&1; then
    echo "Cloud-init artifact has unresolved non-Git placeholders: $CLOUD_INIT_FILE" >&2
    printf '%s\n' "$unresolved" | grep -vE '@GIT_USER_NAME_B64@|@GIT_USER_EMAIL_B64@' >&2
    echo "Run: ./scripts/render-bootstrap-artifacts.sh" >&2
    exit 1
  fi
}

render_cloud_init_template() {
  local template_file output_file git_name_b64 git_email_b64
  template_file="$1"
  output_file="$2"

  git_name_b64="$(b64_no_newline "$GIT_USER_NAME")"
  git_email_b64="$(b64_no_newline "$GIT_USER_EMAIL")"

  sed \
    -e "s/@GIT_USER_NAME_B64@/$(escape_sed_replacement "$git_name_b64")/g" \
    -e "s/@GIT_USER_EMAIL_B64@/$(escape_sed_replacement "$git_email_b64")/g" \
    "$template_file" > "$output_file"
}

need_cmd doctl
need_cmd jq
need_cmd nc
need_cmd sed
need_cmd base64
need_cmd grep

# Ensure doctl is authenticated
if ! doctl account get >/dev/null 2>&1; then
  echo "doctl is not authenticated. Run: doctl auth init"
  exit 1
fi

# Resolve user-data file:
# - Render CLOUD_INIT_FILE to a timestamped /tmp file
# - Pass rendered file to doctl
rendered_cloud_init_file=""

if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
  echo "Cloud-init source file not found: $CLOUD_INIT_FILE"
  exit 1
fi
resolve_git_identity
assert_cloud_init_is_rendered
rendered_ts="$(date -u +"%Y%m%dT%H%M%SZ")"
rendered_cloud_init_file="/tmp/cloud-init.rendered.${rendered_ts}.$$.yaml"
render_cloud_init_template "$CLOUD_INIT_FILE" "$rendered_cloud_init_file"
user_data_file="$rendered_cloud_init_file"

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
echo "  user-data: $user_data_file"
echo "  source:    $CLOUD_INIT_FILE"
echo "  rendered:  kept at $rendered_cloud_init_file"
echo "  state:     $STATE_FILE"
echo

create_json="$(doctl compute droplet create "$DROPLET_NAME" \
  --region "$REGION" \
  --image "$IMAGE" \
  --size "$SIZE" \
  --ssh-keys "$SSH_KEY_ID" \
  --user-data-file "$user_data_file" \
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
