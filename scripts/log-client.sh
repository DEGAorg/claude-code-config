#!/usr/bin/env bash
# Sourceable bash helper for structured event logging.
# Source this file to get the log_event() function.
#
# Usage:
#   source scripts/log-client.sh
#   log_event "LOOP_START" '{"task_slug":"my-task","max_iterations":10}'
#   log_event "SHIP"

set -euo pipefail

_LOG_SOCK="${HOME}/.claude/logs/log.sock"

# LOG_AVAILABLE is set at source time.
# 0 = socat not found; log_event is then a no-op.
LOG_AVAILABLE=0
if command -v socat >/dev/null 2>&1; then
	LOG_AVAILABLE=1
fi

# log_event EVENT_NAME [PAYLOAD_JSON]
#
# Sends a structured JSON event envelope to the log server via Unix socket.
# No-op when LOG_AVAILABLE=0 or the server is not running.
#
# Args:
#   EVENT_NAME   - event type string (e.g. LOOP_START, SHIP)
#   PAYLOAD_JSON - optional JSON object payload (default: {})
log_event() {
	[[ "${LOG_AVAILABLE}" == "1" ]] || return 0

	local event="${1:-}"
	local payload="${2:-{}}"
	local ts
	ts=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
	local caller
	caller=$(basename "${BASH_SOURCE[1]:-unknown}")
	local session="${SESSION_ID:-}"

	printf '{"ts":"%s","session":"%s","script":"%s","event":"%s","payload":%s}\n' \
		"${ts}" "${session}" "${caller}" "${event}" "${payload}" |
		socat -u STDIN "UNIX-CONNECT:${_LOG_SOCK}" 2>/dev/null || true
}
