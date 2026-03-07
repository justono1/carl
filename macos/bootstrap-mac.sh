#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="2026-03-01-v5"
MARKER_FILE="${HOME}/.bootstrap_done"
TMP_BREWFILE=""

INSTALL_PNPM="${INSTALL_PNPM:-1}"
INSTALL_PLAYWRIGHT_MCP="${INSTALL_PLAYWRIGHT_MCP:-1}"
PLAYWRIGHT_BROWSERS="${PLAYWRIGHT_BROWSERS:-chromium}"
GIT_USER_NAME=""
GIT_USER_EMAIL=""

CODEX_VERSION="0.110.0"
CLAUDE_CODE_VERSION="stable"
BR_VERSION="0.1.7"
PNPM_VERSION="10.30.1"
PLAYWRIGHT_MCP_VERSION="0.0.68"
PLAYWRIGHT_VERSION="1.58.2"
NOTIFY_ENABLED_DEFAULT="0"
NOTIFY_MIN_INTERVAL_SEC_DEFAULT="120"
NOTIFY_INCLUDE_SNIPPET_DEFAULT="1"
CARL_NOTIFY_BIN="/usr/local/bin/carl-notify"
CODEX_CONFIG_TOML_B64="bW9kZWwgPSAiZ3B0LTUuNCIKbW9kZWxfcHJvdmlkZXIgPSAib3BlbmFpIgoKIyBBbGxvdyBhdXRvbWF0aWMgd3JpdGVzL2NvbW1hbmRzIGluIHdvcmtzcGFjZS4KIyBQcm90ZWN0ZWQgYWN0aW9ucyByZW1haW4gZ292ZXJuZWQgYnkgdGhlIHJ1bnRpbWUgcG9saWN5IGluIHVzZS4KYXBwcm92YWxfcG9saWN5ID0gIm5ldmVyIgpzYW5kYm94X21vZGUgPSAiZGFuZ2VyLWZ1bGwtYWNjZXNzIgoKbW9kZWxfcmVhc29uaW5nX2VmZm9ydCA9ICJoaWdoIgptb2RlbF9yZWFzb25pbmdfc3VtbWFyeSA9ICJkZXRhaWxlZCIKcHJlZmVycmVkX2F1dGhfbWV0aG9kID0gImNoYXRncHQiCgpbbWNwX3NlcnZlcnMucGxheXdyaWdodF0KY29tbWFuZCA9ICJucHgiCnN0YXJ0dXBfdGltZW91dF9zZWMgPSA2MAphcmdzID0gWwogICJAcGxheXdyaWdodC9tY3BAMC4wLjY4IiwKICAiLS1pc29sYXRlZCIKXQoKW25vdGljZV0KaGlkZV9yYXRlX2xpbWl0X21vZGVsX251ZGdlID0gdHJ1ZQoKW25vdGljZS5tb2RlbF9taWdyYXRpb25zXQoiZ3B0LTUuMiIgPSAiZ3B0LTUuMi1jb2RleCIKCltmZWF0dXJlc10KbXVsdGlfYWdlbnQgPSBmYWxzZQoKIyBTa2lsbHMgYXJlIGludGVudGlvbmFsbHkgb21pdHRlZCBmb3Igbm93IGluIENBUkwuCiMgTm90aWZpY2F0aW9uIHdpcmluZyBpcyBtYW5hZ2VkIGJ5IHNjcmlwdHMvY29uZmlndXJlLWNvZGV4LW5vdGlmeS5zaC4KdHVpLm5vdGlmaWNhdGlvbnMgPSB0cnVlCg=="
CLAUDE_SETTINGS_JSON_B64="ewogICIkc2NoZW1hIjogImh0dHBzOi8vanNvbi5zY2hlbWFzdG9yZS5vcmcvY2xhdWRlLWNvZGUtc2V0dGluZ3MuanNvbiIsCiAgImRlZmF1bHRNb2RlIjogImJ5cGFzc1Blcm1pc3Npb25zIiwKICAic3Bpbm5lclZlcmJzIjogewogICAgIm1vZGUiOiAicmVwbGFjZSIsCiAgICAidmVyYnMiOiBbCiAgICAgICJUaGlua2luZyIKICAgIF0KICB9Cn0K"
CLAUDE_KEYBINDINGS_JSON_B64="ewogICIkc2NoZW1hIjogImh0dHBzOi8vd3d3LnNjaGVtYXN0b3JlLm9yZy9jbGF1ZGUtY29kZS1rZXliaW5kaW5ncy5qc29uIiwKICAiJGRvY3MiOiAiaHR0cHM6Ly9jb2RlLmNsYXVkZS5jb20vZG9jcy9lbi9rZXliaW5kaW5ncyIsCiAgImJpbmRpbmdzIjogWwogICAgewogICAgICAiY29udGV4dCI6ICJDaGF0IiwKICAgICAgImJpbmRpbmdzIjogewogICAgICAgICJzaGlmdCtlbnRlciI6ICJjaGF0Om5ld2xpbmUiCiAgICAgIH0KICAgIH0KICBdCn0K"
CLAUDE_MCP_JSON_B64="ewogICJtY3BTZXJ2ZXJzIjogewogICAgInBsYXl3cmlnaHQiOiB7CiAgICAgICJ0eXBlIjogInN0ZGlvIiwKICAgICAgImNvbW1hbmQiOiAibnB4IiwKICAgICAgImFyZ3MiOiBbCiAgICAgICAgIkBwbGF5d3JpZ2h0L21jcEAwLjAuNjgiLAogICAgICAgICItLWlzb2xhdGVkIiwKICAgICAgICAiLS1vdXRwdXQtZGlyIiwKICAgICAgICAiL3RtcC9wbGF5d3JpZ2h0LW1jcCIKICAgICAgXSwKICAgICAgImVudiI6IHt9CiAgICB9CiAgfQp9Cg=="
NPMRC_B64="IyBDQVJMIGNhbm9uaWNhbCBucG0gY29uZmlndXJhdGlvbgojIEFkZCBzaGFyZWQgbnBtIHNldHRpbmdzIGhlcmUgd2hlbiBuZWVkZWQuCg=="
NVMRC_B64="MjQK"
SHELL_CORE_ZSH_B64="IyBDQVJMIHNoYXJlZCBac2ggY29yZS4KIyBUaGlzIGZpbGUgaXMgc291cmNlZCBmcm9tIH4vLnpzaHJjOyBrZWVwIHBlcnNvbmFsIG92ZXJyaWRlcyBpbiB+Ly56c2hyYyBhZnRlciB0aGUgQ0FSTCBibG9jay4KCmV4cG9ydCBQQVRIPSIkSE9NRS8ubG9jYWwvYmluOiRQQVRIIgoKYWxpYXMgLi49J2NkIC4uJwphbGlhcyAuLi49J2NkIC4uLy4uJwphbGlhcyAuLi4uPSdjZCAuLi8uLi8uLicKYWxpYXMgbD0nbHMgLUNGJwphbGlhcyBsYT0nbHMgLUEnCmFsaWFzIGxsPSdscyAtYWxGJwphbGlhcyBncz0nZ2l0IHN0YXR1cyAtc2InCmFsaWFzIGdhPSdnaXQgYWRkJwphbGlhcyBnYz0nZ2l0IGNvbW1pdCcKYWxpYXMgZ2NhPSdnaXQgY29tbWl0IC0tYW1lbmQnCmFsaWFzIGdjbz0nZ2l0IGNoZWNrb3V0JwphbGlhcyBnYj0nZ2l0IGJyYW5jaCcKYWxpYXMgZ2Q9J2dpdCBkaWZmJwphbGlhcyBnbD0nZ2l0IGxvZyAtLW9uZWxpbmUgLS1ncmFwaCAtLWRlY29yYXRlIC0yMCcKYWxpYXMgZ3A9J2dpdCBwdXNoJwphbGlhcyBmZj0ncmcgLS1maWxlcyB8IHJnJwphbGlhcyByZ2E9J3JnIC1uJwphbGlhcyByZ2k9J3JnIC1uIC1pJwoKIwojIEp1bXAgdG8gdGhlIGN1cnJlbnQgZ2l0IHJlcG9zaXRvcnkgcm9vdC4KY2RiKCkgewogIGxvY2FsIHJvb3QKICByb290PSIkKGdpdCByZXYtcGFyc2UgLS1zaG93LXRvcGxldmVsIDI+L2Rldi9udWxsKSIgfHwgewogICAgZWNobyAiTm90IGluIGEgZ2l0IHJlcG9zaXRvcnkiID4mMgogICAgcmV0dXJuIDEKICB9CiAgY2QgIiRyb290Igp9CgojCiMgSnVtcCB0byB0aGUgZGlyZWN0b3J5IG9mIHRoZSBmaXJzdCBmaWxlIHdob3NlIHBhdGggbWF0Y2hlcyBhIHBhdHRlcm4uCmNkZigpIHsKICBsb2NhbCBtYXRjaAogIGlmIFtbICQjIC1sdCAxIF1dOyB0aGVuCiAgICBlY2hvICJVc2FnZTogY2RmIDxwYXR0ZXJuPiIgPiYyCiAgICByZXR1cm4gMQogIGZpCgogIG1hdGNoPSIkKHJnIC0tZmlsZXMgfCByZyAtLSAiJDEiIHwgaGVhZCAtbjEpIgogIGlmIFtbIC16ICIkbWF0Y2giIF1dOyB0aGVuCiAgICBlY2hvICJObyBmaWxlIG1hdGNoZXM6ICQxIiA+JjIKICAgIHJldHVybiAxCiAgZmkKICBjZCAiJChkaXJuYW1lICIkbWF0Y2giKSIKfQoKIwojIFNlYXJjaCBzaGVsbCBoaXN0b3J5IHdpdGggcmlwZ3JlcC4KaGdyZXAoKSB7CiAgZmMgLWwgMSB8IHJnICIkQCIKfQoKIwojIERlbGV0ZSBsb2NhbCBicmFuY2hlcyBhbHJlYWR5IG1lcmdlZCBpbnRvIHRoZSBjdXJyZW50IGJyYW5jaCAoZXhjbHVkaW5nIHByb3RlY3RlZCBuYW1lcykuCmdjbGVhbigpIHsKICBsb2NhbCBjdXJyZW50IGJyYW5jaAogIGN1cnJlbnQ9IiQoZ2l0IHJldi1wYXJzZSAtLWFiYnJldi1yZWYgSEVBRCAyPi9kZXYvbnVsbCkiIHx8IHsKICAgIGVjaG8gIk5vdCBpbiBhIGdpdCByZXBvc2l0b3J5IiA+JjIKICAgIHJldHVybiAxCiAgfQoKICBnaXQgZm9yLWVhY2gtcmVmIC0tZm9ybWF0PSclKHJlZm5hbWU6c2hvcnQpJyByZWZzL2hlYWRzIHwgd2hpbGUgSUZTPSByZWFkIC1yIGJyYW5jaDsgZG8KICAgIGNhc2UgIiRicmFuY2giIGluCiAgICAgIG1haW58bWFzdGVyfGRldmVsb3B8ZGV2fCIkY3VycmVudCIpCiAgICAgICAgY29udGludWUKICAgICAgICA7OwogICAgZXNhYwoKICAgIGlmIGdpdCBtZXJnZS1iYXNlIC0taXMtYW5jZXN0b3IgIiRicmFuY2giICIkY3VycmVudCIgMj4vZGV2L251bGw7IHRoZW4KICAgICAgZ2l0IGJyYW5jaCAtZCAiJGJyYW5jaCIKICAgIGZpCiAgZG9uZQp9CgojCiMgUHJpbnQgbGlrZWx5IGxvY2FsIElQdjQgYWRkcmVzc2VzIG9uIExpbnV4L21hY09TLgpteWlwKCkgewogIGlmIGNvbW1hbmQgLXYgaXAgPi9kZXYvbnVsbCAyPiYxOyB0aGVuCiAgICBpcCAtbyAtNCBhZGRyIHNob3cgc2NvcGUgZ2xvYmFsIHwgYXdrICd7cHJpbnQgJDIgIjogIiAkNH0nIHwgY3V0IC1kLyAtZjEKICAgIHJldHVybiAwCiAgZmkKCiAgaWYgY29tbWFuZCAtdiBpZmNvbmZpZyA+L2Rldi9udWxsIDI+JjE7IHRoZW4KICAgIGlmY29uZmlnIHwgYXdrICcvaW5ldCAvICYmICQyICE9ICIxMjcuMC4wLjEiIHtwcmludCAkMn0nCiAgICByZXR1cm4gMAogIGZpCgogIGVjaG8gIk5vIHN1cHBvcnRlZCBuZXR3b3JrIHRvb2wgZm91bmQgKGlwL2lmY29uZmlnKS4iID4mMgogIHJldHVybiAxCn0KCiMKIyBTaG93IG1hY09TIGhhcmR3YXJlIHBvcnQgdG8gZGV2aWNlIG1hcHBpbmdzLgptYWNod3BvcnRzKCkgewogIGlmIFtbICIkKHVuYW1lIC1zKSIgIT0gIkRhcndpbiIgXV07IHRoZW4KICAgIGVjaG8gIm1hY2h3cG9ydHMgaXMgb25seSBhdmFpbGFibGUgb24gbWFjT1MuIiA+JjIKICAgIHJldHVybiAxCiAgZmkKCiAgbmV0d29ya3NldHVwIC1saXN0YWxsaGFyZHdhcmVwb3J0cwp9CgojCiMgUHJpbnQgcXVpY2sgbWFjT1MgTEFOIElQIGNhbmRpZGF0ZXMgYWNyb3NzIGtub3duIG5ldHdvcmsgaGFyZHdhcmUgcG9ydHMuCm1hY2lwKCkgewogIGlmIFtbICIkKHVuYW1lIC1zKSIgIT0gIkRhcndpbiIgXV07IHRoZW4KICAgIGVjaG8gIm1hY2lwIGlzIG9ubHkgYXZhaWxhYmxlIG9uIG1hY09TLiIgPiYyCiAgICByZXR1cm4gMQogIGZpCgogIGxvY2FsIGRldiBpcCBmb3VuZF9hbnkKICBmb3VuZF9hbnk9MAoKICB3aGlsZSBJRlM9IHJlYWQgLXIgZGV2OyBkbwogICAgW1sgLW4gIiRkZXYiIF1dIHx8IGNvbnRpbnVlCiAgICBpcD0iJChpcGNvbmZpZyBnZXRpZmFkZHIgIiRkZXYiIDI+L2Rldi9udWxsIHx8IHRydWUpIgogICAgaWYgW1sgLW4gIiRpcCIgXV07IHRoZW4KICAgICAgZWNobyAiJGRldjogJGlwIgogICAgICBmb3VuZF9hbnk9MQogICAgZmkKICBkb25lIDwgPChuZXR3b3Jrc2V0dXAgLWxpc3RhbGxoYXJkd2FyZXBvcnRzIDI+L2Rldi9udWxsIHwgYXdrIC1GJzogJyAnL15EZXZpY2U6IC97cHJpbnQgJDJ9JykKCiAgaWYgW1sgIiRmb3VuZF9hbnkiIC1lcSAwIF1dOyB0aGVuCiAgICBlY2hvICJObyBMQU4gSVAgZm91bmQgdmlhIG5ldHdvcmtzZXR1cCBoYXJkd2FyZSBwb3J0cy4iID4mMgogICAgZWNobyAiUnVuIG1hY2h3cG9ydHMgdG8gaW5zcGVjdCBhdmFpbGFibGUgaW50ZXJmYWNlcy4iID4mMgogICAgcmV0dXJuIDEKICBmaQp9CgojCiMgU2hvdyBtYWNPUyByZW1vdGUgYWNjZXNzIHN0YXR1cyAoU1NIICsgU2NyZWVuIFNoYXJpbmcpIGFuZCBMQU4gSVAgaGludHMuCm1hY3JlbW90ZSgpIHsKICBpZiBbWyAiJCh1bmFtZSAtcykiICE9ICJEYXJ3aW4iIF1dOyB0aGVuCiAgICBlY2hvICJtYWNyZW1vdGUgaXMgb25seSBhdmFpbGFibGUgb24gbWFjT1MuIiA+JjIKICAgIHJldHVybiAxCiAgZmkKCiAgZWNobyAiUmVtb3RlIExvZ2luIChTU0gpOiIKICBzeXN0ZW1zZXR1cCAtZ2V0cmVtb3RlbG9naW4gMj4vZGV2L251bGwgfHwgZWNobyAiICBVbmFibGUgdG8gcmVhZCBSZW1vdGUgTG9naW4gc3RhdHVzLiIKCiAgZWNobyAiIgogIGVjaG8gIlNjcmVlbiBTaGFyaW5nIChWTkMpIHBvcnQgY2hlY2sgb24gbG9jYWxob3N0OiIKICBpZiBuYyAteiBsb2NhbGhvc3QgNTkwMCA+L2Rldi9udWxsIDI+JjE7IHRoZW4KICAgIGVjaG8gIiAgUG9ydCA1OTAwIGlzIG9wZW4gKGxpa2VseSBlbmFibGVkKS4iCiAgZWxzZQogICAgZWNobyAiICBQb3J0IDU5MDAgaXMgY2xvc2VkIChsaWtlbHkgZGlzYWJsZWQpLiIKICBmaQoKICBlY2hvICIiCiAgZWNobyAiTEFOIElQIGNhbmRpZGF0ZXM6IgogIG1hY2lwIHx8IHRydWUKfQo="

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
  CLAUDE_CODE_VERSION       Claude installer target (e.g. stable or a specific version).
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
    log "SSH key already exists at ${private_key}; preserving existing key"
  else
    log "Generating SSH key at ${private_key}"
    ssh-keygen -t ed25519 -a 64 -f "${private_key}" -N "" -C "${key_comment}"
  fi

  if [[ ! -f "${public_key}" ]]; then
    log "Public key missing at ${public_key}; regenerating from private key"
    ssh-keygen -y -f "${private_key}" > "${public_key}"
  fi

  chmod 600 "${private_key}"
  chmod 644 "${public_key}"

  log "SSH public key available at ${public_key}"
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

