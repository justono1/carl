#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${STATE_FILE:-./.do-droplet.json}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }
need_cmd doctl
need_cmd jq

# Ensure doctl is authenticated
if ! doctl account get >/dev/null 2>&1; then
  echo "doctl is not authenticated. Run: doctl auth init"
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  echo "State file not found: $STATE_FILE"
  echo "Nothing to destroy (or create script didn't write state)."
  exit 1
fi

droplet_id="$(jq -r '.droplet.id // empty' "$STATE_FILE")"
droplet_name="$(jq -r '.droplet.name // empty' "$STATE_FILE")"
droplet_ip="$(jq -r '.droplet.ip // empty' "$STATE_FILE")"

if [[ -z "$droplet_id" ]]; then
  echo "State file missing droplet.id: $STATE_FILE"
  exit 1
fi

echo "Destroying last created droplet:"
echo "  name:  $droplet_name"
echo "  id:    $droplet_id"
[[ -n "$droplet_ip" && "$droplet_ip" != "null" ]] && echo "  ip:    $droplet_ip"
echo "  state: $STATE_FILE"
echo

doctl compute droplet delete "$droplet_id" --force

rm -f "$STATE_FILE"

echo "✅ Droplet destroyed (id: $droplet_id). State file removed."
echo "Verify: doctl compute droplet list"