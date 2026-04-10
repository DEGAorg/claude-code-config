#!/usr/bin/env bash
# Signal that current_task is complete. Advances state to next item.
# Usage: bash scripts/task-complete.sh <state-file>
# Called by the worker agent. Validated by PreToolUse hook before running.

set -euo pipefail

STATE_FILE="${1:-}"

if [[ -z "${STATE_FILE}" ]]; then
  echo "error: usage: bash scripts/task-complete.sh <state-file>" >&2
  exit 1
fi

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "error: state file not found: ${STATE_FILE}" >&2
  exit 1
fi

PLAN_DIR="$(dirname "${STATE_FILE}")"
PLAN_FILE="${PLAN_DIR}/plan.md"

if [[ ! -f "${PLAN_FILE}" ]]; then
  echo "error: plan.md not found: ${PLAN_FILE}" >&2
  exit 1
fi

CURRENT_TASK=$(jq -r '.current_task.text' "${STATE_FILE}")

if [[ "${CURRENT_TASK}" == "null" || -z "${CURRENT_TASK}" ]]; then
  echo "error: no current_task in state file" >&2
  exit 1
fi

# Mark the first matching unchecked item as done in plan.md
TMP_PLAN=$(mktemp)
awk -v task="${CURRENT_TASK}" '
  !done && /^[[:space:]]*- \[ \]/ && index($0, task) {
    sub(/\[ \]/, "[x]")
    done = 1
  }
  { print }
' "${PLAN_FILE}" >"${TMP_PLAN}"
mv "${TMP_PLAN}" "${PLAN_FILE}"

# Set claimed_complete = true in state
TMP_STATE=$(mktemp)
jq '.current_task.claimed_complete = true' "${STATE_FILE}" >"${TMP_STATE}"
mv "${TMP_STATE}" "${STATE_FILE}"

# Advance to next item; exit 1 from plan-advance.sh means no more items remain
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if "${SCRIPT_DIR}/plan-advance.sh" "${PLAN_FILE}" "${STATE_FILE}"; then
  NEXT_TASK=$(jq -r '.current_task.text' "${STATE_FILE}")
  echo "✓ task complete: ${CURRENT_TASK} → next: ${NEXT_TASK}"
else
  echo "✓ task complete: ${CURRENT_TASK} → next: all done"
fi
