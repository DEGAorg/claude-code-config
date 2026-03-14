#!/usr/bin/env bash
# Orchestrator launcher — spawns workers in tmux panes by dependency wave.
#
# Reads per-plan state.json for incomplete items (or initializes from plan.md),
# then launches claude workers in tmux panes grouped by dependency waves.
# Each plan gets its own worktree for file isolation and registers in master.json.
#
# Usage: scripts/orch-run.sh <slug> [--max-workers N] [--background]
#
# Options:
#   --max-workers N   Max concurrent workers (default: 4)
#   --background      Headless mode — tmux only, no display windows
#
# Example: scripts/orch-run.sh 20260309-orch-smoke-test
# Example: scripts/orch-run.sh 20260309-orch-smoke-test --background

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

# --- Parse args ---

SLUG=""
MAX_WORKERS=4
BACKGROUND=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--max-workers)
		MAX_WORKERS="${2:-4}"
		shift 2
		;;
	--background)
		BACKGROUND=true
		shift
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-run.sh <slug> [--max-workers N] [--background]" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-run.sh <slug> [--max-workers N] [--background]" >&2
	exit 1
fi

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

# Per-plan state paths (from orch-state.sh helpers)
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
DONE_DIR=$(orch_plan_done_dir "${SLUG}")
REVIEW_DIR=$(orch_plan_review_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

# --- Initialize or resume state ---

init_state() {
	PARSED=$("${SCRIPT_DIR}/orch-parse-items.sh" "${SLUG}")
	ITEM_COUNT=$(printf '%s' "${PARSED}" | jq '.items | length')

	if [[ "${ITEM_COUNT}" -eq 0 ]]; then
		echo "error: no items found in plan" >&2
		exit 1
	fi

	orch_ensure_plan_dirs "${SLUG}"
	NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	MAX_ITER="${MAX_ITERATIONS:-3}"
	ITEMS_JSON=$(printf '%s' "${PARSED}" | jq --argjson maxIter "${MAX_ITER}" '[
	  .items[] | {
	    id: .id,
	    description: .description,
	    deps: .deps,
	    status: (if .checked then "done" else
	      (if (.deps | length) == 0 then "ready" else "queued" end)
	    end),
	    workerPid: null,
	    tmuxPane: null,
	    worktree: null,
	    iteration: 0,
	    maxIterations: $maxIter,
	    lastResult: null
	  }
	]')

	STATE_JSON=$(jq -n \
		--argjson version 1 \
		--arg plan "${SLUG}" \
		--argjson maxWorkers "${MAX_WORKERS}" \
		--argjson items "${ITEMS_JSON}" \
		--arg mode "foreground" \
		--arg startedAt "${NOW}" \
		--arg updatedAt "${NOW}" \
		'{
	    version: $version,
	    plan: $plan,
	    maxParallelWorkers: $maxWorkers,
	    mode: $mode,
	    items: $items,
	    finalReview: { status: "pending", result: null, reworkItems: [] },
	    startedAt: $startedAt,
	    updatedAt: $updatedAt
	  }')

	orch_write_state "${SLUG}" "${STATE_JSON}"
	orch_promote_ready_items "${SLUG}"
	echo "orch-run: initialized ${ITEM_COUNT} items for '${SLUG}'"
}

if [[ -f "${ORCH_STATE_FILE}" ]]; then
	EXISTING_PLAN=$(jq -r '.plan' "${ORCH_STATE_FILE}")
	if [[ "${EXISTING_PLAN}" == "${SLUG}" ]]; then
		echo "orch-run: resuming plan '${SLUG}' from existing state"
	else
		echo "orch-run: state.json is for '${EXISTING_PLAN}', re-initializing for '${SLUG}'"
		init_state
	fi
else
	echo "orch-run: initializing state for plan '${SLUG}'"
	init_state
fi

# --- Create worktree for file isolation ---

orch_create_worktree "${SLUG}"
echo "orch-run: workers will execute in worktree: ${WORKTREE_DIR}"

# --- Register in master state ---

orch_master_register "${SLUG}"

# --- Read incomplete items from state ---

REMAINING_JSON=$(jq '[.items[] | select(.status != "done")]' "${ORCH_STATE_FILE}")
REMAINING_COUNT=$(printf '%s' "${REMAINING_JSON}" | jq 'length')
TOTAL_COUNT=$(jq '.items | length' "${ORCH_STATE_FILE}")
DONE_COUNT=$(jq '[.items[] | select(.status == "done")] | length' "${ORCH_STATE_FILE}")

if [[ "${REMAINING_COUNT}" -eq 0 ]]; then
	echo "orch-run: all ${TOTAL_COUNT} items already complete"
	orch_master_deregister "${SLUG}" "completed"
	orch_cleanup_worktree "${SLUG}"
	exit 0
fi

echo "orch-run: ${DONE_COUNT}/${TOTAL_COUNT} done, ${REMAINING_COUNT} remaining"

# --- Update master progress with initial counts ---

orch_master_update_progress "${SLUG}"

# --- Gather done-file summaries for completed items ---

COMPLETED_CONTEXT=""

DONE_IDS=$(jq -r '.items[] | select(.status == "done") | .id' "${ORCH_STATE_FILE}")
for done_id in ${DONE_IDS}; do
	done_file="${DONE_DIR}/item-${done_id}.txt"
	if [[ -f "${done_file}" ]]; then
		done_desc=$(jq -r ".items[] | select(.id == ${done_id}) | .description" \
			"${ORCH_STATE_FILE}")
		COMPLETED_CONTEXT="${COMPLETED_CONTEXT}
### Item ${done_id}: ${done_desc}
$(cat "${done_file}")
"
	fi
done

# --- Build remaining items description ---

ITEMS_DESC=""
while IFS= read -r item_json; do
	item_id=$(printf '%s' "${item_json}" | jq -r '.id')
	item_desc=$(printf '%s' "${item_json}" | jq -r '.description')
	item_deps=$(printf '%s' "${item_json}" | jq -r '.deps | if length > 0 then map(tostring) | join(", ") else "none" end')
	ITEMS_DESC="${ITEMS_DESC}
- **Item ${item_id}**: ${item_desc} (deps: ${item_deps})"
done < <(printf '%s' "${REMAINING_JSON}" | jq -c '.[]')

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

# --- Tmux session setup ---

TMUX_SESSION="orch-${SLUG}"

# Kill stale session if it exists but has no windows
if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
	echo "orch-run: attaching to existing tmux session '${TMUX_SESSION}'"
else
	TERMINAL_UI_CLI="${SCRIPT_DIR}/terminal-ui/dist/cli.js"
	# Dashboard command: restart on crash, stay alive until tmux session dies
	DASH_CMD="while true; do node '${TERMINAL_UI_CLI}' --orch '${ORCH_STATE_FILE}' 2>/dev/null; echo '[dashboard restarting in 3s...]'; sleep 3; done"
	# Create session with dashboard as the main window (keeps session alive)
	tmux new-session -d -s "${TMUX_SESSION}" -n "dashboard" "${DASH_CMD}"
	echo "orch-run: created tmux session '${TMUX_SESSION}' with Ink dashboard"
fi

# --- Open display windows (foreground mode) ---

if [[ "${BACKGROUND}" == false ]]; then
	bash "${SCRIPT_DIR}/orch-display.sh" "${TMUX_SESSION}" || true
else
	echo "orch-run: background mode — skipping display windows"
	echo "  Attach manually: tmux attach-session -t '${TMUX_SESSION}' -r"
fi

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

	tmux new-window -t "${TMUX_SESSION}" -n "${pane_name}" \
		"cd '${WORKTREE_DIR}' && \
		 RALPH_ROLE=worker RALPH_TASK_DIR='${PLAN_DIR}' \
		 env -u CLAUDECODE ${claude_cmd} ; \
		 echo '--- worker ${item_id} exited ---'; \
		 sleep 5"

	echo "orch-run: spawned ${pane_name} for item ${item_id}: ${item_desc}"
}

