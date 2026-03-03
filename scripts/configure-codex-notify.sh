#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

CONFIG_FILE="${CODEX_CONFIG_FILE:-$HOME/.codex/config.toml}"
SOURCE_CONFIG_FILE="${SOURCE_CONFIG_FILE:-$REPO_ROOT/codex/config.toml}"
NOTIFY_ENV_FILE="${NOTIFY_ENV_FILE:-$REPO_ROOT/notify/env}"
NOTIFY_BIN="${NOTIFY_BIN:-/usr/local/bin/carl-notify}"
NOTIFY_ENABLED_DEFAULT=""
NOTIFY_MIN_INTERVAL_SEC_DEFAULT=""
NOTIFY_INCLUDE_SNIPPET_DEFAULT=""

usage() {
  cat <<'USAGE'
Usage:
  configure-codex-notify.sh [options]

Options:
  --config <path>                    Codex config file path (default: ~/.codex/config.toml)
  --source-config <path>             Canonical source config to install before wiring notify
  --notify-env <path>                Notify env file (default: ./notify/env)
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

resolve_notify_defaults() {
  if [[ -f "$NOTIFY_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV_FILE"
    set +a
  fi

  if [[ -z "$NOTIFY_ENABLED_DEFAULT" ]]; then
    NOTIFY_ENABLED_DEFAULT="${CARL_NOTIFY_ENABLED_DEFAULT:-${NOTIFY_ENABLED:-1}}"
  fi

  if [[ -z "$NOTIFY_MIN_INTERVAL_SEC_DEFAULT" ]]; then
    NOTIFY_MIN_INTERVAL_SEC_DEFAULT="${CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT:-${NOTIFY_MIN_INTERVAL_SEC:-120}}"
  fi

  if [[ -z "$NOTIFY_INCLUDE_SNIPPET_DEFAULT" ]]; then
    NOTIFY_INCLUDE_SNIPPET_DEFAULT="${CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT:-${NOTIFY_INCLUDE_SNIPPET:-1}}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { log "--config requires a value"; exit 1; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    --source-config)
      [[ $# -ge 2 ]] || { log "--source-config requires a value"; exit 1; }
      SOURCE_CONFIG_FILE="$2"
      shift 2
      ;;
    --notify-env)
      [[ $# -ge 2 ]] || { log "--notify-env requires a value"; exit 1; }
      NOTIFY_ENV_FILE="$2"
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

resolve_notify_defaults

NOTIFY_ENABLED_DEFAULT="$(normalize_bool "$NOTIFY_ENABLED_DEFAULT")"
NOTIFY_INCLUDE_SNIPPET_DEFAULT="$(normalize_bool "$NOTIFY_INCLUDE_SNIPPET_DEFAULT")"

if ! [[ "$NOTIFY_MIN_INTERVAL_SEC_DEFAULT" =~ ^[0-9]+$ ]]; then
  log "--notify-min-interval-sec must be a non-negative integer"
  exit 1
fi

if [[ ! -f "$SOURCE_CONFIG_FILE" ]]; then
  log "Source config not found: ${SOURCE_CONFIG_FILE}"
  exit 1
fi

mkdir -p "$(dirname "$CONFIG_FILE")"
install -m 0644 "$SOURCE_CONFIG_FILE" "$CONFIG_FILE"

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

log "Installed ${SOURCE_CONFIG_FILE} and configured Codex notifications in ${CONFIG_FILE}"
