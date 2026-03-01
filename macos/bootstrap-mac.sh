#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="2026-03-01-v1"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
MARKER_FILE="${HOME}/.bootstrap_done"

BREWFILE_PATH=""
TMP_BREWFILE=""

INSTALL_PNPM="${INSTALL_PNPM:-1}"
INSTALL_PLAYWRIGHT_MCP="${INSTALL_PLAYWRIGHT_MCP:-1}"
PLAYWRIGHT_BROWSERS="${PLAYWRIGHT_BROWSERS:-chromium}"

log() {
  printf '[mac-bootstrap] %s\n' "$*"
}

die() {
  printf '[mac-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_BREWFILE}" && -f "${TMP_BREWFILE}" ]]; then
    rm -f "${TMP_BREWFILE}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage:
  bootstrap-mac.sh [--brewfile /path/to/Brewfile]

Environment variables:
  CARL_BREWFILE_URL         Optional URL to download Brewfile if --brewfile is not set.
  INSTALL_PNPM              Set to 0 to skip pnpm npm-global install.
  INSTALL_PLAYWRIGHT_MCP    Set to 0 to skip @playwright/mcp npm-global install.
  PLAYWRIGHT_BROWSERS       Space-delimited browser list for playwright install (default: chromium).
  BOOTSTRAP_SOURCE_REF      Optional source metadata written to marker file.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --brewfile)
        [[ $# -ge 2 ]] || die "--brewfile requires a path"
        BREWFILE_PATH="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

ensure_macos_arm64() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This bootstrap is only supported on macOS."
  [[ "$(uname -m)" == "arm64" ]] || die "This bootstrap only supports Apple Silicon (arm64)."
}

ensure_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools already installed."
    return
  fi

  log "Xcode Command Line Tools not found; launching installer."
  xcode-select --install >/dev/null 2>&1 || true
  die "Complete the Xcode Command Line Tools install, then rerun this script."
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed."
    return
  fi

  log "Installing Homebrew."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

load_brew_env() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif command -v brew >/dev/null 2>&1; then
    eval "$(brew shellenv)"
  else
    die "Homebrew is not available on PATH after installation."
  fi
}

resolve_brewfile() {
  if [[ -n "${BREWFILE_PATH}" ]]; then
    [[ -f "${BREWFILE_PATH}" ]] || die "Brewfile not found: ${BREWFILE_PATH}"
    return
  fi

  if [[ -f "${SCRIPT_DIR}/Brewfile" ]]; then
    BREWFILE_PATH="${SCRIPT_DIR}/Brewfile"
    return
  fi

  if [[ -n "${CARL_BREWFILE_URL:-}" ]]; then
    TMP_BREWFILE="$(mktemp "/tmp/carl.Brewfile.XXXXXX")"
    log "Downloading Brewfile from CARL_BREWFILE_URL."
    curl -fsSL "${CARL_BREWFILE_URL}" -o "${TMP_BREWFILE}"
    BREWFILE_PATH="${TMP_BREWFILE}"
    return
  fi

  die "No Brewfile found. Pass --brewfile or set CARL_BREWFILE_URL."
}

brew_bundle_apply() {
  log "Applying Homebrew bundle: ${BREWFILE_PATH}"
  brew tap homebrew/bundle >/dev/null

  if brew bundle check --file="${BREWFILE_PATH}" >/dev/null 2>&1; then
    log "Brewfile already satisfied."
  else
    brew bundle install --file="${BREWFILE_PATH}" --no-lock
  fi
}

