#!/usr/bin/env bash
# PostToolUse hook — append one JSONL entry per tool call to the daily session log.
#
# Noop when:
#   - RALPH_MODE is set (non-interactive ralph-loop context)
#   - ~/.claude/.session-log-config does not exist (session-start-logging.sh not fired)
#   - backend in config is not "local" (gcp or skip — not yet implemented)
#
# Log location: ~/.claude/logs/sessions/YYYY-MM-DD.jsonl
# Entry format: {"ts":"...","tool":"...","exit_code":N}
#
# Reading the log:
#   rg '"tool":"Bash"' ~/.claude/logs/sessions/          # all bash calls
#   rg '"exit_code":[^0]' ~/.claude/logs/sessions/       # non-zero exits

set -euo pipefail

[[ -n "${RALPH_MODE:-}" ]] && exit 0

CONFIG="${HOME}/.claude/.session-log-config"
[[ ! -f "$CONFIG" ]] && exit 0

BACKEND=$(jq -r '.backend' "$CONFIG")
[[ "$BACKEND" != "local" ]] && exit 0

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // "unknown"' <<<"$INPUT")
STATUS=$(jq -r '.tool_response.exit_code // 0' <<<"$INPUT")

LOG_DIR="${HOME}/.claude/logs/sessions"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).jsonl"

printf '{"ts":"%s","tool":"%s","exit_code":%s}\n' \
	"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL" "$STATUS" >>"$LOG_FILE"
