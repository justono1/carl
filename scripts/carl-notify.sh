#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  carl-notify.sh <source> [json-payload]

Description:
  Shared Slack notifier for Codex/Claude attention events.
  - <source> should be "codex" or "claude"
  - payload may be passed as a JSON argument or via stdin

Runtime environment:
  - CARL_NOTIFY_ENABLED_DEFAULT (default: 1)
  - CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT (default: 120)
  - CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT (default: 1)
  - CARL_NOTIFY_SNIPPET_MAX_CHARS_DEFAULT (default: 500)
  - NOTIFY_ENABLED / NOTIFY_MIN_INTERVAL_SEC / NOTIFY_INCLUDE_SNIPPET (optional runtime overrides)
  - NOTIFY_SNIPPET_MAX_CHARS (optional runtime override)
  - CARL_SECRETS_FILE (default: ~/.config/carl/secrets.env)
  - SLACK_WEBHOOK_URL (required when enabled)
USAGE
}

log() {
  printf '[carl-notify] %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Missing command: $1"
    exit 1
  }
}

trim_to_single_line() {
  tr '\r\n' '  ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//'
}

hash_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
    return 0
  fi

  log "Missing command: sha256sum or shasum"
  exit 1
}

normalize_bool() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) printf '1' ;;
    0|false|FALSE|no|NO|off|OFF) printf '0' ;;
    *)
      log "Invalid boolean value: $1"
      exit 1
      ;;
  esac
}

normalize_source() {
  local src
  src="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$src" in
    codex|claude) printf '%s' "$src" ;;
    *)
      log "Unsupported source: $1"
      exit 1
      ;;
  esac
}

load_secrets() {
  local file
  file="$1"

  if [[ -f "$file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
  fi
}

extract_event() {
  local payload source
  payload="$1"
  source="$2"

  event="$(printf '%s' "$payload" | jq -r '
    .hook_event_name
    // .event
    // .event_name
    // .type
    // .reason
    // empty
  ' 2>/dev/null || true)"

  if [[ -z "$event" ]]; then
    case "$source" in
      claude) event="notification" ;;
      codex) event="notify" ;;
    esac
  fi

  printf '%s' "$event"
}

extract_message() {
  local payload message
  payload="$1"

  message="$(printf '%s' "$payload" | jq -r '
    .message
    // .title
    // .summary
    // .reason
    // .description
    // .["last-assistant-message"]
    // .last_assistant_message
    // empty
  ' 2>/dev/null || true)"

  if [[ -z "$message" ]]; then
    printf ''
    return 0
  fi

  printf '%s' "$message" | trim_to_single_line
}

extract_cwd() {
  local payload value
  payload="$1"
  value="$(printf '%s' "$payload" | jq -r '
    .cwd
    // .workspace_path
    // .workspace_root
    // .path
    // empty
  ' 2>/dev/null || true)"

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  pwd
}

extract_session_hint() {
  local payload
  payload="$1"
  printf '%s' "$payload" | jq -r '
    .session_id
    // .["turn-id"]
    // .turn_id
    // .conversation_id
    // .request_id
    // .id
    // empty
  ' 2>/dev/null || true
}

extract_client() {
  local payload
  payload="$1"
  printf '%s' "$payload" | jq -r '
    .client
    // .client_name
    // empty
  ' 2>/dev/null || true
}

should_send_based_on_dedupe() {
  local key now_ts state_file cache_dir min_interval
  key="$1"
  min_interval="$2"
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/carl-notify"
  state_file="${cache_dir}/last_event"
  now_ts="$(date +%s)"

  mkdir -p "$cache_dir"
  chmod 700 "$cache_dir"

  if [[ -f "$state_file" ]]; then
    local last_ts last_key
    last_ts=""
    last_key=""
    read -r last_ts last_key < "$state_file" || true
    if [[ -n "$last_ts" && -n "$last_key" && "$last_key" == "$key" ]]; then
      if [[ "$last_ts" =~ ^[0-9]+$ ]]; then
        if (( now_ts - last_ts < min_interval )); then
          return 1
        fi
      fi
    fi
  fi

  printf '%s %s\n' "$now_ts" "$key" > "$state_file"
  chmod 600 "$state_file"
  return 0
}