install_npm_globals() {
  local npm_packages=()

  if command -v codex >/dev/null 2>&1; then
    log "codex already available; skipping npm global install."
  else
    npm_packages+=("@openai/codex@latest")
  fi

  if command -v playwright >/dev/null 2>&1; then
    log "playwright already available; skipping npm global install."
  else
    npm_packages+=("playwright@latest")
  fi

  if [[ "${INSTALL_PNPM}" == "1" ]]; then
    if command -v pnpm >/dev/null 2>&1; then
      log "pnpm already available; skipping npm global install."
    else
      npm_packages+=("pnpm@latest")
    fi
  fi

  if [[ "${INSTALL_PLAYWRIGHT_MCP}" == "1" ]]; then
    if npm ls -g --depth=0 "@playwright/mcp" >/dev/null 2>&1; then
      log "@playwright/mcp already installed globally; skipping."
    else
      npm_packages+=("@playwright/mcp@latest")
    fi
  fi

  if [[ "${#npm_packages[@]}" -eq 0 ]]; then
    log "npm global package set already satisfied."
  else
    log "Installing npm global packages: ${npm_packages[*]}"
    npm install -g "${npm_packages[@]}"
  fi
}

install_playwright_browsers() {
  log "Installing Playwright browser binaries: ${PLAYWRIGHT_BROWSERS}"
  # shellcheck disable=SC2086
  playwright install ${PLAYWRIGHT_BROWSERS}
}

verify_versions() {
  log "Verifying toolchain availability."

  command -v brew >/dev/null 2>&1 || die "brew not found on PATH."
  command -v node >/dev/null 2>&1 || die "node not found on PATH."
  command -v npm >/dev/null 2>&1 || die "npm not found on PATH."
  command -v codex >/dev/null 2>&1 || die "codex not found on PATH."
  command -v playwright >/dev/null 2>&1 || die "playwright not found on PATH."

  if [[ "${INSTALL_PNPM}" == "1" ]]; then
    command -v pnpm >/dev/null 2>&1 || die "pnpm not found on PATH."
  fi

  brew --version
  node --version
  npm --version

  if [[ "${INSTALL_PNPM}" == "1" ]]; then
    pnpm --version
  fi

  codex --version
  playwright --version
}

verify_playwright_browser_cache() {
  local pw_cache
  pw_cache="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/Library/Caches/ms-playwright}"

  [[ -d "${pw_cache}" ]] || die "Playwright cache directory not found: ${pw_cache}"

  if [[ " ${PLAYWRIGHT_BROWSERS} " == *" chromium "* ]]; then
    if ! find "${pw_cache}" -maxdepth 1 -type d -name 'chromium-*' | grep -q '.'; then
      die "Chromium browser cache was not detected under ${pw_cache}."
    fi
  elif [[ " ${PLAYWRIGHT_BROWSERS} " == *" firefox "* ]]; then
    if ! find "${pw_cache}" -maxdepth 1 -type d -name 'firefox-*' | grep -q '.'; then
      die "Firefox browser cache was not detected under ${pw_cache}."
    fi
  elif [[ " ${PLAYWRIGHT_BROWSERS} " == *" webkit "* ]]; then
    if ! find "${pw_cache}" -maxdepth 1 -type d -name 'webkit-*' | grep -q '.'; then
      die "WebKit browser cache was not detected under ${pw_cache}."
    fi
  else
    if ! find "${pw_cache}" -maxdepth 1 -type d | tail -n +2 | grep -q '.'; then
      die "No Playwright browser cache entries detected under ${pw_cache}."
    fi
  fi
}

write_marker() {
  local completed_at brewfile_sha source_ref
  completed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  brewfile_sha="$(shasum -a 256 "${BREWFILE_PATH}" | awk '{print $1}')"
  source_ref="${BOOTSTRAP_SOURCE_REF:-unknown}"

  cat > "${MARKER_FILE}" <<EOF
bootstrap_version=${SCRIPT_VERSION}
completed_at=${completed_at}
source_ref=${source_ref}
brewfile_path=${BREWFILE_PATH}
brewfile_sha256=${brewfile_sha}
EOF
}

main() {
  parse_args "$@"
  ensure_macos_arm64
  ensure_xcode_clt
  ensure_homebrew
  load_brew_env
  resolve_brewfile
  brew_bundle_apply
  install_npm_globals
  install_playwright_browsers
  verify_versions
  verify_playwright_browser_cache
  write_marker

  log "Bootstrap complete. Marker written to ${MARKER_FILE}."
}

main "$@"
