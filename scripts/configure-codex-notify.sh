#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"
NOTIFY_BIN="${NOTIFY_BIN:-/usr/local/bin/carl-notify}"
NOTIFY_ENABLED_DEFAULT="${CARL_NOTIFY_ENABLED_DEFAULT:-1}"
NOTIFY_MIN_INTERVAL_SEC_DEFAULT="${CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT:-120}"
NOTIFY_INCLUDE_SNIPPET_DEFAULT="${CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT:-0}"

usage() {
  cat <<'USAGE'
Usage:
  configure-codex-notify.sh [options]

Options:
  --config <path>                    Codex config file path (default: ~/.codex/config.toml)
  --notify-bin <path>                Notifier binary path (default: /usr/local/bin/carl-notify)
  --notify-enabled-default <0|1>     Default notify enabled value
  --notify-min-interval-sec <int>    Default dedupe interval
  --notify-include-snippet <0|1>     Default snippet toggle
  -h, --help                         Show this help text
USAGE
}

log() {
  printf '[configure-codex-notify] %s\n' "$*" >&2
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

NOTIFY_ENABLED_DEFAULT="$(normalize_bool "$NOTIFY_ENABLED_DEFAULT")"
NOTIFY_INCLUDE_SNIPPET_DEFAULT="$(normalize_bool "$NOTIFY_INCLUDE_SNIPPET_DEFAULT")"

if ! [[ "$NOTIFY_MIN_INTERVAL_SEC_DEFAULT" =~ ^[0-9]+$ ]]; then
  log "--notify-min-interval-sec must be a non-negative integer"
  exit 1
fi

mkdir -p "$(dirname "$CONFIG_FILE")"
if [[ ! -f "$CONFIG_FILE" ]]; then
  : > "$CONFIG_FILE"
fi

NOTIFY_LINE="notify = [\"/usr/bin/env\", \"CARL_NOTIFY_ENABLED_DEFAULT=${NOTIFY_ENABLED_DEFAULT}\", \"CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT=${NOTIFY_MIN_INTERVAL_SEC_DEFAULT}\", \"CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT=${NOTIFY_INCLUDE_SNIPPET_DEFAULT}\", \"${NOTIFY_BIN}\", \"codex\"]"
TUI_LINE="tui.notifications = true"

tmp_file="$(mktemp)"
awk \
  -v notify_line="$NOTIFY_LINE" \
  -v tui_line="$TUI_LINE" \
  '
    BEGIN {
      notify_seen = 0
      tui_seen = 0
    }
    /^[[:space:]]*notify[[:space:]]*=/ {
      if (notify_seen == 0) {
        print notify_line
        notify_seen = 1
      }
      next
    }
    /^[[:space:]]*tui\.notifications[[:space:]]*=/ {
      if (tui_seen == 0) {
        print tui_line
        tui_seen = 1
      }
      next
    }
    {
      print
    }
    END {
      if (notify_seen == 0) {
        print notify_line
      }
      if (tui_seen == 0) {
        print tui_line
      }
    }
  ' "$CONFIG_FILE" > "$tmp_file"

mv "$tmp_file" "$CONFIG_FILE"

log "Configured Codex notifications in ${CONFIG_FILE}"