send_slack() {
  local webhook_url text payload
  webhook_url="$1"
  text="$2"

  payload="$(jq -n --arg text "$text" '{text: $text}')"
  curl -fsS \
    -X POST \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "$webhook_url" >/dev/null
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

need_cmd jq
need_cmd curl
need_cmd hostname
need_cmd sed

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

SOURCE="$(normalize_source "$1")"
shift || true

DEFAULT_NOTIFY_ENABLED="$(normalize_bool "${CARL_NOTIFY_ENABLED_DEFAULT:-1}")"
DEFAULT_NOTIFY_INCLUDE_SNIPPET="$(normalize_bool "${CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT:-1}")"
DEFAULT_NOTIFY_MIN_INTERVAL_SEC="${CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT:-120}"
DEFAULT_NOTIFY_SNIPPET_MAX_CHARS="${CARL_NOTIFY_SNIPPET_MAX_CHARS_DEFAULT:-500}"

NOTIFY_ENABLED="$(normalize_bool "${NOTIFY_ENABLED:-$DEFAULT_NOTIFY_ENABLED}")"
NOTIFY_INCLUDE_SNIPPET="$(normalize_bool "${NOTIFY_INCLUDE_SNIPPET:-$DEFAULT_NOTIFY_INCLUDE_SNIPPET}")"
NOTIFY_MIN_INTERVAL_SEC="${NOTIFY_MIN_INTERVAL_SEC:-$DEFAULT_NOTIFY_MIN_INTERVAL_SEC}"
NOTIFY_SNIPPET_MAX_CHARS="${NOTIFY_SNIPPET_MAX_CHARS:-$DEFAULT_NOTIFY_SNIPPET_MAX_CHARS}"

if ! [[ "$NOTIFY_MIN_INTERVAL_SEC" =~ ^[0-9]+$ ]]; then
  log "NOTIFY_MIN_INTERVAL_SEC must be a non-negative integer (got: $NOTIFY_MIN_INTERVAL_SEC)"
  exit 1
fi

if ! [[ "$NOTIFY_SNIPPET_MAX_CHARS" =~ ^[0-9]+$ ]]; then
  log "NOTIFY_SNIPPET_MAX_CHARS must be a non-negative integer (got: $NOTIFY_SNIPPET_MAX_CHARS)"
  exit 1
fi

if [[ "$NOTIFY_ENABLED" != "1" ]]; then
  exit 0
fi

SECRETS_FILE="${CARL_SECRETS_FILE:-$HOME/.config/carl/secrets.env}"
load_secrets "$SECRETS_FILE"

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  log "SLACK_WEBHOOK_URL is required (set in ${SECRETS_FILE})"
  exit 2
fi

RAW_PAYLOAD=""
if [[ $# -gt 0 ]]; then
  RAW_PAYLOAD="$*"
elif [[ ! -t 0 ]]; then
  RAW_PAYLOAD="$(cat || true)"
fi

if [[ -z "$RAW_PAYLOAD" ]]; then
  PAYLOAD='{}'
elif printf '%s' "$RAW_PAYLOAD" | jq -e . >/dev/null 2>&1; then
  PAYLOAD="$RAW_PAYLOAD"
else
  PAYLOAD="$(jq -n --arg message "$RAW_PAYLOAD" '{message: $message}')"
fi

EVENT="$(extract_event "$PAYLOAD" "$SOURCE")"
MESSAGE="$(extract_message "$PAYLOAD")"
CWD_HINT="$(extract_cwd "$PAYLOAD")"
SESSION_HINT="$(extract_session_hint "$PAYLOAD")"
CLIENT_HINT="$(extract_client "$PAYLOAD")"

HOST_NAME="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown-host)"
USER_NAME="${USER:-unknown-user}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

KEY_INPUT="$(printf '%s|%s|%s|%s|%s' "$SOURCE" "$EVENT" "$CWD_HINT" "$SESSION_HINT" "$MESSAGE")"
DEDUP_KEY="$(printf '%s' "$KEY_INPUT" | hash_sha256)"

if ! should_send_based_on_dedupe "$DEDUP_KEY" "$NOTIFY_MIN_INTERVAL_SEC"; then
  exit 0
fi

TITLE="CARL attention needed: ${SOURCE} (${EVENT})"
BODY_LINES=(
  "$TITLE"
  "source=${SOURCE}"
  "event=${EVENT}"
  "host=${HOST_NAME}"
  "user=${USER_NAME}"
  "cwd=${CWD_HINT}"
  "time_utc=${NOW_UTC}"
)

if [[ -n "$SESSION_HINT" ]]; then
  BODY_LINES+=("session=${SESSION_HINT}")
fi

if [[ -n "$CLIENT_HINT" ]]; then
  BODY_LINES+=("client=${CLIENT_HINT}")
fi

if [[ "$NOTIFY_INCLUDE_SNIPPET" == "1" && -n "$MESSAGE" ]]; then
  SNIPPET="$(printf '%.*s' "$NOTIFY_SNIPPET_MAX_CHARS" "$MESSAGE")"
  BODY_LINES+=("message=${SNIPPET}")
fi

SLACK_TEXT="$(printf '%s\n' "${BODY_LINES[@]}")"
send_slack "$SLACK_WEBHOOK_URL" "$SLACK_TEXT"
