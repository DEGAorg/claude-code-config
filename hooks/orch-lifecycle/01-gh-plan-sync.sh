#!/usr/bin/env bash
set -euo pipefail

# Lifecycle hook: sync orchestrator milestones to GitHub Issues.
#
# Called by orch-engine.sh at milestones with (event, slug, ...extra args).
# Reads issue number from state.json and per-item iteration counts,
# then delegates to scripts/gh-plan-sync.sh.
#
# Skips silently when:
#   - github.sync is not enabled in dega-core.yaml
#   - No issue number in state.json (local-only plan)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/../../scripts/gh-plan-sync.sh"

EVENT="${1:?usage: 01-gh-plan-sync.sh <event> <slug> [options]}"
SLUG="${2:?usage: 01-gh-plan-sync.sh <event> <slug> [options]}"
shift 2

# --- Check if GitHub sync is enabled ---

CONFIG_FILE="${REPO_ROOT}/dega-core.yaml"
if [[ ! -f "${CONFIG_FILE}" ]]; then
	exit 0
fi

SYNC_ENABLED=$(grep 'sync:' "${CONFIG_FILE}" 2>/dev/null |
	head -1 | awk '{print $2}' | tr -d ' ')
if [[ "${SYNC_ENABLED}" != "true" ]]; then
	exit 0
fi

# --- Resolve state file and issue number ---

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
STATE_FILE="${ORCH_STATE_DIR}/plans/${SLUG}/state.json"

if [[ ! -f "${STATE_FILE}" ]]; then
	echo "01-gh-plan-sync: no state.json for ${SLUG} — skipping" >&2
	exit 0
fi

ISSUE=$(jq -r '.issueNumber // empty' "${STATE_FILE}")

# Fallback: read from plan-meta.json if state.json has no issue number
if [[ -z "${ISSUE}" || "${ISSUE}" == "null" ]]; then
	PLAN_META="${ORCH_STATE_DIR}/plans/${SLUG}/plan-meta.json"
	if [[ -f "${PLAN_META}" ]]; then
		ISSUE=$(jq -r '.issue_number // empty' "${PLAN_META}")
	fi
fi

# Last resort: check worktree copy of plan-meta.json
if [[ -z "${ISSUE}" || "${ISSUE}" == "null" ]]; then
	WT_META="${ORCH_STATE_DIR}/worktrees/${SLUG}/.orchestrator/plans/${SLUG}/plan-meta.json"
	if [[ -f "${WT_META}" ]]; then
		ISSUE=$(jq -r '.issue_number // empty' "${WT_META}")
	fi
fi

if [[ -z "${ISSUE}" || "${ISSUE}" == "null" ]]; then
	exit 0
fi

# --- Idempotency: posted.json records keys for comments already posted ---
#
# Layout: .orchestrator/plans/<slug>/posted.json — JSON object keyed by
# "${event}:${item_id_or_plan}:${iteration}". Lock file lives next to it
# at posted.json.lock. The hook writes a key only after the sync script
# exits 0, so a transient gh failure leaves the key absent and the next
# poll retries.

POSTED_JSON="${ORCH_STATE_DIR}/plans/${SLUG}/posted.json"
POSTED_LOCK="${POSTED_JSON}.lock"

posted_has_key() {
	local key="$1"
	[[ -f "${POSTED_JSON}" ]] || return 1
	jq -e --arg k "${key}" 'has($k)' "${POSTED_JSON}" >/dev/null 2>&1
}

posted_record_key() {
	local key="$1"
	mkdir -p "$(dirname "${POSTED_JSON}")"
	(
		if command -v flock >/dev/null 2>&1; then
			flock 9 || true
		fi
		local existing='{}'
		if [[ -s "${POSTED_JSON}" ]]; then
			existing=$(cat "${POSTED_JSON}")
		fi
		local now
		now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
		printf '%s' "${existing}" |
			jq --arg k "${key}" --arg t "${now}" \
				'. + {($k): {"postedAt": $t}}' \
				>"${POSTED_JSON}.tmp"
		mv "${POSTED_JSON}.tmp" "${POSTED_JSON}"
	) 9>"${POSTED_LOCK}"
}

# --- Parse extra args passed by engine ---

ITEMS=""
MAX_WORKERS=""
PASSED=""
FAILED=""
ELAPSED=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--items)
		ITEMS="${2:-}"
		shift 2
		;;
	--max-workers)
		MAX_WORKERS="${2:-}"
		shift 2
		;;
	--passed)
		PASSED="${2:-}"
		shift 2
		;;
	--failed)
		FAILED="${2:-}"
		shift 2
		;;
	--elapsed)
		ELAPSED="${2:-}"
		shift 2
		;;
	*)
		shift
		;;
	esac
