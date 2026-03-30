#!/usr/bin/env bash
# Final per-item review — runs after all items settle (done or failed).
# Spawns reviewer agents in parallel via tmux windows, polls for review
# files, respects max-workers concurrency. Failed work items are skipped.
# All reviewed items must PASS for SHIP; any failures trigger REVISE.
#
# Usage: scripts/orch-review.sh <slug>
#
# Requires: jq, agent CLI (claude/gemini/codex), tmux, orch-state.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-review.sh <slug>" >&2
	exit 1
fi

PROMPT_TEMPLATE="${SCRIPT_DIR}/ralph-item-reviewer-prompt.md"

# GH_SYNC flag — exported by orch-run.sh when github.sync is true
GH_SYNC="${GH_SYNC:-false}"

# Per-plan paths from orch-state.sh helpers
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
DONE_DIR=$(orch_plan_done_dir "${SLUG}")
REVIEW_DIR=$(orch_plan_review_dir "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

# Use worktree plan path; in GH mode resolve from .orchestrator/
if [[ "${GH_SYNC}" == true ]]; then
	PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"
elif [[ -d "${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}" ]]; then
	PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"
else
	PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
fi

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

# --- Structural check: all items settled (done or failed) ---

TOTAL=$(jq '.items | length' "${ORCH_STATE_FILE}")
CNT_DONE=$(jq '[.items[] | select(.status == "done")] | length' \
	"${ORCH_STATE_FILE}")
CNT_FAILED=$(jq '[.items[] | select(.status == "failed")] | length' \
	"${ORCH_STATE_FILE}")
CNT_IN_PROGRESS=$(jq \
	'[.items[] | select(.status != "done" and .status != "failed")] | length' \
	"${ORCH_STATE_FILE}")

if [[ "${CNT_IN_PROGRESS}" -gt 0 ]]; then
	echo "error: ${CNT_IN_PROGRESS} items still in progress — review requires all items settled" >&2
	jq -r '.items[] | select(.status != "done" and .status != "failed") |
    "  item \(.id): \(.description) (\(.status))"' "${ORCH_STATE_FILE}" >&2
	exit 1
fi

if [[ "${CNT_DONE}" -eq 0 ]]; then
	echo "error: no items completed — nothing to review (${CNT_FAILED} failed)" >&2
	exit 1
fi

if [[ "${CNT_FAILED}" -gt 0 ]]; then
	echo "orch-review: ${CNT_DONE}/${TOTAL} items done, ${CNT_FAILED} failed — reviewing done items only"
	jq -r '.items[] | select(.status == "failed") |
    "  skipping item \(.id): \(.description) (failed)"' "${ORCH_STATE_FILE}"
else
	echo "orch-review: all ${TOTAL} items done — starting per-item review"
fi

# --- Read concurrency and poll settings from state ---

MAX_WORKERS=$(jq '.maxParallelWorkers // 4' "${ORCH_STATE_FILE}")
POLL_INTERVAL=$(orch_read_config "review_poll_interval_seconds")
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# --- Mark failed work items as review-skipped ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq --arg now "${NOW}" \
	'(.items[] | select(.status == "failed")).reviewStatus = "skipped" |
	 .finalReview.status = "running" |
	 .updatedAt = $now' "${ORCH_STATE_FILE}")
orch_write_state "${SLUG}" "${UPDATED}"

# --- Prepare review directory ---

mkdir -p "${REVIEW_DIR}"

# --- Tmux session ---

TMUX_SESSION="orch-${SLUG}"

# --- Helper: spawn a reviewer in a tmux window ---

spawn_reviewer() {
	local item_id="$1"
	local item_desc="$2"
	local window_name="reviewer-${item_id}"

	# Mark reviewStatus as "reviewing"
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	local updated
	updated=$(jq \
		--argjson id "${item_id}" \
		--arg now "${now}" \
		'(.items[] | select(.id == $id)).reviewStatus = "reviewing" |
		 .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${SLUG}" "${updated}"

	# Read done-file as handoff context
	local done_file="${DONE_DIR}/item-${item_id}.txt"
	local item_handoff
	if [[ -f "${done_file}" ]]; then
		item_handoff=$(cat "${done_file}")
	else
		item_handoff="(no done-file found — worker may not have written a summary)"
	fi

	# Build prompt from template
	local review_prompt
	review_prompt=$(cat "${PROMPT_TEMPLATE}")
	review_prompt="${review_prompt//\{ITEM_TEXT\}/${item_desc}}"
	review_prompt="${review_prompt//\{ITEM_HANDOFF\}/${item_handoff}}"
	review_prompt="${review_prompt//\{REVIEW_DIR\}/${REVIEW_DIR}}"
	review_prompt="${review_prompt//\{ITEM_NUM\}/${item_id}}"

	# Write prompt to temp file (tmux send-keys has length limits)
	local prompt_file
	prompt_file=$(mktemp "${ORCH_STATE_DIR}/reviewer-prompt-${item_id}-XXXXXX")
	mv "${prompt_file}" "${prompt_file}.md"
	prompt_file="${prompt_file}.md"
	printf '%s\n' "${review_prompt}" >"${prompt_file}"

	# Remove stale review file
	rm -f "${REVIEW_DIR}/item-${item_id}-review.txt"

	# Determine working directory
	local review_cwd="${REPO_ROOT}"
	if [[ -d "${WORKTREE_DIR}" ]]; then
		review_cwd="${WORKTREE_DIR}"
	fi

	# Kill stale window from previous iteration if it exists
	tmux kill-window -t "${TMUX_SESSION}:${window_name}" 2>/dev/null || true

	# Build agent command using shim helper (handles Codex exec pattern)
	local cmd_template agent_cmd_str
	cmd_template="$(dega_agent_build_headless_cmd "DEGA_PROMPT_MARKER")"
	agent_cmd_str="${cmd_template/DEGA_PROMPT_MARKER/\"\$(cat '${prompt_file}')\"}"

	# Skip env -u when session var is empty (e.g., Codex has no session var)
	local session_var
	session_var="$(dega_agent_session_var)"
	local env_prefix=""
	if [[ -n "${session_var}" ]]; then
		env_prefix="env -u '${session_var}'"
	fi

	tmux new-window -d -t "${TMUX_SESSION}" -n "${window_name}" \
		"cd '${review_cwd}' && \
		 GH_SYNC='${GH_SYNC}' \
		 RALPH_ROLE=reviewer RALPH_TASK_DIR='${PLAN_DIR}' RALPH_LOOP=1 \
		 ${env_prefix} ${agent_cmd_str} ; \
		 echo '--- reviewer ${item_id} exited ---'; \
		 sleep 2"

	# Stream reviewer output to log file
	tmux pipe-pane -t "${TMUX_SESSION}:${window_name}" \
		-o "cat >> '${LOG_DIR}/reviewer-${item_id}.log'"

	echo "orch-review: spawned ${window_name} for item ${item_id}: ${item_desc}"
}

# --- Helper: kill finished reviewer windows ---

kill_done_reviewers() {
	if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
		return 0
	fi

	local done_statuses
	done_statuses=$(jq -r \
		'.items[] | select(.reviewStatus == "passed" or .reviewStatus == "failed") | .id' \
		"${ORCH_STATE_FILE}")

	if [[ -z "${done_statuses}" ]]; then
		return 0
	fi

	local live_windows
	live_windows=$(tmux list-windows -t "${TMUX_SESSION}" \
		-F '#{window_name}' 2>/dev/null || true)

	for item_id in ${done_statuses}; do
		local window_name="reviewer-${item_id}"
		if printf '%s\n' "${live_windows}" | grep -qx "${window_name}"; then
			tmux kill-window -t "${TMUX_SESSION}:${window_name}" 2>/dev/null || true
			echo "orch-review: killed finished reviewer window ${window_name}"
		fi
	done
}

# --- Helper: detect stale reviewers (window dead, no review file) ---

detect_stale_reviewers() {
	if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
		return 0
	fi

	local reviewing_ids
	reviewing_ids=$(jq -r \
		'.items[] | select(.reviewStatus == "reviewing") | .id' \
		"${ORCH_STATE_FILE}")

	if [[ -z "${reviewing_ids}" ]]; then
		return 0
	fi

	local live_windows
	live_windows=$(tmux list-windows -t "${TMUX_SESSION}" \
		-F '#{window_name} #{pane_dead}' 2>/dev/null || true)

	local state
	state=$(cat "${ORCH_STATE_FILE}")
	local changed=false
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	for item_id in ${reviewing_ids}; do
		local window_name="reviewer-${item_id}"
		local is_alive=false

		if printf '%s\n' "${live_windows}" | grep -q "^${window_name} 0$"; then
			is_alive=true
		fi

		if [[ "${is_alive}" == false ]]; then
			# Reviewer exited without writing review file — mark failed
			state=$(printf '%s' "${state}" | jq \
				--argjson id "${item_id}" \
				--arg now "${now}" \
				'(.items[] | select(.id == $id)).reviewStatus = "failed" |
				 .updatedAt = $now')
			echo "orch-review: reviewer for item ${item_id} exited without writing review — marking failed"
			changed=true
		fi
	done

	if [[ "${changed}" == "true" ]]; then
		orch_write_state "${SLUG}" "${state}"
	fi
}

# --- Poll loop: spawn reviewers and wait for completion ---

echo "orch-review: starting parallel review"
echo "  max concurrent reviewers: ${MAX_WORKERS}"
echo "  poll interval: ${POLL_INTERVAL}s"
echo ""

while true; do
	# Sync review files into state, clean up finished windows, detect stale
	orch_sync_review_files "${SLUG}"
	kill_done_reviewers
	detect_stale_reviewers

	# Count current review state
	cnt_reviewing=$(jq '[.items[] | select(.reviewStatus == "reviewing")] | length' \
		"${ORCH_STATE_FILE}")
	cnt_pending=$(jq '[.items[] | select(.reviewStatus == "pending")] | length' \
		"${ORCH_STATE_FILE}")
	cnt_passed=$(jq '[.items[] | select(.reviewStatus == "passed")] | length' \
		"${ORCH_STATE_FILE}")
	cnt_failed=$(jq '[.items[] | select(.reviewStatus == "failed")] | length' \
		"${ORCH_STATE_FILE}")
	cnt_skipped=$(jq '[.items[] | select(.reviewStatus == "skipped")] | length' \
		"${ORCH_STATE_FILE}")

	echo "orch-review: [poll] reviewing=${cnt_reviewing} pending=${cnt_pending} passed=${cnt_passed} failed=${cnt_failed} skipped=${cnt_skipped}"

	# All reviews complete when nothing is reviewing or pending
	if [[ "${cnt_reviewing}" -eq 0 ]] && [[ "${cnt_pending}" -eq 0 ]]; then
		echo ""
		echo "orch-review: reviews complete — ${cnt_passed} passed, ${cnt_failed} failed, ${cnt_skipped} skipped"
		break
	fi

	# Spawn reviewers for pending items up to max concurrency
	available_slots=$((MAX_WORKERS - cnt_reviewing))
	if ((available_slots > 0 && cnt_pending > 0)); then
		pending_ids=$(jq -r '.items[] | select(.reviewStatus == "pending") | .id' \
			"${ORCH_STATE_FILE}")
		spawned=0
		for pid in ${pending_ids}; do
			if ((spawned >= available_slots)); then break; fi
			pdesc=$(jq -r ".items[] | select(.id == ${pid}) | .description" \
				"${ORCH_STATE_FILE}")
			spawn_reviewer "${pid}" "${pdesc}"
			spawned=$((spawned + 1))
		done
	fi

	sleep "${POLL_INTERVAL}"
done

# --- Aggregate decision ---

# Review-failed: items that were reviewed and failed review
REVIEW_FAILED_IDS=$(jq -r '.items[] | select(.reviewStatus == "failed") | .id' \
	"${ORCH_STATE_FILE}")
REVIEW_FAILED=()
for fid in ${REVIEW_FAILED_IDS}; do
	REVIEW_FAILED+=("${fid}")
done

# Work-failed: items that failed execution and were skipped by review
WORK_FAILED_IDS=$(jq -r '.items[] | select(.reviewStatus == "skipped") | .id' \
	"${ORCH_STATE_FILE}")
WORK_FAILED=()
for fid in ${WORK_FAILED_IDS}; do
	WORK_FAILED+=("${fid}")
done

# SHIP/REVISE decision based on review failures only —
# work-failed items are logged but don't block SHIP
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ ${#REVIEW_FAILED[@]} -eq 0 ]]; then
	echo ""
	if [[ ${#WORK_FAILED[@]} -gt 0 ]]; then
		echo "orch-review: SHIP — all reviewed items passed (${#WORK_FAILED[@]} work-failed items skipped)"
	else
		echo "orch-review: SHIP — all ${TOTAL} items passed"
	fi

	UPDATED=$(jq --arg now "${NOW}" \
		'.finalReview.status = "done" |
     .finalReview.result = "SHIP" |
     .finalReview.reworkItems = [] |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${SLUG}" "${UPDATED}"
else
	echo ""
	echo "orch-review: REVISE — ${#REVIEW_FAILED[@]} item(s) failed review"
	if [[ ${#WORK_FAILED[@]} -gt 0 ]]; then
		echo "orch-review: (${#WORK_FAILED[@]} work-failed items also skipped)"
	fi

	# Build JSON array of rework item IDs (review failures only)
	REWORK_JSON=$(printf '%s\n' "${REVIEW_FAILED[@]}" | jq -R 'tonumber' | jq -s '.')

	UPDATED=$(jq --arg now "${NOW}" --argjson rework "${REWORK_JSON}" \
		'.finalReview.status = "done" |
     .finalReview.result = "REVISE" |
     .finalReview.reworkItems = $rework |
     .updatedAt = $now |
     reduce ($rework[] | tostring | tonumber) as $id (.;
       (.items[] | select(.id == $id)) |=
         (.status = "ready" | .iteration = (.iteration + 1) | .reviewStatus = "pending")
     )' "${ORCH_STATE_FILE}")
	orch_write_state "${SLUG}" "${UPDATED}"

	# Write consolidated feedback for the loop
	FEEDBACK_FILE="${PLAN_DIR}/review-feedback.txt"
	{
		printf 'REWORK_ITEMS: %s\n' "$(printf '%s\n' "${REVIEW_FAILED[@]}" | paste -sd ', ' -)"
		for fid in "${REVIEW_FAILED[@]}"; do
			review="${REVIEW_DIR}/item-${fid}-review.txt"
			if [[ -f "${review}" ]]; then
				printf '\n--- item %s (review failed) ---\n' "${fid}"
				tail -n +2 "${review}"
			fi
		done
	} >"${FEEDBACK_FILE}"

	echo "orch-review: rework items: $(printf '%s\n' "${REVIEW_FAILED[@]}" | paste -sd ', ' -)"
	echo "  Feedback written to ${FEEDBACK_FILE}"
fi
