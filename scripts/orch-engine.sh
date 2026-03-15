#!/usr/bin/env bash
# Orchestrator engine — poll loop, worker spawning, review, and cleanup.
#
# Runs inside a tmux window (started by orch-run.sh). Drives workers to
# completion, invokes review, handles SHIP/REVISE outcomes, and cleans up.
#
# Usage: scripts/orch-engine.sh <slug> [--max-workers N] [--max-iterations N] [--background]
#
# This script is not invoked directly by users. orch-run.sh launches it
# inside a tmux window named "engine" in the orch-<slug> session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

# --- Parse args ---

SLUG=""
MAX_WORKERS=4
MAX_ITERATIONS=3
BACKGROUND=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--max-workers)
		MAX_WORKERS="${2:-4}"
		shift 2
		;;
	--max-iterations)
		MAX_ITERATIONS="${2:-3}"
		shift 2
		;;
	--background)
		BACKGROUND=true
		shift
		;;
	-*)
		echo "error: unknown option: $1" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-engine.sh <slug> [--max-workers N] [--max-iterations N] [--background]" >&2
	exit 1
fi

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

# Per-plan state paths
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
DONE_DIR=$(orch_plan_done_dir "${SLUG}")
REVIEW_DIR=$(orch_plan_review_dir "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
	echo "error: state.json not found — orch-run.sh must initialize first" >&2
	exit 1
fi

# --- Read current state ---

TOTAL_COUNT=$(jq '.items | length' "${ORCH_STATE_FILE}")

# --- Read poll interval from ralph.yaml ---

POLL_INTERVAL=$(grep 'poll_interval_seconds:' ralph.yaml 2>/dev/null |
	awk '{print $2}' | tr -d ' ' || true)
POLL_INTERVAL="${POLL_INTERVAL:-30}"

# --- Worker prompt template ---

WORKER_PROMPT_TEMPLATE="${SCRIPT_DIR}/../agents/orch-worker.md"
if [[ ! -f "${WORKER_PROMPT_TEMPLATE}" ]]; then
	echo "error: worker prompt not found: ${WORKER_PROMPT_TEMPLATE}" >&2
	exit 1
fi
WORKER_PROMPT_BASE=$(cat "${WORKER_PROMPT_TEMPLATE}")

# --- Tmux session name ---

TMUX_SESSION="orch-${SLUG}"

# --- Helper: build worker prompt for an item ---

build_worker_prompt() {
	local item_id="$1"
	local item_desc="$2"
	local plan_path="${PLAN_DIR}/plan.md"
	local done_dir="${DONE_DIR}"

	# Gather dependency summaries (cap at 5)
	local dep_context=""
	local dep_ids
	dep_ids=$(jq -r ".items[] | select(.id == ${item_id}) | .deps[]" \
		"${ORCH_STATE_FILE}" 2>/dev/null || true)
	local dep_count=0
	for dep_id in ${dep_ids}; do
		if ((dep_count >= 5)); then break; fi
		local dep_file="${done_dir}/item-${dep_id}.txt"
		if [[ -f "${dep_file}" ]]; then
			local dep_desc
			dep_desc=$(jq -r ".items[] | select(.id == ${dep_id}) | .description" \
				"${ORCH_STATE_FILE}")
			dep_context="${dep_context}
### Item ${dep_id}: ${dep_desc}
$(cat "${dep_file}")
"
			dep_count=$((dep_count + 1))
		fi
	done

	# Check for per-item review feedback (rework iterations)
	local review_file="${REVIEW_DIR}/item-${item_id}-review.txt"
	local review_context=""
	if [[ -f "${review_file}" ]]; then
		review_context="
## Review feedback

The reviewer flagged issues with your previous work on this item.
Address every point below before writing your done-file.

$(cat "${review_file}")
"
	fi

	cat <<-PROMPT
		${WORKER_PROMPT_BASE}

		---

		## Your Assignment

		- **Item ID**: ${item_id}
		- **Item description**: ${item_desc}
		- **Plan path**: ${plan_path}
		- **Done-files directory**: ${done_dir}
		- **Worktree**: ${WORKTREE_DIR}

		## Completed dependency summaries
		${dep_context:-"(no dependencies)"}
		${review_context}
	PROMPT
}

# --- Helper: spawn a worker in a tmux pane ---

spawn_worker() {
	local item_id="$1"
	local item_desc="$2"
	local pane_name="worker-${item_id}"

	# Mark item as running
	orch_update_item_status "${SLUG}" "${item_id}" "running"

	# Build prompt
	local prompt
	prompt=$(build_worker_prompt "${item_id}" "${item_desc}")

	# Write prompt to temp file (tmux send-keys has length limits)
	local prompt_file
	prompt_file=$(mktemp "${ORCH_STATE_DIR}/prompt-${item_id}-XXXXXX")
	mv "${prompt_file}" "${prompt_file}.md"
	prompt_file="${prompt_file}.md"
	printf '%s\n' "${prompt}" >"${prompt_file}"

	# Create tmux window and run claude worker
	# Foreground: interactive TUI (full claude). Background: headless (claude -p).
	local claude_cmd
	if [[ "${BACKGROUND}" == true ]]; then
		claude_cmd="claude -p --dangerously-skip-permissions \"\$(cat '${prompt_file}')\""
	else
		claude_cmd="claude --dangerously-skip-permissions \"\$(cat '${prompt_file}')\""
	fi

	# Kill stale window from previous iteration if it exists
	tmux kill-window -t "${TMUX_SESSION}:${pane_name}" 2>/dev/null || true

	# Spawn in background (-d) so dashboard keeps focus
	tmux new-window -d -t "${TMUX_SESSION}" -n "${pane_name}" \
		"cd '${WORKTREE_DIR}' && \
		 RALPH_ROLE=worker RALPH_TASK_DIR='${PLAN_DIR}' \
		 env -u CLAUDECODE ${claude_cmd} ; \
		 echo '--- worker ${item_id} exited ---'; \
		 sleep 5"

	# Stream worker output to log file for the dashboard
	tmux pipe-pane -t "${TMUX_SESSION}:${pane_name}" \
		-o "cat >> '${LOG_DIR}/worker-${item_id}.log'"

	echo "orch-engine: spawned ${pane_name} for item ${item_id}: ${item_desc}"
}

# --- Wave execution loop ---

echo ""
echo "orch-engine: starting wave execution"
echo "  plan: ${SLUG}"
echo "  total items: ${TOTAL_COUNT}"
echo "  max workers: ${MAX_WORKERS}"
echo "  worktree: ${WORKTREE_DIR}"
echo "  poll interval: ${POLL_INTERVAL}s"
echo ""

while true; do
	# Sync done-files, kill finished windows, detect stale workers, promote
	orch_sync_done_files "${SLUG}"
	orch_kill_done_workers "${SLUG}"
	orch_detect_stale_workers "${SLUG}"
	orch_promote_ready_items "${SLUG}"

	# Update master state with current progress
	orch_master_update_progress "${SLUG}"

	# Count current state
	local_failed=$(orch_count_by_status "${SLUG}" "failed")
	local_done=$(orch_count_by_status "${SLUG}" "done")
	local_running=$(orch_count_by_status "${SLUG}" "running")
	local_ready=$(orch_count_by_status "${SLUG}" "ready")
	local_queued=$(orch_count_by_status "${SLUG}" "queued")

	echo "orch-engine: [poll] done=${local_done} running=${local_running} ready=${local_ready} queued=${local_queued} failed=${local_failed}"

	# Check if all items are done
	if [[ "${local_running}" -eq 0 ]] && [[ "${local_ready}" -eq 0 ]] && [[ "${local_queued}" -eq 0 ]]; then
		echo ""
		echo "orch-engine: all ${TOTAL_COUNT} items complete"
		break
	fi

	# Spawn workers for ready items up to max concurrency
	available_slots=$((MAX_WORKERS - local_running))
	if ((available_slots > 0 && local_ready > 0)); then
		ready_ids=$(jq -r '.items[] | select(.status == "ready") | .id' \
			"${ORCH_STATE_FILE}")
		spawned=0
		for rid in ${ready_ids}; do
			if ((spawned >= available_slots)); then break; fi

			# Check max-iterations guard before spawning
			cur_iter=$(jq ".items[] | select(.id == ${rid}) | .iteration // 0" \
				"${ORCH_STATE_FILE}")
			max_iter=$(jq ".items[] | select(.id == ${rid}) | .maxIterations // 3" \
				"${ORCH_STATE_FILE}")
			if ((cur_iter >= max_iter)); then
				echo "orch-engine: item ${rid} exhausted ${max_iter} iterations — marking failed"
				now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
				updated=$(jq \
					--argjson id "${rid}" \
					--arg now "${now}" \
					'(.items[] | select(.id == $id)) |=
					  (.status = "failed" | .lastResult = "review-max-retries") |
					 .updatedAt = $now' "${ORCH_STATE_FILE}")
				orch_write_state "${SLUG}" "${updated}"
				continue
			fi

			rdesc=$(jq -r ".items[] | select(.id == ${rid}) | .description" \
				"${ORCH_STATE_FILE}")
			spawn_worker "${rid}" "${rdesc}"
			spawned=$((spawned + 1))
		done
	fi

	# Sleep before next poll
	sleep "${POLL_INTERVAL}"
done

# --- Post-completion: run per-item review ---

echo "orch-engine: running per-item review via orch-review.sh"
"${SCRIPT_DIR}/orch-review.sh" "${SLUG}"

# Read review result from state
REVIEW_RESULT=$(jq -r '.finalReview.result // "UNKNOWN"' "${ORCH_STATE_FILE}")

if [[ "${REVIEW_RESULT}" == "SHIP" ]]; then
	echo ""
	echo "orch-engine: review passed — checking completion criteria"

	# --- Completion criteria gate ---
	CC_UNCHECKED=$(orch_count_unchecked_criteria "${PLAN_DIR}/plan.md")

	if [[ "${CC_UNCHECKED}" -gt 0 ]]; then
		echo "orch-engine: ${CC_UNCHECKED} unchecked completion criteria — spawning verifier"

		# Update state with verification status
		now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
		updated=$(jq \
			--arg now "${now}" \
			--argjson count "${CC_UNCHECKED}" \
			'.verification = {
				status: "running",
				uncheckedCount: $count,
				iteration: ((.verification.iteration // 0) + 1)
			} |
			.updatedAt = $now' "${ORCH_STATE_FILE}")
		orch_write_state "${SLUG}" "${updated}"

		if "${SCRIPT_DIR}/orch-verify.sh" "${SLUG}"; then
			# Verifier succeeded — re-check criteria
			CC_AFTER=$(orch_count_unchecked_criteria "${PLAN_DIR}/plan.md")
			if [[ "${CC_AFTER}" -gt 0 ]]; then
				echo "orch-engine: verifier finished but ${CC_AFTER} criteria still unchecked — REVISE"
				now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
				updated=$(jq \
					--arg now "${now}" \
					--argjson count "${CC_AFTER}" \
					'.verification.status = "failed" |
					 .verification.uncheckedCount = $count |
					 .updatedAt = $now' "${ORCH_STATE_FILE}")
				orch_write_state "${SLUG}" "${updated}"
				REVIEW_RESULT="REVISE"
			else
				echo "orch-engine: all completion criteria verified"
				now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
				updated=$(jq \
					--arg now "${now}" \
					'.verification.status = "passed" |
					 .verification.uncheckedCount = 0 |
					 .updatedAt = $now' "${ORCH_STATE_FILE}")
				orch_write_state "${SLUG}" "${updated}"
			fi
		else
			echo "orch-engine: verifier failed — REVISE"
			now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
			updated=$(jq \
				--arg now "${now}" \
				'.verification.status = "failed" |
				 .updatedAt = $now' "${ORCH_STATE_FILE}")
			orch_write_state "${SLUG}" "${updated}"
			REVIEW_RESULT="REVISE"
		fi
	else
		echo "orch-engine: all completion criteria already checked"
		now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
		updated=$(jq \
			--arg now "${now}" \
			'.verification = {
				status: "passed",
				uncheckedCount: 0,
				iteration: 0
			} |
			.updatedAt = $now' "${ORCH_STATE_FILE}")
		orch_write_state "${SLUG}" "${updated}"
	fi
fi

# --- Actual SHIP / REVISE handling ---

if [[ "${REVIEW_RESULT}" == "SHIP" ]]; then
	echo ""
	echo "orch-engine: SHIP — all items passed review and completion criteria verified"
	# Play completion sound if available
	if [[ -x "${SCRIPT_DIR}/../hooks/play-sound.sh" ]]; then
		bash "${SCRIPT_DIR}/../hooks/play-sound.sh" "success" || true
	fi
	# Merge worker changes, deregister, and clean up worktree
	orch_merge_worktree "${SLUG}"
	orch_master_deregister "${SLUG}" "completed"
	orch_cleanup_worktree "${SLUG}"
	# Write completed status so the dashboard renders a final SHIP screen
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	updated=$(jq \
		--arg now "${now}" \
		'.status = "completed" | .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${SLUG}" "${updated}"

	# Preserve final state.json (with completed status) in the exec-plan directory
	COMPLETED_DIR="${REPO_ROOT}/docs/exec-plans/completed/${SLUG}"
	if [[ -d "${COMPLETED_DIR}" ]]; then
		cp "${ORCH_STATE_FILE}" "${COMPLETED_DIR}/state.json"
		echo "orch-engine: state.json saved to ${COMPLETED_DIR}/state.json"
	fi

	# Log path message (log written by tee in orch-run.sh)
	echo "orch-engine: log saved to .orchestrator/plans/${SLUG}/logs/engine.log"

	# Give the dashboard time to render the final screen
	sleep 5
	# Clean up tmux session
	tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
	echo "orch-engine: tmux session '${TMUX_SESSION}' cleaned up"
elif [[ "${REVIEW_RESULT}" == "REVISE" ]]; then
	echo ""
	echo "orch-engine: REVISE — some items need rework"
	echo "  Re-running wave execution for rework items..."
	echo ""

	# Update master progress before re-exec
	orch_master_update_progress "${SLUG}"

	# Re-exec engine for rework pass (review already reset items to "ready")
	BACKGROUND_FLAG=""
	if [[ "${BACKGROUND}" == true ]]; then
		BACKGROUND_FLAG="--background"
	fi
	# shellcheck disable=SC2086
	exec "${SCRIPT_DIR}/orch-engine.sh" "${SLUG}" --max-workers "${MAX_WORKERS}" --max-iterations "${MAX_ITERATIONS}" ${BACKGROUND_FLAG}
else
	echo "orch-engine: unexpected review result: ${REVIEW_RESULT}" >&2
	orch_master_deregister "${SLUG}" "failed"
	orch_cleanup_worktree "${SLUG}"
	# Write failed status so the dashboard renders a final screen
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	updated=$(jq \
		--arg now "${now}" \
		'.status = "failed" | .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${SLUG}" "${updated}"
	sleep 5
	tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
	exit 1
fi
