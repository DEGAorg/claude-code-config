#!/usr/bin/env bash
# Orchestrator polling loop — drives the full plan lifecycle:
#   start workers → poll for done-files → schedule next wave → final review.
#
# Usage: scripts/orch-loop.sh <slug> [--timeout N] [--bg] [--max-workers N]
#   slug:          exec-plan directory name (e.g., 20260308-orch-e2e)
#   --timeout:     max seconds before aborting (default: 1800 = 30 min)
#   --bg:          background mode (detached tmux sessions + worktrees)
#   --max-workers: max concurrent workers (default: 4)
#
# Polls every 5 seconds. When all items complete, runs orch-review.sh.
# On SHIP → exit 0. On REVISE → re-queues failed items and continues.
#
# Requires: jq, tmux, claude CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

# --- Defaults ---

SLUG=""
TIMEOUT=1800
MODE_ARGS=()
MAX_WORKERS=4
POLL_INTERVAL=5

# --- Parse args ---

while [[ $# -gt 0 ]]; do
	case "$1" in
	--timeout)
		TIMEOUT="${2:-1800}"
		shift 2
		;;
	--bg)
		MODE_ARGS+=("--bg")
		shift
		;;
	--max-workers)
		MAX_WORKERS="${2:-4}"
		MODE_ARGS+=("--max-workers" "${MAX_WORKERS}")
		shift 2
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-loop.sh <slug> [--timeout N] [--bg] [--max-workers N]" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-loop.sh <slug> [--timeout N] [--bg] [--max-workers N]" >&2
	exit 1
fi

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_STATE_DIR}/state.json"

# --- Scheduling ---

# Schedule ready items into available worker slots.
# Mirrors orch-start.sh logic but works on existing state.
schedule_ready_items() {
	local state
	state=$(cat "${ORCH_STATE_FILE}")
	local running
	running=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "running")] | length')
	local ready_ids
	ready_ids=$(printf '%s' "${state}" | jq -r '[.items[] | select(.status == "ready")] | sort_by(.id) | .[].id')

	local slots=$((MAX_WORKERS - running))
	if [[ ${slots} -le 0 || -z "${ready_ids}" ]]; then
		return
	fi

	local mode
	mode=$(printf '%s' "${state}" | jq -r '.mode')

	for item_id in ${ready_ids}; do
		if [[ ${slots} -le 0 ]]; then
			break
		fi

		local desc
		desc=$(jq -r ".items[] | select(.id == ${item_id}) | .description" "${ORCH_STATE_FILE}")
		echo "orch-loop: launching worker for item ${item_id}: ${desc}"

		local launched=true
		if [[ "${mode}" == "foreground" ]]; then
			launch_foreground "${item_id}" || launched=false
		else
			launch_background "${item_id}" || launched=false
		fi

		if [[ "${launched}" == "true" ]]; then
			orch_update_item_status "${item_id}" "running"
			orch_bump_iteration "${item_id}"
			slots=$((slots - 1))
		else
			echo "orch-loop: skipping item ${item_id} — launch failed, will retry next poll"
		fi
	done
}

