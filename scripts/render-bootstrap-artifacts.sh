#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

# shellcheck source=./load-domain-env.sh
source "$REPO_ROOT/scripts/load-domain-env.sh"

LINUX_TEMPLATE_FILE="${LINUX_TEMPLATE_FILE:-$REPO_ROOT/linux/cloud-init.yaml.in}"
LINUX_OUTPUT_FILE="${LINUX_OUTPUT_FILE:-$REPO_ROOT/linux/cloud-init.yaml}"
MAC_TEMPLATE_FILE="${MAC_TEMPLATE_FILE:-$REPO_ROOT/macos/bootstrap-mac.sh.in}"
MAC_OUTPUT_FILE="${MAC_OUTPUT_FILE:-$REPO_ROOT/macos/bootstrap-mac.sh}"

NODE_ENV_FILE="${NODE_ENV_FILE:-$REPO_ROOT/node/env}"
CODEX_ENV_FILE="${CODEX_ENV_FILE:-$REPO_ROOT/codex/env}"
CLAUDE_ENV_FILE="${CLAUDE_ENV_FILE:-$REPO_ROOT/claude/env}"
BR_ENV_FILE="${BR_ENV_FILE:-$REPO_ROOT/br/env}"
PNPM_ENV_FILE="${PNPM_ENV_FILE:-$REPO_ROOT/pnpm/env}"
PLAYWRIGHT_ENV_FILE="${PLAYWRIGHT_ENV_FILE:-$REPO_ROOT/playwright/env}"
NOTIFY_ENV_FILE="${NOTIFY_ENV_FILE:-$REPO_ROOT/notify/env}"

CODEX_CONFIG_SOURCE="${CODEX_CONFIG_SOURCE:-$REPO_ROOT/codex/config.toml}"
CLAUDE_SETTINGS_SOURCE="${CLAUDE_SETTINGS_SOURCE:-$REPO_ROOT/claude/settings.json}"
NPMRC_SOURCE="${NPMRC_SOURCE:-$REPO_ROOT/npm/.npmrc}"
NVMRC_SOURCE="${NVMRC_SOURCE:-$REPO_ROOT/node/.nvmrc}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

file_b64_no_newline() {
  local file
  file="$1"
  base64 < "$file" | tr -d '\n'
}

validate_versions() {
  local required_vars value lower name
  required_vars=(
    NODE_MAJOR
    CODEX_VERSION
    CLAUDE_CODE_VERSION
    BR_VERSION
    PNPM_VERSION
    PLAYWRIGHT_MCP_VERSION
    PLAYWRIGHT_VERSION
    NOTIFY_ENABLED
    NOTIFY_MIN_INTERVAL_SEC
    NOTIFY_INCLUDE_SNIPPET
  )

  for name in "${required_vars[@]}"; do
    value="${!name:-}"
    if [[ -z "${value}" ]]; then
      echo "Domain config: missing required variable ${name}" >&2
      exit 1
    fi

    case "${name}" in
      NODE_MAJOR|CODEX_VERSION|CLAUDE_CODE_VERSION|BR_VERSION|PNPM_VERSION|PLAYWRIGHT_MCP_VERSION|PLAYWRIGHT_VERSION)
        lower="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
        if [[ "${lower}" == "latest" ]]; then
          echo "Domain config: ${name} must be pinned and cannot be 'latest'" >&2
          exit 1
        fi
        ;;
      NOTIFY_ENABLED|NOTIFY_INCLUDE_SNIPPET)
        lower="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
        case "${lower}" in
          0|1|true|false|yes|no|on|off) ;;
          *)
            echo "Domain config: ${name} must be boolean-like (0/1/true/false)" >&2
            exit 1
            ;;
        esac
        ;;
      NOTIFY_MIN_INTERVAL_SEC)
        if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
          echo "Domain config: ${name} must be a non-negative integer" >&2
          exit 1
        fi
        ;;
    esac
  done
}

validate_source_files() {
  local source_file
  for source_file in \
    "$LINUX_TEMPLATE_FILE" \
    "$MAC_TEMPLATE_FILE" \
    "$CODEX_CONFIG_SOURCE" \
    "$CLAUDE_SETTINGS_SOURCE" \
    "$NPMRC_SOURCE" \
    "$NVMRC_SOURCE"; do
    if [[ ! -f "$source_file" ]]; then
      echo "Required source file not found: $source_file" >&2
      exit 1
    fi
  done

}

