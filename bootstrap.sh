#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="2026-05-30-v1"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
MARKER_FILE="${HOME}/.bootstrap_done"
TMP_BREWFILE=""

PLAYWRIGHT_BROWSERS="${PLAYWRIGHT_BROWSERS:-chromium}"
GIT_USER_NAME=""
GIT_USER_EMAIL=""

log() {
  printf '[bootstrap] %s\n' "$*"
}

die() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_BREWFILE}" && -f "${TMP_BREWFILE}" ]]; then
    rm -f "${TMP_BREWFILE}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'USAGE'
Usage:
  bootstrap.sh

Bootstraps or updates this Mac for use as an AI coding agent runtime.
Run from a checkout of this repository. Safe to re-run; every step is idempotent.

Environment overrides:
  PLAYWRIGHT_BROWSERS   Space-delimited browser list (default: chromium).
  BOOTSTRAP_SOURCE_REF  Optional source metadata written to marker file.
USAGE
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    return
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) die "This script takes no positional arguments." ;;
  esac
}

ensure_macos_arm64() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This bootstrap only supports macOS."
  [[ "$(uname -m)" == "arm64" ]] || die "This bootstrap only supports Apple Silicon (arm64)."
}

load_domain_env() {
  local domain_envs=(
    node/env
    npm/env
    playwright/env
    codex/env
    claude/env
    br/env
    bv/env
    shell/env
  )
  local f
  for f in "${domain_envs[@]}"; do
    [[ -f "${REPO_ROOT}/${f}" ]] || die "Missing required env file: ${f}"
    set -a
    # shellcheck disable=SC1090
    source "${REPO_ROOT}/${f}"
    set +a
  done

  local pinned=(
    NODE_MAJOR
    CODEX_VERSION
    CLAUDE_CODE_VERSION
    BR_VERSION
    BV_VERSION
    PLAYWRIGHT_MCP_VERSION
    PLAYWRIGHT_VERSION
  )
  local var val lower
  for var in "${pinned[@]}"; do
    val="${!var:-}"
    [[ -n "${val}" ]] || die "Missing required version pin: ${var}"
    lower="$(printf '%s' "${val}" | tr '[:upper:]' '[:lower:]')"
    # CLAUDE_CODE_VERSION accepts 'stable' (installer keyword), all others must be exact pins.
    if [[ "${lower}" == "latest" ]]; then
      die "${var} must be pinned, not 'latest'."
    fi
    if [[ "${var}" != "CLAUDE_CODE_VERSION" && "${lower}" == "stable" ]]; then
      die "${var} must be pinned, not 'stable'."
    fi
  done
}

prompt_required_value() {
  local label current value
  label="$1"
  current="$2"

  while true; do
    if [[ -n "${current}" ]]; then
      read -r -p "${label} [${current}]: " value
      value="${value:-$current}"
    else
      read -r -p "${label}: " value
    fi
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    printf '[bootstrap] ERROR: %s is required.\n' "${label}" >&2
  done
}

