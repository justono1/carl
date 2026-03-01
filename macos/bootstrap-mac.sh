#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="2026-03-01-v4"
MARKER_FILE="${HOME}/.bootstrap_done"
TMP_BREWFILE=""

INSTALL_PNPM="${INSTALL_PNPM:-1}"
INSTALL_PLAYWRIGHT_MCP="${INSTALL_PLAYWRIGHT_MCP:-1}"
PLAYWRIGHT_BROWSERS="${PLAYWRIGHT_BROWSERS:-chromium}"
GIT_USER_NAME=""
GIT_USER_EMAIL=""

CODEX_VERSION="0.104.0"
BR_VERSION="0.1.7"
PNPM_VERSION="10.30.1"
PLAYWRIGHT_MCP_VERSION="0.0.68"
PLAYWRIGHT_VERSION="1.58.2"

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

ensure_rust_toolchain() {
  if command -v cargo >/dev/null 2>&1; then
    return
  fi

  log "Rust toolchain not found; installing rustup (minimal profile) for br source fallback."
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal

  if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
  fi

  command -v cargo >/dev/null 2>&1 || die "cargo was not found after rustup installation."
}

usage() {
  cat <<'USAGE'
Usage:
  bootstrap-mac.sh

Environment variables:
  INSTALL_PNPM              Set to 0 to skip pnpm npm-global install.
  INSTALL_PLAYWRIGHT_MCP    Set to 0 to skip @playwright/mcp npm-global install.
  PLAYWRIGHT_BROWSERS       Space-delimited browser list for playwright install (default: chromium).
  BOOTSTRAP_SOURCE_REF      Optional source metadata written to marker file.
USAGE
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    return
  fi

  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "This script takes no positional arguments."
      ;;
  esac
}

ensure_macos_arm64() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This bootstrap is only supported on macOS."
  [[ "$(uname -m)" == "arm64" ]] || die "This bootstrap only supports Apple Silicon (arm64)."
}

prompt_required_value() {
  local label current value
  label="$1"
  current="$2"

  while true; do
    if [[ -n "$current" ]]; then
      read -r -p "${label} [${current}]: " value
      value="${value:-$current}"
    else
      read -r -p "${label}: " value
    fi

    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi

    printf '[mac-bootstrap] ERROR: %s is required.\n' "${label}" >&2
  done
}

resolve_git_identity() {
  local default_name default_email

  if [[ ! -t 0 ]]; then
    die "Interactive terminal required to collect Git identity."
  fi

  default_name=""
  default_email=""
  if command -v git >/dev/null 2>&1; then
    default_name="$(git config --global --get user.name 2>/dev/null || true)"
    default_email="$(git config --global --get user.email 2>/dev/null || true)"
  fi

  log "Git identity is required."
  GIT_USER_NAME="$(prompt_required_value "Git user.name" "${default_name}")"
  GIT_USER_EMAIL="$(prompt_required_value "Git user.email" "${default_email}")"
}