render_versions() {
  local template_file output_file
  template_file="$1"
  output_file="$2"

  sed \
    -e "s/@NODE_MAJOR@/$(escape_sed_replacement "$NODE_MAJOR")/g" \
    -e "s/@CODEX_VERSION@/$(escape_sed_replacement "$CODEX_VERSION")/g" \
    -e "s/@CLAUDE_CODE_VERSION@/$(escape_sed_replacement "$CLAUDE_CODE_VERSION")/g" \
    -e "s/@BR_VERSION@/$(escape_sed_replacement "$BR_VERSION")/g" \
    -e "s/@PNPM_VERSION@/$(escape_sed_replacement "$PNPM_VERSION")/g" \
    -e "s/@PLAYWRIGHT_MCP_VERSION@/$(escape_sed_replacement "$PLAYWRIGHT_MCP_VERSION")/g" \
    -e "s/@PLAYWRIGHT_VERSION@/$(escape_sed_replacement "$PLAYWRIGHT_VERSION")/g" \
    -e "s/@NOTIFY_ENABLED@/$(escape_sed_replacement "$NOTIFY_ENABLED")/g" \
    -e "s/@NOTIFY_MIN_INTERVAL_SEC@/$(escape_sed_replacement "$NOTIFY_MIN_INTERVAL_SEC")/g" \
    -e "s/@NOTIFY_INCLUDE_SNIPPET@/$(escape_sed_replacement "$NOTIFY_INCLUDE_SNIPPET")/g" \
    -e "s/@CODEX_CONFIG_TOML_B64@/$(escape_sed_replacement "$CODEX_CONFIG_TOML_B64")/g" \
    -e "s/@CLAUDE_SETTINGS_JSON_B64@/$(escape_sed_replacement "$CLAUDE_SETTINGS_JSON_B64")/g" \
    -e "s/@NPMRC_B64@/$(escape_sed_replacement "$NPMRC_B64")/g" \
    -e "s/@NVMRC_B64@/$(escape_sed_replacement "$NVMRC_B64")/g" \
    "$template_file" > "$output_file"
}

assert_no_placeholders() {
  local file
  file="$1"
  if grep -nE '@[A-Z0-9_]+@' "$file" >/dev/null 2>&1; then
    echo "Unresolved placeholders found in $file" >&2
    grep -nE '@[A-Z0-9_]+@' "$file" >&2
    exit 1
  fi
}

assert_linux_placeholders_are_git_only() {
  local file unresolved
  file="$1"
  unresolved="$(grep -nE '@[A-Z0-9_]+@' "$file" || true)"

  if [[ -z "$unresolved" ]]; then
    return
  fi

  if printf '%s\n' "$unresolved" | grep -vE '@GIT_USER_NAME_B64@|@GIT_USER_EMAIL_B64@' >/dev/null 2>&1; then
    echo "Unexpected unresolved placeholders found in $file" >&2
    printf '%s\n' "$unresolved" | grep -vE '@GIT_USER_NAME_B64@|@GIT_USER_EMAIL_B64@' >&2
    exit 1
  fi
}

need_cmd sed
need_cmd grep
need_cmd tr
need_cmd chmod
need_cmd base64

carl_load_env_file "$NODE_ENV_FILE"
carl_load_env_file "$CODEX_ENV_FILE"
carl_load_env_file "$CLAUDE_ENV_FILE"
carl_load_env_file "$BR_ENV_FILE"
carl_load_env_file "$PNPM_ENV_FILE"
carl_load_env_file "$PLAYWRIGHT_ENV_FILE"
carl_load_env_file "$NOTIFY_ENV_FILE"

validate_versions
validate_source_files

CODEX_CONFIG_TOML_B64="$(file_b64_no_newline "$CODEX_CONFIG_SOURCE")"
CLAUDE_SETTINGS_JSON_B64="$(file_b64_no_newline "$CLAUDE_SETTINGS_SOURCE")"
NPMRC_B64="$(file_b64_no_newline "$NPMRC_SOURCE")"
NVMRC_B64="$(file_b64_no_newline "$NVMRC_SOURCE")"

render_versions "$LINUX_TEMPLATE_FILE" "$LINUX_OUTPUT_FILE"
render_versions "$MAC_TEMPLATE_FILE" "$MAC_OUTPUT_FILE"

chmod 0755 "$MAC_OUTPUT_FILE"

assert_linux_placeholders_are_git_only "$LINUX_OUTPUT_FILE"
assert_no_placeholders "$MAC_OUTPUT_FILE"

"$REPO_ROOT/macos/update-checksums.sh"

echo "Rendered bootstrap artifacts from domain env files:"
echo "  $LINUX_OUTPUT_FILE"
echo "  $MAC_OUTPUT_FILE"