launch_foreground() {
	local item_id="$1"
	local session="orch-${SLUG}"

	if ! tmux has-session -t "${session}" 2>/dev/null; then
		echo "orch-loop: warning: tmux session '${session}' not found — skipping item ${item_id}" >&2
		return 1
	fi

	# Find a free worker pane
	local total_panes
	total_panes=$(tmux list-panes -t "${session}" -F '#{pane_index}' | wc -l | tr -d ' ')

	for idx in $(seq 2 $((total_panes - 1))); do
		local title
		title=$(tmux display-message -t "${session}:0.${idx}" -p '#{pane_title}' 2>/dev/null || true)
		if [[ "${title}" == worker-* ]]; then
			local pane_pid
			pane_pid=$(tmux display-message -t "${session}:0.${idx}" -p '#{pane_pid}' 2>/dev/null || true)
			local children
			children=$(pgrep -P "${pane_pid}" 2>/dev/null || true)
			local child_count=0
			if [[ -n "${children}" ]]; then
				child_count=$(printf '%s\n' "${children}" | wc -l | tr -d ' ')
			fi
			if [[ "${child_count}" -le 1 ]]; then
				local worker_cmd="cd '${REPO_ROOT}' && bash '${SCRIPT_DIR}/orch-worker.sh' '${SLUG}' --item ${item_id}"
				tmux send-keys -t "${session}:0.${idx}" "${worker_cmd}" Enter
				tmux select-pane -t "${session}:0.${idx}" -T "worker: item ${item_id}"

				local now
				now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
				local updated
				updated=$(jq \
					--argjson id "${item_id}" \
					--arg pane "${title}" \
					--arg now "${now}" \
					'(.items[] | select(.id == $id)).tmuxPane = $pane |
           .updatedAt = $now' "${ORCH_STATE_FILE}")
				orch_write_state "${updated}"
				echo "orch-loop: item ${item_id} → ${title} (pane ${idx})"
				return 0
			fi
		fi
	done

	echo "orch-loop: no free worker pane for item ${item_id}" >&2
	return 1
}

launch_background() {
	local item_id="$1"
	local wt_path="${REPO_ROOT}/.claude/worktrees/${SLUG}-item-${item_id}"
	local bg_session="orch-${SLUG}-item-${item_id}"

	if [[ ! -d "${wt_path}" ]]; then
		local branch="orch/${SLUG}/item-${item_id}"
		git -C "${REPO_ROOT}" worktree add "${wt_path}" -b "${branch}" 2>/dev/null ||
			git -C "${REPO_ROOT}" worktree add "${wt_path}" "${branch}" 2>/dev/null || true

		if [[ ! -d "${wt_path}" ]]; then
			echo "orch-loop: error: failed to create worktree at ${wt_path}" >&2
			return 1
		fi
	fi

	tmux new-session -d -s "${bg_session}" -c "${wt_path}" \
		"bash '${SCRIPT_DIR}/orch-worker.sh' '${SLUG}' --item ${item_id}"

	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	local updated
	updated=$(jq \
		--argjson id "${item_id}" \
		--arg wt "${wt_path}" \
		--arg now "${now}" \
		'(.items[] | select(.id == $id)).worktree = $wt |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${updated}"
	echo "orch-loop: item ${item_id} → background session '${bg_session}'"
}

# Resolve dependencies: promote queued items to ready when all deps are done.
resolve_deps() {
	local state
	state=$(cat "${ORCH_STATE_FILE}")
	local changed=false

	local queued_ids
	queued_ids=$(printf '%s' "${state}" | jq -r '.items[] | select(.status == "queued") | .id')

	for item_id in ${queued_ids}; do
		local all_deps_done
		all_deps_done=$(printf '%s' "${state}" | jq --argjson id "${item_id}" '
      . as $root |
      ($root.items[] | select(.id == $id) | .deps) as $deps |
      if ($deps | length) == 0 then true
      else [$root.items[] | select(.id == ($deps[])) | .status] | all(. == "done")
      end')

		if [[ "${all_deps_done}" == "true" ]]; then
			local now
			now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
			state=$(printf '%s' "${state}" | jq \
				--argjson id "${item_id}" \
				--arg now "${now}" \
				'(.items[] | select(.id == $id)).status = "ready" |
         .updatedAt = $now')
			changed=true
			local desc
			desc=$(printf '%s' "${state}" | jq -r ".items[] | select(.id == ${item_id}) | .description")
			echo "orch-loop: item ${item_id} deps satisfied — now ready: ${desc}"
		fi
	done

	if [[ "${changed}" == "true" ]]; then
		orch_write_state "${state}"
		local newly_ready
		newly_ready=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "ready")] | length')
		echo "orch-loop: wave advancement — ${newly_ready} item(s) now ready"
	fi
}

# --- Phase 1: Start ---

echo "orch-loop: starting plan '${SLUG}' (timeout: ${TIMEOUT}s)"

bash "${SCRIPT_DIR}/orch-start.sh" "${SLUG}" "${MODE_ARGS[@]+"${MODE_ARGS[@]}"}"

# --- Phase 2: Poll loop ---

START_TIME=$(date +%s)
REVIEW_ATTEMPTS=0
MAX_REVIEW_ATTEMPTS=3

while true; do
	sleep "${POLL_INTERVAL}"

	# Check timeout
	ELAPSED=$(($(date +%s) - START_TIME))
	if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
		echo "orch-loop: timeout after ${ELAPSED}s — stopping" >&2
		bash "${SCRIPT_DIR}/orch-stop.sh" "${SLUG}"
		exit 1
	fi

	# Sync done-files: detect completed workers
	orch_sync_done_files "${SLUG}"

	# Prune dead workers (crashed tmux sessions)
	orch_prune_dead_workers "${SLUG}"

	# Resolve dependencies: promote queued → ready
	resolve_deps

	# Schedule any newly ready items
	schedule_ready_items

	# Check progress
	DONE=$(orch_count_by_status "done")
	RUNNING=$(orch_count_by_status "running")
	READY=$(orch_count_by_status "ready")
	QUEUED=$(orch_count_by_status "queued")
	STOPPED=$(orch_count_by_status "stopped")
	TOTAL=$(jq '.items | length' "${ORCH_STATE_FILE}")

	echo "orch-loop: [${ELAPSED}s] done=${DONE}/${TOTAL} running=${RUNNING} ready=${READY} queued=${QUEUED} stopped=${STOPPED}"

	# Handle stopped items: re-queue if under max iterations
	if [[ "${STOPPED}" -gt 0 ]]; then
		local_state=$(cat "${ORCH_STATE_FILE}")
		stopped_ids=$(printf '%s' "${local_state}" | jq -r '.items[] | select(.status == "stopped") | .id')

		for sid in ${stopped_ids}; do
			iter=$(printf '%s' "${local_state}" | jq ".items[] | select(.id == ${sid}) | .iteration")
			max_iter=$(printf '%s' "${local_state}" | jq ".items[] | select(.id == ${sid}) | .maxIterations")
			if [[ "${iter}" -lt "${max_iter}" ]]; then
				echo "orch-loop: re-queuing stopped item ${sid} (iteration ${iter}/${max_iter})"
				orch_update_item_status "${sid}" "ready"
			else
				echo "orch-loop: item ${sid} exhausted max iterations (${max_iter}) — leaving stopped" >&2
			fi
		done

		# Re-run scheduling after re-queuing
		schedule_ready_items
	fi

	# All items done → final review
	if [[ "${DONE}" -eq "${TOTAL}" ]]; then
		echo ""
		echo "orch-loop: all ${TOTAL} items complete — running final review"

		REVIEW_ATTEMPTS=$((REVIEW_ATTEMPTS + 1))
		if [[ ${REVIEW_ATTEMPTS} -gt ${MAX_REVIEW_ATTEMPTS} ]]; then
			echo "orch-loop: error: ${MAX_REVIEW_ATTEMPTS} review attempts exhausted" >&2
			exit 1
		fi

		bash "${SCRIPT_DIR}/orch-review.sh" "${SLUG}"

		# Read decision from state
		RESULT=$(jq -r '.finalReview.result // "unknown"' "${ORCH_STATE_FILE}")

		case "${RESULT}" in
		SHIP)
			echo ""
			echo "orch-loop: SHIP — plan '${SLUG}' complete in ${ELAPSED}s"
			exit 0
			;;
		REVISE)
			echo ""
			echo "orch-loop: REVISE — re-queuing rework items (attempt ${REVIEW_ATTEMPTS}/${MAX_REVIEW_ATTEMPTS})"

			# orch-review.sh already re-queued rework items as "ready"
			# Reset final review status for next attempt
			NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
			UPDATED=$(jq --arg now "${NOW}" \
				'.finalReview.status = "pending" |
         .finalReview.result = null |
         .updatedAt = $now' "${ORCH_STATE_FILE}")
			orch_write_state "${UPDATED}"

			# Schedule the re-queued items
			schedule_ready_items
			;;
		*)
			echo "orch-loop: error: unexpected review result: '${RESULT}'" >&2
			exit 1
			;;
		esac
	fi

	# If nothing is running, ready, or queued but not all done → stuck
	if [[ "${RUNNING}" -eq 0 && "${READY}" -eq 0 && "${QUEUED}" -eq 0 && "${DONE}" -lt "${TOTAL}" ]]; then
		echo "orch-loop: error: stuck — ${STOPPED} stopped items, no running/ready/queued" >&2
		echo "  Run 'orch-status.sh ${SLUG}' for details" >&2
		exit 1
	fi
done
