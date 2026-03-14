#!/usr/bin/env bash
# Final per-item review — runs after all items complete.
# For each item, spawns a focused reviewer agent using the done-file
# as handoff context. All items must PASS for SHIP.
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

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
PROMPT_TEMPLATE="${SCRIPT_DIR}/ralph-item-reviewer-prompt.md"

# Per-plan paths from orch-state.sh helpers
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
DONE_DIR=$(orch_plan_done_dir "${SLUG}")
REVIEW_DIR=$(orch_plan_review_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
	echo "error: state file not found: ${ORCH_STATE_FILE}" >&2
	exit 1
fi

if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

if [[ ! -f "${PROMPT_TEMPLATE}" ]]; then
	echo "error: reviewer prompt template not found: ${PROMPT_TEMPLATE}" >&2
	exit 1
fi

# --- Structural check: all items done ---

NOT_DONE=$(jq '[.items[] | select(.status != "done")] | length' \
	"${ORCH_STATE_FILE}")

if [[ "${NOT_DONE}" -gt 0 ]]; then
	echo "error: ${NOT_DONE} items not done — final review requires all items complete" >&2
	jq -r '.items[] | select(.status != "done") |
    "  item \(.id): \(.description) (\(.status))"' "${ORCH_STATE_FILE}" >&2
	exit 1
fi

TOTAL=$(jq '.items | length' "${ORCH_STATE_FILE}")
echo "orch-review: all ${TOTAL} items done — starting per-item review"

# --- Mark final review as running ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq --arg now "${NOW}" \
	'.finalReview.status = "running" | .updatedAt = $now' \
	"${ORCH_STATE_FILE}")
orch_write_state "${SLUG}" "${UPDATED}"

# --- Prepare review directory ---

mkdir -p "${REVIEW_DIR}"

# --- Per-item review loop ---

ITEM_IDS=$(jq -r '.items | sort_by(.id) | .[].id' "${ORCH_STATE_FILE}")
FAILED_ITEMS=()

for item_id in ${ITEM_IDS}; do
	ITEM_DESC=$(jq -r ".items[] | select(.id == ${item_id}) | .description" \
		"${ORCH_STATE_FILE}")
	REVIEW_FILE="${REVIEW_DIR}/item-${item_id}-review.txt"

	echo "orch-review: reviewing item ${item_id}: ${ITEM_DESC}"

	# Read done-file as handoff context
	DONE_FILE="${DONE_DIR}/item-${item_id}.txt"
	ITEM_HANDOFF=""
	if [[ -f "${DONE_FILE}" ]]; then
		ITEM_HANDOFF=$(cat "${DONE_FILE}")
	else
		ITEM_HANDOFF="(no done-file found — worker may not have written a summary)"
	fi

	# Build prompt from template
	REVIEW_PROMPT=$(cat "${PROMPT_TEMPLATE}")
	REVIEW_PROMPT="${REVIEW_PROMPT//\{ITEM_TEXT\}/${ITEM_DESC}}"
	REVIEW_PROMPT="${REVIEW_PROMPT//\{ITEM_HANDOFF\}/${ITEM_HANDOFF}}"
	REVIEW_PROMPT="${REVIEW_PROMPT//\{REVIEW_DIR\}/${REVIEW_DIR}}"
	REVIEW_PROMPT="${REVIEW_PROMPT//\{ITEM_NUM\}/${item_id}}"

	# Remove stale review file
	rm -f "${REVIEW_FILE}"

	# Run reviewer in the worktree so it sees worker changes
	REVIEW_CWD="${REPO_ROOT}"
	if [[ -d "${WORKTREE_DIR}" ]]; then
		REVIEW_CWD="${WORKTREE_DIR}"
		echo "orch-review: running in worktree: ${WORKTREE_DIR}"
	fi

	# Spawn reviewer agent
	(cd "${REVIEW_CWD}" &&
		RALPH_ROLE=reviewer RALPH_TASK_DIR="${PLAN_DIR}" RALPH_LOOP=1 \
			env -u CLAUDECODE claude -p \
			--dangerously-skip-permissions \
			"${REVIEW_PROMPT}") || true

	# Read decision
	if [[ ! -f "${REVIEW_FILE}" ]]; then
		echo "orch-review: warning: reviewer did not write review for item ${item_id}" >&2
		FAILED_ITEMS+=("${item_id}")
		continue
	fi

	DECISION=$(head -1 "${REVIEW_FILE}" | tr -d '[:space:]')

	case "${DECISION}" in
	PASS)
		echo "orch-review: item ${item_id} — PASS"
		;;
	FAIL)
		echo "orch-review: item ${item_id} — FAIL"
		tail -n +2 "${REVIEW_FILE}"
		FAILED_ITEMS+=("${item_id}")
		;;
	*)
		echo "orch-review: item ${item_id} — unexpected decision: '${DECISION}'" >&2
		FAILED_ITEMS+=("${item_id}")
		;;
	esac
done

# --- Aggregate decision ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ ${#FAILED_ITEMS[@]} -eq 0 ]]; then
	echo ""
	echo "orch-review: SHIP — all ${TOTAL} items passed"

	UPDATED=$(jq --arg now "${NOW}" \
		'.finalReview.status = "done" |
     .finalReview.result = "SHIP" |
     .finalReview.reworkItems = [] |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${SLUG}" "${UPDATED}"
else
	echo ""
	echo "orch-review: REVISE — ${#FAILED_ITEMS[@]} item(s) failed"

	# Build JSON array of failed item IDs
	REWORK_JSON=$(printf '%s\n' "${FAILED_ITEMS[@]}" | jq -R 'tonumber' | jq -s '.')

	UPDATED=$(jq --arg now "${NOW}" --argjson rework "${REWORK_JSON}" \
		'.finalReview.status = "done" |
     .finalReview.result = "REVISE" |
     .finalReview.reworkItems = $rework |
     .updatedAt = $now |
     reduce ($rework[] | tostring | tonumber) as $id (.;
       (.items[] | select(.id == $id)).status = "ready"
     )' "${ORCH_STATE_FILE}")
	orch_write_state "${SLUG}" "${UPDATED}"

	# Write consolidated feedback for the loop
	FEEDBACK_FILE="${PLAN_DIR}/review-feedback.txt"
	{
		printf 'REWORK_ITEMS: %s\n' "$(printf '%s\n' "${FAILED_ITEMS[@]}" | paste -sd ', ' -)"
		for fid in "${FAILED_ITEMS[@]}"; do
			review="${REVIEW_DIR}/item-${fid}-review.txt"
			if [[ -f "${review}" ]]; then
				printf '\n--- item %s ---\n' "${fid}"
				tail -n +2 "${review}"
			fi
		done
	} >"${FEEDBACK_FILE}"

	echo "orch-review: rework items: $(printf '%s\n' "${FAILED_ITEMS[@]}" | paste -sd ', ' -)"
	echo "  Feedback written to ${FEEDBACK_FILE}"
fi