decode_b64_to_file() {
  local b64_value dest_path mode
  b64_value="$1"
  dest_path="$2"
  mode="$3"

  mkdir -p "$(dirname "${dest_path}")"
  if ! printf '%s' "${b64_value}" | base64 -d > "${dest_path}"; then
    die "Failed to decode embedded config for ${dest_path}"
  fi
  chmod "${mode}" "${dest_path}"
}

install_baseline_config_files() {
  decode_b64_to_file "${NPMRC_B64}" "${HOME}/.npmrc" 0644
  decode_b64_to_file "${NVMRC_B64}" "${HOME}/.nvmrc" 0644
  decode_b64_to_file "${CODEX_CONFIG_TOML_B64}" "${HOME}/.codex/config.toml" 0644
  decode_b64_to_file "${CLAUDE_SETTINGS_JSON_B64}" "${HOME}/.claude/settings.json" 0644
  decode_b64_to_file "${CLAUDE_KEYBINDINGS_JSON_B64}" "${HOME}/.claude/keybindings.json" 0644
  decode_b64_to_file "${CLAUDE_MCP_JSON_B64}" "${HOME}/.claude/mcp.json" 0644
  decode_b64_to_file "${SHELL_CORE_ZSH_B64}" "${HOME}/.config/carl/zsh/core.zsh" 0644

  if ! jq -e . "${HOME}/.claude/settings.json" >/dev/null 2>&1; then
    die "Embedded Claude settings JSON is invalid."
  fi

  if ! jq -e . "${HOME}/.claude/keybindings.json" >/dev/null 2>&1; then
    die "Embedded Claude keybindings JSON is invalid."
  fi

  if ! jq -e . "${HOME}/.claude/mcp.json" >/dev/null 2>&1; then
    die "Embedded Claude MCP JSON is invalid."
  fi
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
      $0 == end_marker {
        in_block = 0
        next
      }
      {
        if (!in_block) {
          print
        }
      }
      END {
        if (block_written == 0) {
          if (NR > 0) {
            print ""
          }
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

normalize_bool() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) printf '1' ;;
    0|false|FALSE|no|NO|off|OFF) printf '0' ;;
    *)
      die "Invalid boolean value: $1"
      ;;
  esac
}