done

# --- Dispatch by event ---

PLAN_ITERATION=$(jq -r '.iteration // 0' "${STATE_FILE}" 2>/dev/null || echo 0)
VERIFY_ITERATION=$(jq -r '.verification.iteration // 0' "${STATE_FILE}" 2>/dev/null || echo 0)

case "${EVENT}" in
start)
	START_KEY="start:plan:${PLAN_ITERATION}"
	if posted_has_key "${START_KEY}"; then
		exit 0
	fi
	ARGS=(start "${SLUG}" --issue "${ISSUE}")
	if [[ -n "${ITEMS}" ]]; then
		ARGS+=(--items "${ITEMS}")
	fi
	if [[ -n "${MAX_WORKERS}" ]]; then
		ARGS+=(--max-workers "${MAX_WORKERS}")
	fi
	if "${SYNC_SCRIPT}" "${ARGS[@]}"; then
		posted_record_key "${START_KEY}"
	fi
	;;

review)
	# Post per-item review comments by reading state.json.
	# Each item with a lastResult gets a comment with its iteration count.
	ITEM_COUNT=$(jq '.items | length' "${STATE_FILE}")
	DONE_DIR="${ORCH_STATE_DIR}/plans/${SLUG}/done"
	REVIEW_DIR="${ORCH_STATE_DIR}/plans/${SLUG}/reviews"

	# Identify items that failed review (rework list from finalReview).
	REWORK_IDS=$(jq -r '.finalReview.reworkItems // [] | .[]' "${STATE_FILE}")

	for ((i = 0; i < ITEM_COUNT; i++)); do
		ITEM_RESULT=$(jq -r ".items[${i}].lastResult // empty" "${STATE_FILE}")
		if [[ -z "${ITEM_RESULT}" || "${ITEM_RESULT}" == "null" ]]; then
			continue
		fi
		ITEM_ID=$(jq -r ".items[${i}].id" "${STATE_FILE}")
		ITEM_DESC=$(jq -r ".items[${i}].description" "${STATE_FILE}")
		ITEM_ITER=$(jq -r ".items[${i}].iteration // 1" "${STATE_FILE}")

		ITEM_KEY="review:${ITEM_ID}:${ITEM_ITER}"
		if posted_has_key "${ITEM_KEY}"; then
			continue
		fi

		# Read per-item work summary: try done-file first, then
		# worktree plan-level work-summary.txt as fallback.
		WORK_SUMMARY=""
		DONE_FILE="${DONE_DIR}/item-${ITEM_ID}.txt"
		if [[ -f "${DONE_FILE}" ]]; then
			WORK_SUMMARY=$(cat "${DONE_FILE}")
		else
			for ws_path in \
				"${ORCH_STATE_DIR}/worktrees/${SLUG}/docs/exec-plans/active/${SLUG}/work-summary.txt" \
				"${ORCH_STATE_DIR}/worktrees/${SLUG}/.orchestrator/plans/${SLUG}/work-summary.txt"; do
				if [[ -f "${ws_path}" ]]; then
					WORK_SUMMARY=$(cat "${ws_path}")
					break
				fi
			done
		fi

		# Read review feedback for items that failed review.
		FEEDBACK=""
		if echo "${REWORK_IDS}" | grep -qw "${ITEM_ID}"; then
			ITEM_RESULT="REVISE"
			REVIEW_FILE="${REVIEW_DIR}/item-${ITEM_ID}-review.txt"
			if [[ -f "${REVIEW_FILE}" ]]; then
				FEEDBACK=$(tail -n +2 "${REVIEW_FILE}")
			fi
		fi

		ARGS=(review "${SLUG}" --issue "${ISSUE}")
		ARGS+=(--item-id "${ITEM_ID}")
		ARGS+=(--item-desc "${ITEM_DESC}")
		ARGS+=(--item-result "${ITEM_RESULT}")
		ARGS+=(--iterations "${ITEM_ITER}")
		if [[ -n "${WORK_SUMMARY}" ]]; then
			ARGS+=(--work-summary "${WORK_SUMMARY}")
		fi
		if [[ -n "${FEEDBACK}" ]]; then
			ARGS+=(--feedback "${FEEDBACK}")
		fi

		if "${SYNC_SCRIPT}" "${ARGS[@]}"; then
			posted_record_key "${ITEM_KEY}"
		fi
	done
	;;

