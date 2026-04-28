#!/usr/bin/env bash
# Stop hook: surfaces unseen orch plan notifications to the agent.
#
# Reads ${CLAUDE_PROJECT_DIR}/.orchestrator/notifications/*.json, finds
# entries with `seen: false`, builds a single human-readable message,
# marks them seen via atomic rewrite, and emits a Claude Code Stop-hook
# block JSON ({"decision": "block", "reason": "..."}) on stdout so the
# agent surfaces the outcome on the next turn.
#
# No-op (exit 0 silently) when the notifications dir is absent or empty,
# making this safe to run from any repo.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${PWD}}"
NOTIF_DIR="${PROJECT_DIR}/.orchestrator/notifications"

[[ -d "${NOTIF_DIR}" ]] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Drain stdin so the harness doesn't see SIGPIPE when it pipes hook input.
cat >/dev/null 2>&1 || true

shopt -s nullglob
files=("${NOTIF_DIR}"/*.json)
shopt -u nullglob

[[ ${#files[@]} -gt 0 ]] || exit 0

unseen=()
for f in "${files[@]}"; do
  if jq -e '.seen == false' "${f}" >/dev/null 2>&1; then
    unseen+=("${f}")
  fi
done

[[ ${#unseen[@]} -gt 0 ]] || exit 0

MAX_DETAIL=6
total=${#unseen[@]}
detail_count=$((total < MAX_DETAIL ? total : MAX_DETAIL))

format_one() {
  local file="$1"
  jq -r '
    def fmt:
      "- plan \(.slug // "?") — \(.status // "?")"
      + (if .prUrl then " — PR: \(.prUrl)"
         elif .prNumber then " — PR #\(.prNumber)"
         else "" end)
      + (if .issueNumber then " (issue #\(.issueNumber))" else "" end)
      + (if .summary then ": \(.summary)" else "" end);
    fmt
  ' "${file}"
}

lines=()
lines+=("Orchestrator plan notifications (${total} unseen):")
for ((i = 0; i < detail_count; i++)); do
  lines+=("$(format_one "${unseen[$i]}")")
done

if ((total > MAX_DETAIL)); then
  remaining=$((total - MAX_DETAIL))
  lines+=("…and ${remaining} more — see ${NOTIF_DIR}")
fi

message=""
for line in "${lines[@]}"; do
  message="${message}${line}"$'\n'
done
message="${message%$'\n'}"

# Mark each unseen entry seen via atomic rewrite.
for f in "${unseen[@]}"; do
  tmp="${f}.tmp.$$"
  if jq '.seen = true' "${f}" >"${tmp}" 2>/dev/null; then
    mv -f "${tmp}" "${f}"
  else
    rm -f "${tmp}"
  fi
done

jq -nc --arg reason "${message}" '{decision: "block", reason: $reason}'

exit 0
