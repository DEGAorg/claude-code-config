#!/usr/bin/env bash
# Final whole-plan review — runs after all items complete.
# Spawns a reviewer agent that evaluates the full diff, then
# updates finalReview in state.json with SHIP or REVISE.
#
# Usage: scripts/orch-review.sh <slug>
#
# Requires: jq, claude CLI, orch-state.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-review.sh <slug>" >&2
	exit 1
fi

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_STATE_DIR}/state.json"
PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
	echo "error: state file not found: ${ORCH_STATE_FILE}" >&2
	exit 1
fi

if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

# --- Verify all items are done ---

NOT_DONE=$(jq '[.items[] | select(.status != "done")] | length' \
	"${ORCH_STATE_FILE}")

if [[ "${NOT_DONE}" -gt 0 ]]; then
	echo "error: ${NOT_DONE} items not done — final review requires all items complete" >&2
	jq -r '.items[] | select(.status != "done") |
    "  item \(.id): \(.description) (\(.status))"' "${ORCH_STATE_FILE}" >&2
	exit 1
fi

echo "orch-review: all items done — starting final whole-plan review"

# --- Mark final review as running ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq --arg now "${NOW}" \
	'.finalReview.status = "running" | .updatedAt = $now' \
	"${ORCH_STATE_FILE}")
orch_write_state "${UPDATED}"

# --- Build reviewer prompt ---

REVIEW_PROMPT="# Final Whole-Plan Review

You are reviewing the FULL output of plan '${SLUG}' after all items completed.
Your job: evaluate whether the plan's completion criteria are satisfied by the
combined work. Decide SHIP or REVISE.

## Plan

Read: ${PLAN_DIR}/plan.md
Focus on the **Completion criteria** section — that is your acceptance test.

## Evidence

1. Read the plan's completion criteria
2. Run \`git diff HEAD\` to see all uncommitted changes
3. Read ${PLAN_DIR}/work-summary.txt for the last worker's summary
4. Check that every completion criterion is satisfied

## Decision

Write your decision to: ${PLAN_DIR}/review-result.txt

First line must be exactly \`SHIP\` or \`REVISE\`. Nothing else on that line.

If SHIP:
\`\`\`
SHIP
\`\`\`

If REVISE, also write ${PLAN_DIR}/review-feedback.txt with:
- Which completion criteria failed
- Which plan items (by number) need rework
- Specific, actionable fixes

Format for review-feedback.txt:
\`\`\`
REWORK_ITEMS: 3, 7
CRITERION: <which completion criterion failed>
FINDING: <what is missing, with file:line references>
ACTION: <what the worker must do>
\`\`\`

The first line must be \`REWORK_ITEMS: N, M\` listing item numbers that need
rework. One CRITERION/FINDING/ACTION block per failing criterion.

## Rules

- Evaluate evidence only — do not implement fixes
- Be strict: every completion criterion must pass for SHIP
- If the diff is empty but items are marked done, that is suspicious — REVISE
- You MUST write review-result.txt before stopping"

# --- Remove stale review files ---

rm -f "${PLAN_DIR}/review-result.txt" "${PLAN_DIR}/review-feedback.txt"

# --- Run reviewer agent ---

echo "orch-review: spawning reviewer agent..."
SESSION_ID="orch-review-${SLUG}-$(date +%s)"

RALPH_ROLE=reviewer RALPH_TASK_DIR="${PLAN_DIR}" RALPH_LOOP=1 \
	env -u CLAUDECODE claude -p \
	--session-id "${SESSION_ID}" \
	--dangerously-skip-permissions \
	"${REVIEW_PROMPT}" || true

echo "orch-review: reviewer done"

# --- Read decision ---

RESULT_FILE="${PLAN_DIR}/review-result.txt"

if [[ ! -f "${RESULT_FILE}" ]]; then
	echo "error: reviewer did not write review-result.txt" >&2
	# Reset final review status
	NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	UPDATED=$(jq --arg now "${NOW}" \
		'.finalReview.status = "pending" | .updatedAt = $now' \
		"${ORCH_STATE_FILE}")
	orch_write_state "${UPDATED}"
	exit 1
fi

DECISION=$(head -1 "${RESULT_FILE}" | tr -d '[:space:]')

case "${DECISION}" in
SHIP)
	echo "orch-review: SHIP — plan is complete"
	NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	UPDATED=$(jq --arg now "${NOW}" \
		'.finalReview.status = "done" |
     .finalReview.result = "SHIP" |
     .finalReview.reworkItems = [] |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${UPDATED}"
	;;
REVISE)
	echo "orch-review: REVISE — some items need rework"

	# Parse rework items from feedback
	REWORK_ITEMS="[]"
	FEEDBACK_FILE="${PLAN_DIR}/review-feedback.txt"
	if [[ -f "${FEEDBACK_FILE}" ]]; then
		REWORK_LINE=$(grep -i '^REWORK_ITEMS:' "${FEEDBACK_FILE}" | head -1 || true)
		if [[ -n "${REWORK_LINE}" ]]; then
			# Extract comma-separated numbers after the colon
			NUMS=$(echo "${REWORK_LINE}" | sed 's/^[^:]*://' | tr ',' '\n' | tr -d ' ' | grep -E '^[0-9]+$' || true)
			if [[ -n "${NUMS}" ]]; then
				REWORK_ITEMS=$(echo "${NUMS}" | jq -R 'tonumber' | jq -s '.')
			fi
		fi
		cat "${FEEDBACK_FILE}"
	fi

	NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	UPDATED=$(jq --arg now "${NOW}" --argjson rework "${REWORK_ITEMS}" \
		'.finalReview.status = "done" |
     .finalReview.result = "REVISE" |
     .finalReview.reworkItems = $rework |
     .updatedAt = $now |
     reduce ($rework[] | tostring | tonumber) as $id (.;
       (.items[] | select(.id == $id)).status = "ready"
     )' "${ORCH_STATE_FILE}")
	orch_write_state "${UPDATED}"

	echo ""
	echo "orch-review: rework items: $(echo "${REWORK_ITEMS}" | jq -r 'join(", ")')"
	echo "  Re-run orch-start.sh to schedule rework workers"
	;;
*)
	echo "error: unexpected review decision: '${DECISION}'" >&2
	echo "  Expected SHIP or REVISE as first line of ${RESULT_FILE}" >&2
	NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	UPDATED=$(jq --arg now "${NOW}" \
		'.finalReview.status = "pending" | .updatedAt = $now' \
		"${ORCH_STATE_FILE}")
	orch_write_state "${UPDATED}"
	exit 1
	;;
esac
