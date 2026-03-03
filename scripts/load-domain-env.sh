#!/usr/bin/env bash

# shellcheck shell=bash

if [[ -n "${CARL_DOMAIN_ENV_LOADER_SOURCED:-}" ]]; then
  return 0
fi
CARL_DOMAIN_ENV_LOADER_SOURCED=1

CARL_DOMAIN_ENV_LOADER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CARL_DOMAIN_ENV_LOADER_REPO_ROOT="$(cd -- "${CARL_DOMAIN_ENV_LOADER_DIR}/.." >/dev/null 2>&1 && pwd)"

carl_repo_root() {
  if [[ -n "${REPO_ROOT:-}" ]]; then
    printf '%s\n' "${REPO_ROOT}"
    return 0
  fi

  printf '%s\n' "${CARL_DOMAIN_ENV_LOADER_REPO_ROOT}"
}

carl_to_repo_root_path() {
  local path
  path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "$(carl_repo_root)/${path}"
  fi
}

carl_load_env_file() {
  local path required resolved
  path="$1"
  required="${2:-1}"
  resolved="$(carl_to_repo_root_path "${path}")"

  if [[ ! -f "${resolved}" ]]; then
    if [[ "${required}" == "1" ]]; then
      echo "Required env file not found: ${resolved}" >&2
      return 1
    fi
    return 0
  fi

  set -a
  # shellcheck disable=SC1090
  source "${resolved}"
  set +a
}

carl_require_env_keys() {
  local key value
  for key in "$@"; do
    value="${!key:-}"
    if [[ -z "${value}" ]]; then
      echo "Missing required configuration key: ${key}" >&2
      return 1
    fi
  done
}
