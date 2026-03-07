#!/usr/bin/env bash
# Extract next unchecked [ ] item from plan.md and write to .ralph-state.json
# Usage: scripts/plan-advance.sh <plan.md> <state.json>
# Exits 0 if an item was found and written; exits 1 if no unchecked items remain.

set -euo pipefail

PLAN_FILE="${1:-}"
STATE_FILE="${2:-}"

if [[ -z "${PLAN_FILE}" || -z "${STATE_FILE}" ]]; then
	echo "error: usage: scripts/plan-advance.sh <plan.md> <state.json>" >&2
	exit 1
fi

if [[ ! -f "${PLAN_FILE}" ]]; then
	echo "error: plan file not found: ${PLAN_FILE}" >&2
	exit 1
fi

if [[ ! -f "${STATE_FILE}" ]]; then
	echo "error: state file not found: ${STATE_FILE}" >&2
	exit 1
fi

# Extract the LAST ## Progress log section (skip examples in earlier sections).
# Uses awk: track fenced code blocks (```) to skip items inside them,
# reset on each ## Progress log heading so only the last section survives.
PROGRESS_SECTION=$(awk '
	/^```/ { fence = !fence; next }
	fence { next }
	/^## Progress log/ { buf = ""; capturing = 1; next }
	capturing && /^## / { capturing = 0; next }
	capturing { buf = buf $0 "\n" }
	END { printf "%s", buf }
' "${PLAN_FILE}")

# Find the next unchecked item — exit 1 (no more items) if none remain
if ! LINE=$(printf '%s\n' "${PROGRESS_SECTION}" | grep -m1 '^[[:space:]]*- \[ \]'); then
	exit 1
fi

ITEM=$(printf '%s' "${LINE}" | sed 's/^[[:space:]]*- \[ \] //')

# Write current_task into state
TMP=$(mktemp)
jq --arg text "${ITEM}" \
	'.current_task.text = $text | .current_task.claimed_complete = false' \
	"${STATE_FILE}" >"${TMP}"
mv "${TMP}" "${STATE_FILE}"
