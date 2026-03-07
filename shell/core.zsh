# CARL shared Zsh core.
# This file is sourced from ~/.zshrc; keep personal overrides in ~/.zshrc after the CARL block.

export PATH="$HOME/.local/bin:$PATH"

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias l='ls -CF'
alias la='ls -A'
alias ll='ls -alF'
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit'
alias gca='git commit --amend'
alias gco='git checkout'
alias gb='git branch'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
alias gp='git push'
alias ff='rg --files | rg'
alias rga='rg -n'
alias rgi='rg -n -i'

#
# Jump to the current git repository root.
cdb() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Not in a git repository" >&2
    return 1
  }
  cd "$root"
}

#
# Jump to the directory of the first file whose path matches a pattern.
cdf() {
  local match
  if [[ $# -lt 1 ]]; then
    echo "Usage: cdf <pattern>" >&2
    return 1
  fi

  match="$(rg --files | rg -- "$1" | head -n1)"
  if [[ -z "$match" ]]; then
    echo "No file matches: $1" >&2
    return 1
  fi
  cd "$(dirname "$match")"
}

#
# Search shell history with ripgrep.
hgrep() {
  fc -l 1 | rg "$@"
}

#
# Delete local branches already merged into the current branch (excluding protected names).
gclean() {
  local current branch
  current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || {
    echo "Not in a git repository" >&2
    return 1
  }

  git for-each-ref --format='%(refname:short)' refs/heads | while IFS= read -r branch; do
    case "$branch" in
      main|master|develop|dev|"$current")
        continue
        ;;
    esac

    if git merge-base --is-ancestor "$branch" "$current" 2>/dev/null; then
      git branch -d "$branch"
    fi
  done
}

#
# Print likely local IPv4 addresses on Linux/macOS.
myip() {
  if command -v ip >/dev/null 2>&1; then
    ip -o -4 addr show scope global | awk '{print $2 ": " $4}' | cut -d/ -f1
    return 0
  fi

  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig | awk '/inet / && $2 != "127.0.0.1" {print $2}'
    return 0
  fi

  echo "No supported network tool found (ip/ifconfig)." >&2
  return 1
}

#
# Show macOS hardware port to device mappings.
machwports() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "machwports is only available on macOS." >&2
    return 1
  fi

  networksetup -listallhardwareports
}

#
# Print quick macOS LAN IP candidates across known network hardware ports.
macip() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macip is only available on macOS." >&2
    return 1
  fi

  local dev ip found_any
  found_any=0

  while IFS= read -r dev; do
    [[ -n "$dev" ]] || continue
    ip="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
    if [[ -n "$ip" ]]; then
      echo "$dev: $ip"
      found_any=1
    fi
  done < <(networksetup -listallhardwareports 2>/dev/null | awk -F': ' '/^Device: /{print $2}')

  if [[ "$found_any" -eq 0 ]]; then
    echo "No LAN IP found via networksetup hardware ports." >&2
    echo "Run machwports to inspect available interfaces." >&2
    return 1
  fi
}

#
# Show macOS remote access status (SSH + Screen Sharing) and LAN IP hints.
macremote() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macremote is only available on macOS." >&2
    return 1
  fi

  echo "Remote Login (SSH):"
  systemsetup -getremotelogin 2>/dev/null || echo "  Unable to read Remote Login status."

  echo ""
  echo "Screen Sharing (VNC) port check on localhost:"
  if nc -z localhost 5900 >/dev/null 2>&1; then
    echo "  Port 5900 is open (likely enabled)."
  else
    echo "  Port 5900 is closed (likely disabled)."
  fi

  echo ""
  echo "LAN IP candidates:"
  macip || true
}