validate_notify_defaults() {
  NOTIFY_ENABLED_DEFAULT="$(normalize_bool "${NOTIFY_ENABLED_DEFAULT}")"
  NOTIFY_INCLUDE_SNIPPET_DEFAULT="$(normalize_bool "${NOTIFY_INCLUDE_SNIPPET_DEFAULT}")"

  if [[ ! "${NOTIFY_MIN_INTERVAL_SEC_DEFAULT}" =~ ^[0-9]+$ ]]; then
    die "NOTIFY_MIN_INTERVAL_SEC must be a non-negative integer."
  fi
}

install_carl_notify_binary() {
  local script_dir repo_script tmp_script
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  repo_script="${script_dir}/../scripts/carl-notify.sh"

  if [[ -f "${repo_script}" ]]; then
    if install -m 0755 "${repo_script}" "${CARL_NOTIFY_BIN}" 2>/dev/null; then
      log "Installed carl-notify from repo script to ${CARL_NOTIFY_BIN}"
      return
    fi
  fi

  tmp_script="$(mktemp "/tmp/carl-notify.XXXXXX")"
  cat > "${tmp_script}" <<'CARL_NOTIFY'
#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[carl-notify] %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Missing command: $1"
    exit 1
  }
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

hash_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return 0
  fi
  shasum -a 256 | awk '{print $1}'
}