# --- Wave execution loop ---

echo ""
echo "orch-run: starting wave execution"
echo "  plan: ${SLUG}"
echo "  remaining: ${REMAINING_COUNT} items"
echo "  max workers: ${MAX_WORKERS}"
echo "  worktree: ${WORKTREE_DIR}"
echo "  poll interval: ${POLL_INTERVAL}s"
echo ""

while true; do
	# Sync done-files, detect stale workers, and promote newly unblocked items
	orch_sync_done_files "${SLUG}"
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

	echo "orch-run: [poll] done=${local_done} running=${local_running} ready=${local_ready} queued=${local_queued} failed=${local_failed}"

	# Check if all items are done
	if [[ "${local_running}" -eq 0 ]] && [[ "${local_ready}" -eq 0 ]] && [[ "${local_queued}" -eq 0 ]]; then
		echo ""
		echo "orch-run: all ${TOTAL_COUNT} items complete"
		break
	fi

	# Spawn workers for ready items up to max concurrency
	available_slots=$((MAX_WORKERS - local_running))
	if ((available_slots > 0 && local_ready > 0)); then
		# Get ready item IDs
		ready_ids=$(jq -r '.items[] | select(.status == "ready") | .id' \
			"${ORCH_STATE_FILE}")
		spawned=0
		for rid in ${ready_ids}; do
			if ((spawned >= available_slots)); then break; fi
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

echo "orch-run: running per-item review via orch-review.sh"
"${SCRIPT_DIR}/orch-review.sh" "${SLUG}"

# Read review result from state
REVIEW_RESULT=$(jq -r '.finalReview.result // "UNKNOWN"' "${ORCH_STATE_FILE}")

if [[ "${REVIEW_RESULT}" == "SHIP" ]]; then
	echo ""
	echo "orch-run: SHIP — all items passed review"
	# Play completion sound if available
	if [[ -x "${SCRIPT_DIR}/../hooks/play-sound.sh" ]]; then
		bash "${SCRIPT_DIR}/../hooks/play-sound.sh" "success" || true
	fi
	# Deregister from master and clean up worktree
	orch_master_deregister "${SLUG}" "completed"
	orch_cleanup_worktree "${SLUG}"
	# Clean up tmux session
	tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
	echo "orch-run: tmux session '${TMUX_SESSION}' cleaned up"
elif [[ "${REVIEW_RESULT}" == "REVISE" ]]; then
	echo ""
	echo "orch-run: REVISE — some items need rework"
	echo "  Review reset failed items to 'ready' in state.json"
	echo "  Re-running wave execution for rework items..."
	echo ""

	# Update master progress before re-exec
	orch_master_update_progress "${SLUG}"

	# Update counts and re-enter the wave loop
	# orch-review.sh already set failed items back to "ready"
	BACKGROUND_FLAG=""
	if [[ "${BACKGROUND}" == true ]]; then
		BACKGROUND_FLAG="--background"
	fi
	# shellcheck disable=SC2086
	exec "${SCRIPT_DIR}/orch-run.sh" "${SLUG}" --max-workers "${MAX_WORKERS}" ${BACKGROUND_FLAG}
else
	echo "orch-run: unexpected review result: ${REVIEW_RESULT}" >&2
	# Deregister as failed
	orch_master_deregister "${SLUG}" "failed"
	orch_cleanup_worktree "${SLUG}"
	exit 1
fi
