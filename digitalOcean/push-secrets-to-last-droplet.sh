#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

to_repo_root_path() {
  local path
  path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${REPO_ROOT}/${path}"
  fi
}

ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"
ENV_FILE="$(to_repo_root_path "${ENV_FILE}")"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

STATE_FILE="${STATE_FILE:-$REPO_ROOT/.do-droplet.json}"
STATE_FILE="$(to_repo_root_path "${STATE_FILE}")"
PUSH_SCRIPT="${REPO_ROOT}/scripts/push-secrets.sh"

if [[ ! -f "${PUSH_SCRIPT}" ]]; then
  echo "[push-secrets-do] Missing push script: ${PUSH_SCRIPT}" >&2
  exit 1
fi

bash "${PUSH_SCRIPT}" --do-state "${STATE_FILE}" "$@"
