#!/usr/bin/env bash
# Shared stderr/exit helper for canon scripts.
#
# Scripts in canon/scripts/ source this helper and call `canon_error` on
# failure paths instead of hand-rolling the prefix. See
# canon/scripts/README.md for the runtime contract (exit-code taxonomy
# and stderr-line format).
#
# Usage (from a sibling script):
#
#   source "$(dirname "${BASH_SOURCE[0]}")/canon-error.sh"
#   canon_error 2 missing-tool "jq is required; install via 'brew install jq'"

set -euo pipefail

# canon_error <code> <short> [detail...]
#
# Writes `canon-error: <code>: <short>` as the first stderr line, any
# additional detail args on subsequent stderr lines, and exits with
# <code>. Emits nothing to stdout.
canon_error() {
  local code="${1:-1}"
  local short="${2:-generic-failure}"
  shift 2 || true

  printf 'canon-error: %s: %s\n' "$code" "$short" >&2
  local detail
  for detail in "$@"; do
    printf '%s\n' "$detail" >&2
  done

  exit "$code"
}