need_cmd jq
need_cmd curl
need_cmd hostname

source_name="${1:-}"
if [[ -z "${source_name}" ]]; then
  log "Usage: carl-notify <codex|claude> [json-payload]"
  exit 1
fi
shift || true

default_enabled="$(normalize_bool "${CARL_NOTIFY_ENABLED_DEFAULT:-1}")"
default_interval="${CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT:-120}"
default_include="$(normalize_bool "${CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT:-1}")"

notify_enabled="$(normalize_bool "${NOTIFY_ENABLED:-${default_enabled}}")"
notify_interval="${NOTIFY_MIN_INTERVAL_SEC:-${default_interval}}"
notify_include="$(normalize_bool "${NOTIFY_INCLUDE_SNIPPET:-${default_include}}")"

if [[ "${notify_enabled}" != "1" ]]; then
  exit 0
fi

if [[ ! "${notify_interval}" =~ ^[0-9]+$ ]]; then
  log "NOTIFY_MIN_INTERVAL_SEC must be a non-negative integer"
  exit 1
fi

secrets_file="${CARL_SECRETS_FILE:-$HOME/.config/carl/secrets.env}"
if [[ -f "${secrets_file}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${secrets_file}"
  set +a
fi

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  log "SLACK_WEBHOOK_URL is required in ${secrets_file}"
  exit 2
fi

raw_payload=""
if [[ $# -gt 0 ]]; then
  raw_payload="$*"
elif [[ ! -t 0 ]]; then
  raw_payload="$(cat || true)"
fi

if [[ -z "${raw_payload}" ]]; then
  payload='{}'
elif printf '%s' "${raw_payload}" | jq -e . >/dev/null 2>&1; then
  payload="${raw_payload}"
else
  payload="$(jq -n --arg message "${raw_payload}" '{message: $message}')"
fi

event="$(printf '%s' "${payload}" | jq -r '.hook_event_name // .event // .event_name // .type // .reason // "notification"')"
message="$(printf '%s' "${payload}" | jq -r '.message // .title // .summary // .reason // .["last-assistant-message"] // .last_assistant_message // empty' | tr '\r\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//')"
cwd_hint="$(printf '%s' "${payload}" | jq -r '.cwd // .workspace_path // .workspace_root // .path // empty')"
session_hint="$(printf '%s' "${payload}" | jq -r '.session_id // .["turn-id"] // .turn_id // .conversation_id // .request_id // .id // empty')"

if [[ -z "${cwd_hint}" ]]; then
  cwd_hint="$(pwd)"
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/carl-notify"
state_file="${cache_dir}/last_event"
mkdir -p "${cache_dir}"
chmod 700 "${cache_dir}"

dedupe_key="$(printf '%s|%s|%s|%s|%s' "${source_name}" "${event}" "${cwd_hint}" "${session_hint}" "${message}" | hash_sha256)"
now_ts="$(date +%s)"
if [[ -f "${state_file}" ]]; then
  read -r prev_ts prev_key < "${state_file}" || true
  if [[ "${prev_key:-}" == "${dedupe_key}" && "${prev_ts:-}" =~ ^[0-9]+$ ]]; then
    if (( now_ts - prev_ts < notify_interval )); then
      exit 0
    fi
  fi
fi

printf '%s %s\n' "${now_ts}" "${dedupe_key}" > "${state_file}"
chmod 600 "${state_file}"

host_name="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown-host)"
user_name="${USER:-unknown-user}"
now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

text_lines=(
  "CARL attention needed: ${source_name} (${event})"
  "host=${host_name}"
  "user=${user_name}"
  "cwd=${cwd_hint}"
  "time_utc=${now_utc}"
)

if [[ -n "${session_hint}" ]]; then
  text_lines+=("session=${session_hint}")
fi

if [[ "${notify_include}" == "1" && -n "${message}" ]]; then
  text_lines+=("message=$(printf '%.240s' "${message}")")
fi

slack_payload="$(jq -n --arg text "$(printf '%s\n' "${text_lines[@]}")" '{text: $text}')"
curl -fsS -X POST -H 'Content-Type: application/json' --data "${slack_payload}" "${SLACK_WEBHOOK_URL}" >/dev/null
CARL_NOTIFY

  if install -m 0755 "${tmp_script}" "${CARL_NOTIFY_BIN}" 2>/dev/null; then
    rm -f "${tmp_script}"
    log "Installed carl-notify to ${CARL_NOTIFY_BIN}"
    return
  fi

  CARL_NOTIFY_BIN="${HOME}/.local/bin/carl-notify"
  install -m 0755 "${tmp_script}" "${CARL_NOTIFY_BIN}"
  rm -f "${tmp_script}"
  log "Installed carl-notify to ${CARL_NOTIFY_BIN} (fallback path)"
}

configure_codex_notify() {
  local config_file notify_line tui_line tmp_file
  config_file="${HOME}/.codex/config.toml"
  mkdir -p "${HOME}/.codex"
  if [[ ! -f "${config_file}" ]]; then
    : > "${config_file}"
  fi

  notify_line="notify = [\"/usr/bin/env\", \"CARL_NOTIFY_ENABLED_DEFAULT=${NOTIFY_ENABLED_DEFAULT}\", \"CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT=${NOTIFY_MIN_INTERVAL_SEC_DEFAULT}\", \"CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT=${NOTIFY_INCLUDE_SNIPPET_DEFAULT}\", \"${CARL_NOTIFY_BIN}\", \"codex\"]"
  tui_line="tui.notifications = true"

  tmp_file="$(mktemp)"
  awk \
    -v notify_line="${notify_line}" \
    -v tui_line="${tui_line}" \
    '
      BEGIN { notify_seen = 0; tui_seen = 0 }
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
      { print }
      END {
        if (notify_seen == 0) { print notify_line }
        if (tui_seen == 0) { print tui_line }
      }
    ' "${config_file}" > "${tmp_file}"
  mv "${tmp_file}" "${config_file}"
}

configure_claude_notify() {
  local config_file escaped_notify_bin command_string tmp_file
  config_file="${HOME}/.claude/settings.json"
  mkdir -p "${HOME}/.claude"
  if [[ ! -f "${config_file}" ]]; then
    printf '{}\n' > "${config_file}"
  fi

  if ! jq -e . "${config_file}" >/dev/null 2>&1; then
    die "Invalid JSON in ${config_file}; cannot configure Claude hook."
  fi

  escaped_notify_bin="$(printf '%q' "${CARL_NOTIFY_BIN}")"
  command_string="CARL_NOTIFY_ENABLED_DEFAULT=${NOTIFY_ENABLED_DEFAULT} CARL_NOTIFY_MIN_INTERVAL_SEC_DEFAULT=${NOTIFY_MIN_INTERVAL_SEC_DEFAULT} CARL_NOTIFY_INCLUDE_SNIPPET_DEFAULT=${NOTIFY_INCLUDE_SNIPPET_DEFAULT} ${escaped_notify_bin} claude"
  tmp_file="$(mktemp)"

  jq --arg cmd "${command_string}" '
    . as $root
    | if ($root | type) == "object" then $root else {} end
    | .hooks = (.hooks // {})
    | reduce ["Notification","Stop"][] as $event (
        .;
        .hooks[$event] = (
          if (.hooks[$event] | type) == "array"
          then .hooks[$event]
          else []
          end
        )
        | if ([ .hooks[$event][]?.hooks[]? | select(.type == "command" and .command == $cmd) ] | length) > 0
          then .
          else .hooks[$event] += [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": $cmd
                }
              ]
            }
          ]
          end
      )
  ' "${config_file}" > "${tmp_file}"

  mv "${tmp_file}" "${config_file}"
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
brew "tmux"
brew "cmake"
brew "ninja"
brew "pkg-config"
brew "bash"
brew "gnu-sed"
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
  # Central place for user-local -> Homebrew bin shims needed for login shell UX.
  ensure_brew_bin_symlink "${HOME}/.local/bin/claude" "claude"
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
  command -v tmux >/dev/null 2>&1 || die "tmux not found on PATH."
  command -v codex >/dev/null 2>&1 || die "codex not found on PATH."
  command -v claude >/dev/null 2>&1 || die "claude not found on PATH."
  command -v code >/dev/null 2>&1 || die "code not found on PATH."
  command -v playwright >/dev/null 2>&1 || die "playwright not found on PATH."
  command -v br >/dev/null 2>&1 || die "br not found on PATH."
  command -v carl-notify >/dev/null 2>&1 || die "carl-notify not found on PATH."

  if [[ "${INSTALL_PNPM}" == "1" ]]; then
    command -v pnpm >/dev/null 2>&1 || die "pnpm not found on PATH."
  fi

  brew --version
  node --version
  npm --version
  tmux -V

  if [[ "${INSTALL_PNPM}" == "1" ]]; then
    pnpm --version
  fi

  codex --version
  claude --version
  code --version
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
claude_code_target=${CLAUDE_CODE_VERSION}
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
  ensure_local_bin_path
  validate_notify_defaults
  configure_git_identity
  ensure_ssh_keypair
  write_embedded_brewfile
  brew_bundle_apply
  install_baseline_config_files
  ensure_carl_zshrc_source_block
  ensure_zsh_as_default_shell
  install_carl_notify_binary
  install_npm_globals
  install_claude_code
  configure_codex_notify
  configure_claude_notify
  install_br
  install_playwright_browsers
  verify_versions
  verify_playwright_browser_cache
  write_marker

  log "Bootstrap complete. Marker written to ${MARKER_FILE}."
  log "If node/npm/codex/claude are not found in your current shell, run:"
  log '  eval "$(/opt/homebrew/bin/brew shellenv)"'
  log '  export PATH="$HOME/.local/bin:$PATH"'
  log "  hash -r"
}

main "$@"
