#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
NOTIFY_BIN="${NOTIFY_BIN:-/usr/local/bin/carl-notify}"
NOTIFY_ENABLED_DEFAULT="${CARL_NOTIFY_ENABLED_DEFAULT:-1}"
NOTIFY_MIN_INTERVAL_SEC_DEFAULT="${CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT:-120}"
NOTIFY_INCLUDE_SNIPPET_DEFAULT="${CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT:-0}"

usage() {
  cat <<'USAGE'
Usage:
  configure-claude-notify.sh [options]

Options:
  --config <path>                    Claude settings JSON path (default: ~/.claude/settings.json)
  --notify-bin <path>                Notifier binary path (default: /usr/local/bin/carl-notify)
  --notify-enabled-default <0|1>     Default notify enabled value
  --notify-min-interval-sec <int>    Default dedupe interval
  --notify-include-snippet <0|1>     Default snippet toggle
  -h, --help                         Show this help text
USAGE
}

log() {
  printf '[configure-claude-notify] %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Missing command: $1"
    exit 1
  }
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { log "--config requires a value"; exit 1; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    --notify-bin)
      [[ $# -ge 2 ]] || { log "--notify-bin requires a value"; exit 1; }
      NOTIFY_BIN="$2"
      shift 2
      ;;
    --notify-enabled-default)
      [[ $# -ge 2 ]] || { log "--notify-enabled-default requires a value"; exit 1; }
      NOTIFY_ENABLED_DEFAULT="$2"
      shift 2
      ;;
    --notify-min-interval-sec)
      [[ $# -ge 2 ]] || { log "--notify-min-interval-sec requires a value"; exit 1; }
      NOTIFY_MIN_INTERVAL_SEC_DEFAULT="$2"
      shift 2
      ;;
    --notify-include-snippet)
      [[ $# -ge 2 ]] || { log "--notify-include-snippet requires a value"; exit 1; }
      NOTIFY_INCLUDE_SNIPPET_DEFAULT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

need_cmd jq

NOTIFY_ENABLED_DEFAULT="$(normalize_bool "$NOTIFY_ENABLED_DEFAULT")"
NOTIFY_INCLUDE_SNIPPET_DEFAULT="$(normalize_bool "$NOTIFY_INCLUDE_SNIPPET_DEFAULT")"

if ! [[ "$NOTIFY_MIN_INTERVAL_SEC_DEFAULT" =~ ^[0-9]+$ ]]; then
  log "--notify-min-interval-sec must be a non-negative integer"
  exit 1
fi

mkdir -p "$(dirname "$CONFIG_FILE")"

if [[ ! -f "$CONFIG_FILE" ]]; then
  printf '{}\n' > "$CONFIG_FILE"
fi

if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then
  log "Invalid JSON in ${CONFIG_FILE}; refusing to modify."
  exit 1
fi

escaped_notify_bin="$(printf '%q' "$NOTIFY_BIN")"
command_string="CARL_NOTIFY_ENABLED_DEFAULT=${NOTIFY_ENABLED_DEFAULT} CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT=${NOTIFY_MIN_INTERVAL_SEC_DEFAULT} CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT=${NOTIFY_INCLUDE_SNIPPET_DEFAULT} ${escaped_notify_bin} claude"

tmp_file="$(mktemp)"
jq --arg cmd "$command_string" '
  . as $root
  | if ($root | type) == "object" then $root else {} end
  | .hooks = (.hooks // {})
  | .hooks.Notification = (
      if (.hooks.Notification | type) == "array"
      then .hooks.Notification
      else []
      end
    )
  | if ([ .hooks.Notification[]?.hooks[]? | select(.type == "command" and .command == $cmd) ] | length) > 0
    then .
    else .hooks.Notification += [
      {
        "hooks": [
          {
            "type": "command",
            "command": $cmd
          }
        ]
      }
    ]
    end
' "$CONFIG_FILE" > "$tmp_file"

mv "$tmp_file" "$CONFIG_FILE"

log "Configured Claude Notification hook in ${CONFIG_FILE}"

