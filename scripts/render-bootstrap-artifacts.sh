#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

VERSIONS_FILE="${VERSIONS_FILE:-$REPO_ROOT/.env}"
LINUX_TEMPLATE_FILE="${LINUX_TEMPLATE_FILE:-$REPO_ROOT/linux/cloud-init.yaml.in}"
LINUX_OUTPUT_FILE="${LINUX_OUTPUT_FILE:-$REPO_ROOT/linux/cloud-init.yaml}"
MAC_TEMPLATE_FILE="${MAC_TEMPLATE_FILE:-$REPO_ROOT/macos/bootstrap-mac.sh.in}"
MAC_OUTPUT_FILE="${MAC_OUTPUT_FILE:-$REPO_ROOT/macos/bootstrap-mac.sh}"

DEFAULT_NODE_MAJOR="24"
DEFAULT_CODEX_VERSION="0.104.0"
DEFAULT_CLAUDE_CODE_VERSION="stable"
DEFAULT_BR_VERSION="0.1.12"
DEFAULT_PNPM_VERSION="10.30.1"
DEFAULT_PLAYWRIGHT_MCP_VERSION="0.0.68"
DEFAULT_PLAYWRIGHT_VERSION="1.58.2"
DEFAULT_NOTIFY_ENABLED="1"
DEFAULT_NOTIFY_MIN_INTERVAL_SEC="120"
DEFAULT_NOTIFY_INCLUDE_SNIPPET="0"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

validate_versions() {
  local source_label required_vars value lower
  source_label="$1"
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
      echo "${source_label}: missing required variable ${name}" >&2
      exit 1
    fi
    case "${name}" in
      NODE_MAJOR|CODEX_VERSION|CLAUDE_CODE_VERSION|BR_VERSION|PNPM_VERSION|PLAYWRIGHT_MCP_VERSION|PLAYWRIGHT_VERSION)
        lower="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
        if [[ "${lower}" == "latest" ]]; then
          echo "${source_label}: ${name} must be pinned and cannot be 'latest'" >&2
          exit 1
        fi
        ;;
      NOTIFY_ENABLED|NOTIFY_INCLUDE_SNIPPET)
        lower="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
        case "${lower}" in
          0|1|true|false|yes|no|on|off) ;;
          *)
            echo "${source_label}: ${name} must be boolean-like (0/1/true/false)" >&2
            exit 1
            ;;
        esac
        ;;
      NOTIFY_MIN_INTERVAL_SEC)
        if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
          echo "${source_label}: ${name} must be a non-negative integer" >&2
          exit 1
        fi
        ;;
    esac
  done
}

load_default_versions() {
  NODE_MAJOR="$DEFAULT_NODE_MAJOR"
  CODEX_VERSION="$DEFAULT_CODEX_VERSION"
  CLAUDE_CODE_VERSION="$DEFAULT_CLAUDE_CODE_VERSION"
  BR_VERSION="$DEFAULT_BR_VERSION"
  PNPM_VERSION="$DEFAULT_PNPM_VERSION"
  PLAYWRIGHT_MCP_VERSION="$DEFAULT_PLAYWRIGHT_MCP_VERSION"
  PLAYWRIGHT_VERSION="$DEFAULT_PLAYWRIGHT_VERSION"
  NOTIFY_ENABLED="$DEFAULT_NOTIFY_ENABLED"
  NOTIFY_MIN_INTERVAL_SEC="$DEFAULT_NOTIFY_MIN_INTERVAL_SEC"
  NOTIFY_INCLUDE_SNIPPET="$DEFAULT_NOTIFY_INCLUDE_SNIPPET"
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
    "$template_file" > "$output_file"
}

assert_no_placeholders() {
  local file="$1"
  if grep -nE '@[A-Z0-9_]+@' "$file" >/dev/null 2>&1; then
    echo "Unresolved placeholders found in $file" >&2
    grep -nE '@[A-Z0-9_]+@' "$file" >&2
    exit 1
  fi
}

assert_linux_placeholders_are_git_only() {
  local file="$1"
  local unresolved
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

if [[ ! -f "$LINUX_TEMPLATE_FILE" ]]; then
  echo "Linux template file not found: $LINUX_TEMPLATE_FILE" >&2
  exit 1
fi
if [[ ! -f "$MAC_TEMPLATE_FILE" ]]; then
  echo "macOS template file not found: $MAC_TEMPLATE_FILE" >&2
  exit 1
fi

if [[ -f "$VERSIONS_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$VERSIONS_FILE"
  set +a
  validate_versions "$VERSIONS_FILE"
else
  echo "Versions file not found; using built-in pinned defaults: $VERSIONS_FILE" >&2
  load_default_versions
  validate_versions "built-in defaults"
fi

render_versions "$LINUX_TEMPLATE_FILE" "$LINUX_OUTPUT_FILE"
render_versions "$MAC_TEMPLATE_FILE" "$MAC_OUTPUT_FILE"

chmod 0755 "$MAC_OUTPUT_FILE"

assert_linux_placeholders_are_git_only "$LINUX_OUTPUT_FILE"
assert_no_placeholders "$MAC_OUTPUT_FILE"

"$REPO_ROOT/macos/update-checksums.sh"

echo "Rendered bootstrap artifacts from ${VERSIONS_FILE}:"
echo "  ${LINUX_OUTPUT_FILE}"
echo "  ${MAC_OUTPUT_FILE}"
