#!/usr/bin/env bash
# Sourceable bash helper for structured event logging.
# Source this file to get the log_event() function.
#
# Usage:
#   source scripts/log-client.sh
#   log_event "LOOP_START" '{"task_slug":"my-task","max_iterations":10}'
#   log_event "SHIP"
#
# Transport (tried in order):
#   1. socat  — preferred (brew install socat)
#   2. nc -U  — fallback (ships with macOS)
#   3. none   — warns once at source time, then no-ops

set -euo pipefail

# Source agent-shim for DEGA_CORE_HOME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"

_LOG_SOCK="${DEGA_CORE_HOME}/state/logs/log.sock"

# _LOG_TRANSPORT: "socat" | "nc" | "none"
_LOG_TRANSPORT="none"
if command -v socat >/dev/null 2>&1; then
  _LOG_TRANSPORT="socat"
elif command -v nc >/dev/null 2>&1; then
  _LOG_TRANSPORT="nc"
else
  echo "log-client: warning: socat and nc not found — event logging disabled" >&2
fi

# log_event EVENT_NAME [PAYLOAD_JSON]
#
# Sends a structured JSON event envelope to the log server via Unix socket.
# No-op when no transport is available or the server is not running.
#
# Args:
#   EVENT_NAME   - event type string (e.g. LOOP_START, SHIP)
#   PAYLOAD_JSON - optional JSON object payload (default: {})
log_event() {
  [[ "${_LOG_TRANSPORT}" != "none" ]] || return 0

  local event="${1:-}"
  # "${2:-{}}" mis-parses in bash — {} in default appends a literal '}' suffix.
  # Two-step assignment avoids the ambiguity entirely.
  local payload="${2:-}"
  [[ -n "${payload}" ]] || payload="{}"
  # Compact payload to single line so it fits on one JSONL line.
  # jq without -c emits pretty-printed JSON; tr -d strips the newlines safely.
  payload=$(printf '%s' "${payload}" | tr -d '\n')
  local ts
  ts=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
  local caller
  caller=$(basename "${BASH_SOURCE[1]:-unknown}")
  local session="${SESSION_ID:-}"

  local msg
  msg=$(printf '{"ts":"%s","session":"%s","script":"%s","event":"%s","payload":%s}\n' \
    "${ts}" "${session}" "${caller}" "${event}" "${payload}")

  if [[ "${_LOG_TRANSPORT}" == "socat" ]]; then
    printf '%s\n' "${msg}" | socat -u STDIN "UNIX-CONNECT:${_LOG_SOCK}" 2>/dev/null || true
  else
    printf '%s\n' "${msg}" | nc -U "${_LOG_SOCK}" 2>/dev/null || true
  fi
}
