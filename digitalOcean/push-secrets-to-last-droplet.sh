#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=../scripts/load-domain-env.sh
source "${REPO_ROOT}/scripts/load-domain-env.sh"

RUNTIME_ENV_FILE="${RUNTIME_ENV_FILE:-$REPO_ROOT/runtime/env}"
carl_load_env_file "${RUNTIME_ENV_FILE}"
carl_require_env_keys STATE_FILE

STATE_FILE="$(carl_to_repo_root_path "${STATE_FILE}")"
PUSH_SCRIPT="${REPO_ROOT}/scripts/push-secrets.sh"

if [[ ! -f "${PUSH_SCRIPT}" ]]; then
  echo "[push-secrets-do] Missing push script: ${PUSH_SCRIPT}" >&2
  exit 1
fi

bash "${PUSH_SCRIPT}" --do-state "${STATE_FILE}" "$@"
