#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

SOURCE_FILE="${REPO_ROOT}/.secrets/secrets.env"
STATE_FILE="${REPO_ROOT}/.do-droplet.json"
REMOTE_TMP="/tmp/carl.secrets.env"
REQUIRED_KEYS_CSV=""
TARGET_MODE=""
SSH_TARGET=""

usage() {
  cat <<'USAGE'
Usage:
  push-secrets.sh [options]

Target mode (exactly one required):
  --ssh <user@host>        Push to a remote machine over SSH/SCP
  --do-state [path]        Resolve droplet IP from CARL state JSON and push as root

Options:
  --source <path>          Local source dotenv file (default: ./.secrets/secrets.env)
  --remote-tmp <path>      Remote temporary path (default: /tmp/carl.secrets.env)
  --required-keys <csv>    Comma-separated keys required to be non-empty (validated remotely)
  -h, --help               Show this help text
USAGE
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[push-secrets] Missing command: $1" >&2
    exit 1
  }
}

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

to_repo_root_path() {
  local path
  path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${REPO_ROOT}/${path}"
  fi
}

detect_file_mode() {
  local path mode
  path="$1"

  if mode="$(stat -c '%a' "$path" 2>/dev/null)"; then
    printf '%s\n' "$mode"
    return 0
  fi

  if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
    printf '%s\n' "$mode"
    return 0
  fi

  return 1
}

set_target_mode() {
  local next_mode
  next_mode="$1"
  if [[ -n "${TARGET_MODE}" && "${TARGET_MODE}" != "${next_mode}" ]]; then
    echo "[push-secrets] Use exactly one target mode: --ssh or --do-state" >&2
    exit 1
  fi
  TARGET_MODE="${next_mode}"
}

validate_source_file() {
  local source_mode
  if [[ ! -f "${SOURCE_FILE}" ]]; then
    echo "[push-secrets] Source file not found: ${SOURCE_FILE}" >&2
    exit 2
  fi

  if [[ ! -r "${SOURCE_FILE}" ]]; then
    echo "[push-secrets] Source file is not readable: ${SOURCE_FILE}" >&2
    exit 2
  fi

  source_mode="$(detect_file_mode "${SOURCE_FILE}" || true)"
  if [[ -z "${source_mode}" ]]; then
    echo "[push-secrets] Could not determine file mode: ${SOURCE_FILE}" >&2
    exit 2
  fi

  if [[ "${source_mode}" != "600" ]]; then
    echo "[push-secrets] Source mode must be 600, found ${source_mode}: ${SOURCE_FILE}" >&2
    echo "[push-secrets] Fix with: chmod 600 '${SOURCE_FILE}'" >&2
    exit 2
  fi
}

resolve_ip_from_state() {
  local ip
  need_cmd jq

  if [[ ! -f "${STATE_FILE}" ]]; then
    echo "[push-secrets] State file not found: ${STATE_FILE}" >&2
    exit 2
  fi

  ip="$(jq -r '.droplet.ip // empty' "${STATE_FILE}")"
  if [[ -z "${ip}" || "${ip}" == "null" ]]; then
    echo "[push-secrets] Could not resolve droplet.ip from state file: ${STATE_FILE}" >&2
    exit 2
  fi

  printf '%s\n' "${ip}"
}