resolve_git_identity() {
  local default_name default_email
  default_name=""
  default_email=""

  if command -v git >/dev/null 2>&1; then
    default_name="$(git config --global --get user.name 2>/dev/null || true)"
    default_email="$(git config --global --get user.email 2>/dev/null || true)"
  fi

  if [[ -n "${default_name}" && -n "${default_email}" ]]; then
    GIT_USER_NAME="${default_name}"
    GIT_USER_EMAIL="${default_email}"
    log "Using existing git identity: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    die "Interactive terminal required to collect Git identity (no existing config found)."
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

ensure_ssh_keypair() {
  local ssh_dir private_key public_key key_comment host_name
  ssh_dir="${HOME}/.ssh"
  private_key="${ssh_dir}/id_ed25519"
  public_key="${private_key}.pub"

  command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen is required but was not found."

  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"

  if [[ -n "${GIT_USER_EMAIL}" ]]; then
    key_comment="${GIT_USER_EMAIL}"
  else
    host_name="$(scutil --get LocalHostName 2>/dev/null || hostname 2>/dev/null || echo "mac")"
    key_comment="$(whoami)@${host_name}"
  fi

  if [[ -f "${private_key}" ]]; then
    log "SSH key already exists at ${private_key}; preserving."
  else
    log "Generating SSH key at ${private_key}"
    ssh-keygen -t ed25519 -a 64 -f "${private_key}" -N "" -C "${key_comment}"
  fi

  if [[ ! -f "${public_key}" ]]; then
    log "Public key missing at ${public_key}; regenerating from private key."
    ssh-keygen -y -f "${private_key}" > "${public_key}"
  fi

  chmod 600 "${private_key}"
  chmod 644 "${public_key}"
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

ensure_local_bin_path() {
  local export_line profile
  export_line='export PATH="$HOME/.local/bin:$PATH"'
  export PATH="${HOME}/.local/bin:${PATH}"

  for profile in "${HOME}/.zprofile" "${HOME}/.zshrc" "${HOME}/.bash_profile"; do
    if [[ -f "${profile}" ]]; then
      if ! grep -Fqx "${export_line}" "${profile}"; then
        printf '\n%s\n' "${export_line}" >> "${profile}"
      fi
    else
      printf '%s\n' "${export_line}" > "${profile}"
    fi
  done
}

install_baseline_config_files() {
  install -d -m 0755 "${HOME}/.codex" "${HOME}/.claude" "${HOME}/.config/carl/zsh"
  install -m 0644 "${REPO_ROOT}/codex/config.toml"      "${HOME}/.codex/config.toml"
  install -m 0644 "${REPO_ROOT}/claude/settings.json"   "${HOME}/.claude/settings.json"
  install -m 0644 "${REPO_ROOT}/claude/keybindings.json" "${HOME}/.claude/keybindings.json"
  install -m 0644 "${REPO_ROOT}/claude/mcp.json"        "${HOME}/.claude/mcp.json"
  install -m 0644 "${REPO_ROOT}/npm/.npmrc"             "${HOME}/.npmrc"
  install -m 0644 "${REPO_ROOT}/node/.nvmrc"            "${HOME}/.nvmrc"
  install -m 0644 "${REPO_ROOT}/shell/core.zsh"         "${HOME}/.config/carl/zsh/core.zsh"

  jq -e . "${HOME}/.claude/settings.json"    >/dev/null || die "Claude settings.json is not valid JSON."
  jq -e . "${HOME}/.claude/keybindings.json" >/dev/null || die "Claude keybindings.json is not valid JSON."
  jq -e . "${HOME}/.claude/mcp.json"         >/dev/null || die "Claude mcp.json is not valid JSON."
}

ensure_carl_zshrc_source_block() {
  local zshrc source_line begin_marker end_marker tmp_file
  zshrc="${HOME}/.zshrc"
  source_line='[[ -f "$HOME/.config/carl/zsh/core.zsh" ]] && source "$HOME/.config/carl/zsh/core.zsh"'
  begin_marker='# >>> CARL ZSH CORE >>>'
  end_marker='# <<< CARL ZSH CORE <<<'

  touch "${zshrc}"
  tmp_file="$(mktemp)"

  awk \
    -v begin_marker="${begin_marker}" \
    -v end_marker="${end_marker}" \
    -v source_line="${source_line}" \
    '
      BEGIN { in_block = 0; block_written = 0 }
      $0 == begin_marker {
        if (block_written == 0) {
          print begin_marker
          print source_line
          print end_marker
          block_written = 1
        }
        in_block = 1
        next
      }
      $0 == end_marker { in_block = 0; next }
      { if (!in_block) print }
      END {
        if (block_written == 0) {
          if (NR > 0) print ""
          print begin_marker
          print source_line
          print end_marker
        }
      }
    ' "${zshrc}" > "${tmp_file}"

  mv "${tmp_file}" "${zshrc}"
}

ensure_zsh_as_default_shell() {
  local zsh_bin current_shell
  zsh_bin="$(command -v zsh || true)"
  [[ -n "${zsh_bin}" ]] || die "zsh is required but was not found."

  current_shell="$(dscl . -read "/Users/${USER}" UserShell 2>/dev/null | awk '{print $2}' || true)"
  if [[ "${current_shell}" == "${zsh_bin}" ]]; then
    return 0
  fi

  if chsh -s "${zsh_bin}" "${USER}" >/dev/null 2>&1; then
    log "Set default shell to ${zsh_bin} for ${USER}."
  else
    log "Warning: failed to set default shell to ${zsh_bin} for ${USER}."
  fi
}

write_embedded_brewfile() {
  TMP_BREWFILE="$(mktemp "/tmp/carl.Brewfile.XXXXXX")"
  cat > "${TMP_BREWFILE}" <<BREWFILE
# Runtime/toolchain foundation
brew "node@${NODE_MAJOR}"
brew "python"

# Dev tooling and shell utilities
brew "jq"
brew "ripgrep"
brew "rsync"
brew "tmux"
brew "gnu-sed"

# Editors
cask "visual-studio-code"
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

link_pinned_node() {
  # node@MAJOR is keg-only; ensure it's on PATH via brew link.
  if brew list --versions "node@${NODE_MAJOR}" >/dev/null 2>&1; then
    brew link --overwrite --force "node@${NODE_MAJOR}" >/dev/null 2>&1 || true
  fi
}

npm_global_satisfied() {
  local pkg="$1"
  local version="$2"
  npm ls -g --depth=0 "${pkg}@${version}" >/dev/null 2>&1
}

install_npm_globals() {
  local npm_packages=()
  local codex_target playwright_target playwright_mcp_target

  codex_target="@openai/codex@${CODEX_VERSION}"
  playwright_target="playwright@${PLAYWRIGHT_VERSION}"
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

  if npm_global_satisfied "@playwright/mcp" "${PLAYWRIGHT_MCP_VERSION}"; then
    log "${playwright_mcp_target} already satisfied; skipping."
  else
    npm_packages+=("${playwright_mcp_target}")
  fi

  if [[ "${#npm_packages[@]}" -eq 0 ]]; then
    log "npm global package set already satisfied."
  else
    log "Installing npm global packages: ${npm_packages[*]}"
    npm install -g "${npm_packages[@]}"
  fi
}

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

ensure_brew_bin_symlink() {
  local src_path link_name brew_prefix dst_path
  src_path="$1"
  link_name="$2"
  [[ -x "${src_path}" ]] || return 0
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  [[ -n "${brew_prefix}" ]] || return 0
  dst_path="${brew_prefix}/bin/${link_name}"
  if [[ -e "${dst_path}" && ! -L "${dst_path}" ]]; then
    return 0
  fi
  ln -sfn "${src_path}" "${dst_path}"
}

ensure_standard_cli_symlinks() {
  ensure_brew_bin_symlink "${HOME}/.local/bin/claude" "claude"
}

ensure_claude_on_path() {
  ensure_standard_cli_symlinks
  if command -v claude >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "${HOME}/.local/bin/claude" ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
  command -v claude >/dev/null 2>&1
}

claude_native_satisfied() {
  local installed
  ensure_standard_cli_symlinks
  if ! ensure_claude_on_path; then
    return 1
  fi
  if [[ "${CLAUDE_CODE_VERSION}" == "stable" || "${CLAUDE_CODE_VERSION}" == "latest" ]]; then
    return 0
  fi
  installed="$(claude --version 2>/dev/null || true)"
  [[ "${installed}" == *"${CLAUDE_CODE_VERSION}"* ]]
}

install_claude_code() {
  if claude_native_satisfied; then
    log "Claude Code (${CLAUDE_CODE_VERSION}) already satisfied; skipping."
    return
  fi
  log "Installing Claude Code via native installer (${CLAUDE_CODE_VERSION})"
  curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}"
  ensure_standard_cli_symlinks
  ensure_claude_on_path || die "claude not found on PATH after install."
}

ensure_bd_shim() {
  local br_path bd_path br_dir
  br_path="$(command -v br || true)"
  [[ -n "${br_path}" ]] || die "br not found on PATH; cannot create bd compatibility shim."
  bd_path="$(command -v bd || true)"
  if [[ -n "${bd_path}" ]]; then
    log "bd already exists at ${bd_path}; preserving existing command."
    return
  fi
  br_dir="$(dirname "${br_path}")"
  ln -sfn "${br_path}" "${br_dir}/bd"
  log "Created bd compatibility shim at ${br_dir}/bd -> ${br_path}"
  bd --version
}

install_br() {
  local existing_version br_tag release_api asset_url tmp_dir br_bin brew_prefix install_dir
  command -v jq >/dev/null 2>&1 || die "jq is required to resolve beads release assets."

  if command -v br >/dev/null 2>&1; then
    existing_version="$(br --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+){2}' | head -n1 || true)"
    if [[ "${existing_version}" == "${BR_VERSION}" ]]; then
      log "br ${BR_VERSION} already available; skipping install."
      ensure_bd_shim
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
  ensure_bd_shim
}

install_bv() {
  local existing_version bv_tag release_api asset_url tmp_dir bv_bin brew_prefix install_dir
  command -v jq >/dev/null 2>&1 || die "jq is required to resolve beads viewer release assets."

  if command -v bv >/dev/null 2>&1; then
    existing_version="$(bv --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+){2}' | head -n1 || true)"
    if [[ "${existing_version}" == "${BV_VERSION}" ]]; then
      log "bv ${BV_VERSION} already available; skipping install."
      return
    fi
    log "bv version mismatch (found: ${existing_version:-unknown}, target: ${BV_VERSION}); reinstalling."
  fi

  log "Installing bv (${BV_VERSION})"
  bv_tag="v${BV_VERSION}"
  release_api="https://api.github.com/repos/Dicklesworthstone/beads_viewer/releases/tags/${bv_tag}"
  asset_url="$(curl -fsSL "${release_api}" \
    | jq -r '.assets[]?.browser_download_url | select(test("bv"; "i") and test("(darwin|macos)"; "i") and test("(arm64|aarch64)"; "i") and test("\\.(tar\\.gz|tgz)$"; "i"))' \
    | head -n1 || true)"

  [[ -n "${asset_url}" ]] || die "No macOS arm64 release tarball found for ${bv_tag}."

  brew_prefix="$(brew --prefix)"
  install_dir="${brew_prefix}/bin"

  tmp_dir="$(mktemp -d)"
  curl -fsSL "${asset_url}" -o "${tmp_dir}/bv.tar.gz"
  tar -xzf "${tmp_dir}/bv.tar.gz" -C "${tmp_dir}"
  bv_bin="$(find "${tmp_dir}" -type f -name bv | head -n1 || true)"
  [[ -n "${bv_bin}" ]] || die "Downloaded bv archive did not contain a bv binary."
  install -m 0755 "${bv_bin}" "${install_dir}/bv"
  rm -rf "${tmp_dir}"
  bv --version
}

install_playwright_browsers() {
  log "Installing Playwright browser binaries: ${PLAYWRIGHT_BROWSERS}"
  # shellcheck disable=SC2086
  playwright install ${PLAYWRIGHT_BROWSERS}
}

verify_versions() {
  log "Verifying toolchain availability."
  command -v brew       >/dev/null 2>&1 || die "brew not found on PATH."
  command -v node       >/dev/null 2>&1 || die "node not found on PATH."
  command -v npm        >/dev/null 2>&1 || die "npm not found on PATH."
  command -v tmux       >/dev/null 2>&1 || die "tmux not found on PATH."
  command -v codex      >/dev/null 2>&1 || die "codex not found on PATH."
  command -v claude     >/dev/null 2>&1 || die "claude not found on PATH."
  command -v code       >/dev/null 2>&1 || die "code not found on PATH."
  command -v playwright >/dev/null 2>&1 || die "playwright not found on PATH."
  command -v br         >/dev/null 2>&1 || die "br not found on PATH."
  command -v bv         >/dev/null 2>&1 || die "bv not found on PATH."

  brew --version
  node --version
  npm --version
  tmux -V
  codex --version
  claude --version
  code --version
  playwright --version
  br --version
  bv --version
}

verify_playwright_browser_cache() {
  local pw_cache
  pw_cache="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/Library/Caches/ms-playwright}"
  [[ -d "${pw_cache}" ]] || die "Playwright cache directory not found: ${pw_cache}"

  if [[ " ${PLAYWRIGHT_BROWSERS} " == *" chromium "* ]]; then
    find "${pw_cache}" -maxdepth 1 -type d -name 'chromium-*' | grep -q '.' \
      || die "Chromium browser cache was not detected under ${pw_cache}."
  elif [[ " ${PLAYWRIGHT_BROWSERS} " == *" firefox "* ]]; then
    find "${pw_cache}" -maxdepth 1 -type d -name 'firefox-*' | grep -q '.' \
      || die "Firefox browser cache was not detected under ${pw_cache}."
  elif [[ " ${PLAYWRIGHT_BROWSERS} " == *" webkit "* ]]; then
    find "${pw_cache}" -maxdepth 1 -type d -name 'webkit-*' | grep -q '.' \
      || die "WebKit browser cache was not detected under ${pw_cache}."
  else
    find "${pw_cache}" -maxdepth 1 -type d | tail -n +2 | grep -q '.' \
      || die "No Playwright browser cache entries detected under ${pw_cache}."
  fi
}

write_marker() {
  local completed_at package_set_sha source_ref
  completed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  package_set_sha="$(shasum -a 256 "${TMP_BREWFILE}" | awk '{print $1}')"
  source_ref="${BOOTSTRAP_SOURCE_REF:-$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)}"

  cat > "${MARKER_FILE}" <<MARKER
bootstrap_version=${SCRIPT_VERSION}
completed_at=${completed_at}
source_ref=${source_ref}
brew_profile_sha256=${package_set_sha}
node_major=${NODE_MAJOR}
codex_version=${CODEX_VERSION}
claude_code_target=${CLAUDE_CODE_VERSION}
br_version=${BR_VERSION}
bv_version=${BV_VERSION}
playwright_mcp_version=${PLAYWRIGHT_MCP_VERSION}
playwright_version=${PLAYWRIGHT_VERSION}
playwright_browsers=${PLAYWRIGHT_BROWSERS}
MARKER
}

main() {
  parse_args "$@"
  ensure_macos_arm64
  load_domain_env
  resolve_git_identity
  ensure_xcode_clt
  ensure_homebrew
  load_brew_env
  ensure_local_bin_path
  configure_git_identity
  ensure_ssh_keypair
  write_embedded_brewfile
  brew_bundle_apply
  link_pinned_node
  install_baseline_config_files
  ensure_carl_zshrc_source_block
  ensure_zsh_as_default_shell
  install_npm_globals
  install_claude_code
  install_br
  install_bv
  install_playwright_browsers
  verify_versions
  verify_playwright_browser_cache
  write_marker

  log "Bootstrap complete. Marker written to ${MARKER_FILE}."
  log "If tools are not found in your current shell, run:"
  log '  eval "$(/opt/homebrew/bin/brew shellenv)"'
  log '  export PATH="$HOME/.local/bin:$PATH"'
  log "  hash -r"
}

main "$@"