ship)
	# Compute rework-count and total-reviews from per-item iterations.
	REWORK_COUNT=$(jq '[.items[] | select((.iteration // 0) > 0)] | length' \
		"${STATE_FILE}")
	TOTAL_REVIEWS=$(jq '[.items[].iteration // 0] | add // 0' \
		"${STATE_FILE}")

	ARGS=(ship "${SLUG}" --issue "${ISSUE}")
	if [[ -n "${ITEMS}" ]]; then
		ARGS+=(--items "${ITEMS}")
	fi
	if [[ -n "${PASSED}" ]]; then
		ARGS+=(--passed "${PASSED}")
	fi
	if [[ "${REWORK_COUNT}" -gt 0 ]]; then
		ARGS+=(--rework-count "${REWORK_COUNT}")
		ARGS+=(--total-reviews "${TOTAL_REVIEWS}")
	fi
	if [[ -n "${ELAPSED}" ]]; then
		ARGS+=(--elapsed "${ELAPSED}")
	fi
	SHIP_KEY="ship:plan:${PLAN_ITERATION}"
	if posted_has_key "${SHIP_KEY}"; then
		exit 0
	fi
	if "${SYNC_SCRIPT}" "${ARGS[@]}"; then
		posted_record_key "${SHIP_KEY}"
	fi
	;;

revise)
	# Build failed-details from state.json.
	FAILED_DETAILS=$(jq -r \
		'[.items[] | select(.status == "failed") | "Item \(.id) (\(.lastResult // "unknown"))"] | join(", ")' \
		"${STATE_FILE}")

	ARGS=(revise "${SLUG}" --issue "${ISSUE}")
	if [[ -n "${ITEMS}" ]]; then
		ARGS+=(--items "${ITEMS}")
	fi
	if [[ -n "${PASSED}" ]]; then
		ARGS+=(--passed "${PASSED}")
	fi
	if [[ -n "${FAILED}" ]]; then
		ARGS+=(--failed "${FAILED}")
	fi
	if [[ -n "${FAILED_DETAILS}" ]]; then
		ARGS+=(--failed-details "${FAILED_DETAILS}")
	fi
	if [[ -n "${ELAPSED}" ]]; then
		ARGS+=(--elapsed "${ELAPSED}")
	fi
	REVISE_KEY="revise:plan:${PLAN_ITERATION}"
	if posted_has_key "${REVISE_KEY}"; then
		exit 0
	fi
	if "${SYNC_SCRIPT}" "${ARGS[@]}"; then
		posted_record_key "${REVISE_KEY}"
	fi
	;;

verify)
	# Read verification status from state.json.
	VERIFY_STATUS=$(jq -r '.verification.status // empty' "${STATE_FILE}")
	if [[ -z "${VERIFY_STATUS}" || "${VERIFY_STATUS}" == "null" ]]; then
		echo "01-gh-plan-sync: no verification status in state.json — skipping" >&2
		exit 0
	fi

	VERIFY_RESULT="FAIL"
	if [[ "${VERIFY_STATUS}" == "passed" ]]; then
		VERIFY_RESULT="PASS"
	fi

	# Extract completion criteria from plan.md as details text.
	VERIFY_DETAILS=""
	for plan_path in \
		"${ORCH_STATE_DIR}/worktrees/${SLUG}/docs/exec-plans/active/${SLUG}/plan.md" \
		"${ORCH_STATE_DIR}/worktrees/${SLUG}/.orchestrator/plans/${SLUG}/plan.md" \
		"${REPO_ROOT}/docs/exec-plans/active/${SLUG}/plan.md"; do
		if [[ -f "${plan_path}" ]]; then
			VERIFY_DETAILS=$(awk '
				/^```/ { fence = !fence; next }
				fence { next }
				/^## Completion criteria/ { capturing = 1; next }
				capturing && /^## / { exit }
				capturing && /^- \[/ { print }
			' "${plan_path}")
			break
		fi
	done

	ARGS=(verify "${SLUG}" --issue "${ISSUE}")
	ARGS+=(--verify-result "${VERIFY_RESULT}")
	if [[ -n "${VERIFY_DETAILS}" ]]; then
		ARGS+=(--verify-details "${VERIFY_DETAILS}")
	fi
	VERIFY_KEY="verify:plan:${VERIFY_ITERATION}"
	if posted_has_key "${VERIFY_KEY}"; then
		exit 0
	fi
	if "${SYNC_SCRIPT}" "${ARGS[@]}"; then
		posted_record_key "${VERIFY_KEY}"
	fi
	;;

*)
	echo "01-gh-plan-sync: unknown event: ${EVENT} — skipping" >&2
	;;
esac