run_remote_install() {
  local target
  local cleanup_cmd

  target="$1"

  need_cmd scp
  need_cmd ssh

  echo "[push-secrets] Copying source file to ${target}:${REMOTE_TMP}"
  scp -q "${SOURCE_FILE}" "${target}:${REMOTE_TMP}"

  echo "[push-secrets] Installing secrets on ${target}."
  # shellcheck disable=SC2029
  if ! ssh -o StrictHostKeyChecking=accept-new "${target}" \
    "bash -s -- $(printf '%q' "${REMOTE_TMP}") $(printf '%q' "${REQUIRED_KEYS_CSV}")" <<'REMOTE_INSTALL'
set -euo pipefail

SOURCE_PATH="$1"
REQUIRED_KEYS_CSV="${2:-}"
DEST_PATH="${HOME}/.config/carl/secrets.env"

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

detect_file_mode() {
  local path mode
  path="$1"
  if mode="$(stat -c '%a' "$path" 2>/dev/null)"; then
    printf '%s\n' "$mode"
    return 0
  fi
  if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
    printf '%s\n' "$mode"
    return 0
  fi
  return 1
}

validate_required_keys() {
  local key key_trimmed line value
  local keys=()

  if [[ -z "${REQUIRED_KEYS_CSV}" ]]; then
    return 0
  fi

  IFS=',' read -r -a keys <<< "${REQUIRED_KEYS_CSV}"
  for key in "${keys[@]}"; do
    key_trimmed="$(trim "${key}")"
    if [[ -z "${key_trimmed}" ]]; then
      continue
    fi
    if [[ ! "${key_trimmed}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "[push-secrets][remote] Invalid required key name: ${key_trimmed}" >&2
      exit 3
    fi
    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key_trimmed}=" "${DEST_PATH}" | tail -n1 || true)"
    if [[ -z "${line}" ]]; then
      echo "[push-secrets][remote] Missing required key: ${key_trimmed}" >&2
      exit 3
    fi
    value="$(trim "${line#*=}")"
    if [[ -z "${value}" || "${value}" == '""' || "${value}" == "''" ]]; then
      echo "[push-secrets][remote] Required key is empty: ${key_trimmed}" >&2
      exit 3
    fi
  done
}

mkdir -p "$(dirname "${DEST_PATH}")"
install -m 600 "${SOURCE_PATH}" "${DEST_PATH}"
validate_required_keys
dest_mode="$(detect_file_mode "${DEST_PATH}" || true)"
if [[ "${dest_mode}" != "600" ]]; then
  echo "[push-secrets][remote] Destination mode must be 600, found ${dest_mode}" >&2
  exit 2
fi
rm -f "${SOURCE_PATH}"
echo "[push-secrets][remote] Installed secrets file at: ${DEST_PATH}"
echo "[push-secrets][remote] File mode verified: ${dest_mode}"
REMOTE_INSTALL
  then
    cleanup_cmd="rm -f $(printf '%q' "${REMOTE_TMP}")"
    # shellcheck disable=SC2029
    ssh -o StrictHostKeyChecking=accept-new "${target}" "${cleanup_cmd}" >/dev/null 2>&1 || true
    echo "[push-secrets] Remote install failed on ${target}" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "[push-secrets] --source requires a value" >&2; exit 1; }
      SOURCE_FILE="$(to_repo_root_path "$2")"
      shift 2
      ;;
    --remote-tmp)
      [[ $# -ge 2 ]] || { echo "[push-secrets] --remote-tmp requires a value" >&2; exit 1; }
      REMOTE_TMP="$2"
      shift 2
      ;;
    --required-keys)
      [[ $# -ge 2 ]] || { echo "[push-secrets] --required-keys requires a value" >&2; exit 1; }
      REQUIRED_KEYS_CSV="$(trim "$2")"
      shift 2
      ;;
    --ssh)
      [[ $# -ge 2 ]] || { echo "[push-secrets] --ssh requires a value" >&2; exit 1; }
      set_target_mode "ssh"
      SSH_TARGET="$2"
      shift 2
      ;;
    --do-state)
      set_target_mode "do-state"
      if [[ $# -ge 2 && "${2}" != --* && "${2}" != -* ]]; then
        STATE_FILE="$(to_repo_root_path "$2")"
        shift 2
      else
        shift
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[push-secrets] Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${TARGET_MODE}" ]]; then
  echo "[push-secrets] One target mode is required: --ssh or --do-state" >&2
  usage >&2
  exit 1
fi

need_cmd sed
need_cmd stat
validate_source_file

case "${TARGET_MODE}" in
  ssh)
    if [[ -z "${SSH_TARGET}" ]]; then
      echo "[push-secrets] --ssh target cannot be empty" >&2
      exit 1
    fi
    run_remote_install "${SSH_TARGET}"
    ;;
  do-state)
    droplet_ip="$(resolve_ip_from_state)"
    run_remote_install "root@${droplet_ip}"
    ;;
  *)
    echo "[push-secrets] Unsupported target mode: ${TARGET_MODE}" >&2
    exit 1
    ;;
esac

echo "[push-secrets] Secrets push completed."