configure_git_identity() {
  command -v git >/dev/null 2>&1 || die "git is required but was not found."
  git config --global user.name "${GIT_USER_NAME}"
  git config --global user.email "${GIT_USER_EMAIL}"
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

write_embedded_brewfile() {
  TMP_BREWFILE="$(mktemp "/tmp/carl.Brewfile.XXXXXX")"
  cat > "${TMP_BREWFILE}" <<'BREWFILE'
# Runtime/toolchain foundation
brew "node"
brew "python"

# Dev tooling and shell utilities
brew "jq"
brew "ripgrep"
brew "wget"
brew "rsync"
brew "cmake"
brew "ninja"
brew "pkg-config"
brew "bash"
brew "gnu-sed"
BREWFILE
}

brew_bundle_apply() {
  log "Applying embedded Homebrew package set."

  if brew bundle check --file="${TMP_BREWFILE}" >/dev/null 2>&1; then
    log "Homebrew package set already satisfied."
  else
    brew bundle install --file="${TMP_BREWFILE}"
  fi
}

npm_global_satisfied() {
  local pkg="$1"
  local version="$2"
  npm ls -g --depth=0 "${pkg}@${version}" >/dev/null 2>&1
}

install_npm_globals() {
  local npm_packages=()
  local codex_target playwright_target pnpm_target playwright_mcp_target

  codex_target="@openai/codex@${CODEX_VERSION}"
  playwright_target="playwright@${PLAYWRIGHT_VERSION}"
  pnpm_target="pnpm@${PNPM_VERSION}"
  playwright_mcp_target="@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}"

  if npm_global_satisfied "@openai/codex" "${CODEX_VERSION}"; then
    log "${codex_target} already satisfied; skipping."
  else
    npm_packages+=("${codex_target}")
  fi

  if npm_global_satisfied "playwright" "${PLAYWRIGHT_VERSION}"; then
    log "${playwright_target} already satisfied; skipping."
  else
    npm_packages+=("${playwright_target}")
  fi

  if [[ "${INSTALL_PNPM}" == "1" ]]; then
    if npm_global_satisfied "pnpm" "${PNPM_VERSION}"; then
      log "${pnpm_target} already satisfied; skipping."
    else
      npm_packages+=("${pnpm_target}")
    fi
  fi

  if [[ "${INSTALL_PLAYWRIGHT_MCP}" == "1" ]]; then
    if npm_global_satisfied "@playwright/mcp" "${PLAYWRIGHT_MCP_VERSION}"; then
      log "${playwright_mcp_target} already satisfied; skipping."
    else
      npm_packages+=("${playwright_mcp_target}")
    fi
  fi

  if [[ "${#npm_packages[@]}" -eq 0 ]]; then
    log "npm global package set already satisfied."
  else
    log "Installing npm global packages: ${npm_packages[*]}"
    npm install -g "${npm_packages[@]}"
  fi
}

install_br() {
  local existing_version br_tag release_api asset_url tmp_dir br_bin brew_prefix install_dir

  if ! command -v jq >/dev/null 2>&1; then
    die "jq is required to resolve beads release assets."
  fi

  if command -v br >/dev/null 2>&1; then
    existing_version="$(br --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+){2}' | head -n1 || true)"
    if [[ "${existing_version}" == "${BR_VERSION}" ]]; then
      log "br ${BR_VERSION} already available; skipping install."
      return
    fi
    log "br version mismatch (found: ${existing_version:-unknown}, target: ${BR_VERSION}); reinstalling."
  fi

  log "Installing br (${BR_VERSION})"
  br_tag="v${BR_VERSION}"
  release_api="https://api.github.com/repos/Dicklesworthstone/beads_rust/releases/tags/${br_tag}"
  asset_url="$(curl -fsSL "${release_api}" \
    | jq -r '.assets[]?.browser_download_url | select(test("br-.*((darwin|macos).*(arm64|aarch64)|(arm64|aarch64).*(darwin|macos))\\.tar\\.gz$"))' \
    | head -n1 || true)"

  brew_prefix="$(brew --prefix)"
  install_dir="${brew_prefix}/bin"

  if [[ -n "${asset_url}" ]]; then
    tmp_dir="$(mktemp -d)"
    curl -fsSL "${asset_url}" -o "${tmp_dir}/br.tar.gz"
    tar -xzf "${tmp_dir}/br.tar.gz" -C "${tmp_dir}"
    br_bin="$(find "${tmp_dir}" -type f -name br | head -n1 || true)"
    [[ -n "${br_bin}" ]] || die "Downloaded br archive did not contain a br binary."
    install -m 0755 "${br_bin}" "${install_dir}/br"
    rm -rf "${tmp_dir}"
  else
    log "No macOS arm64 release tarball found for ${br_tag}; falling back to source build."
    ensure_rust_toolchain
    cargo install --git https://github.com/Dicklesworthstone/beads_rust.git --tag "${br_tag}" --bin br --force
    [[ -x "${HOME}/.cargo/bin/br" ]] || die "cargo install completed but ~/.cargo/bin/br was not found."
    install -m 0755 "${HOME}/.cargo/bin/br" "${install_dir}/br"
  fi

  br --version
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
  command -v br >/dev/null 2>&1 || die "br not found on PATH."

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
  br --version
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
  local completed_at package_set_sha source_ref pnpm_marker playwright_mcp_marker
  completed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  package_set_sha="$(shasum -a 256 "${TMP_BREWFILE}" | awk '{print $1}')"
  source_ref="${BOOTSTRAP_SOURCE_REF:-unknown}"
  pnpm_marker="${PNPM_VERSION}"
  playwright_mcp_marker="${PLAYWRIGHT_MCP_VERSION}"

  if [[ "${INSTALL_PNPM}" != "1" ]]; then
    pnpm_marker="skipped"
  fi

  if [[ "${INSTALL_PLAYWRIGHT_MCP}" != "1" ]]; then
    playwright_mcp_marker="skipped"
  fi

  cat > "${MARKER_FILE}" <<MARKER
bootstrap_version=${SCRIPT_VERSION}
completed_at=${completed_at}
source_ref=${source_ref}
brew_profile=embedded-default
brew_profile_sha256=${package_set_sha}
codex_version=${CODEX_VERSION}
br_version=${BR_VERSION}
pnpm_version=${pnpm_marker}
playwright_mcp_version=${playwright_mcp_marker}
playwright_version=${PLAYWRIGHT_VERSION}
playwright_browsers=${PLAYWRIGHT_BROWSERS}
MARKER
}

main() {
  parse_args "$@"
  ensure_macos_arm64
  resolve_git_identity
  ensure_xcode_clt
  ensure_homebrew
  load_brew_env
  configure_git_identity
  write_embedded_brewfile
  brew_bundle_apply
  install_npm_globals
  install_br
  install_playwright_browsers
  verify_versions
  verify_playwright_browser_cache
  write_marker

  log "Bootstrap complete. Marker written to ${MARKER_FILE}."
  log "If node/npm/codex are not found in your current shell, run: eval \"$(/opt/homebrew/bin/brew shellenv)\""
}

main "$@"
