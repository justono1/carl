#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

BOOTSTRAP_FILE="${SCRIPT_DIR}/bootstrap-mac.sh"
BOOTSTRAP_SUM_FILE="${SCRIPT_DIR}/bootstrap-mac.sh.sha256"

write_sum_line() {
  local src_file out_file label
  src_file="$1"
  out_file="$2"
  label="$3"
  shasum -a 256 "${src_file}" | awk -v l="${label}" '{print $1 "  " l}' > "${out_file}"
}

check_sum_line() {
  local src_file expected_file label tmp_file
  src_file="$1"
  expected_file="$2"
  label="$3"
  tmp_file="$(mktemp "/tmp/carl.sha256.${label}.XXXXXX")"
  shasum -a 256 "${src_file}" | awk -v l="${label}" '{print $1 "  " l}' > "${tmp_file}"
  if ! diff -u "${expected_file}" "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi
  rm -f "${tmp_file}"
  return 0
}

mode="${1:-update}"
case "${mode}" in
  update)
    write_sum_line "${BOOTSTRAP_FILE}" "${BOOTSTRAP_SUM_FILE}" "bootstrap-mac.sh"
    echo "Updated checksum file:"
    echo "  ${BOOTSTRAP_SUM_FILE}"
    ;;
  --check|check)
    check_sum_line "${BOOTSTRAP_FILE}" "${BOOTSTRAP_SUM_FILE}" "bootstrap-mac.sh"
    echo "Checksum matches."
    ;;
  *)
    echo "Usage: $0 [update|--check]" >&2
    exit 1
    ;;
esac
