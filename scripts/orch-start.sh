#!/usr/bin/env bash
# Start plan execution — parse items, initialize state, schedule workers
# by dependency wave. Each worker runs orch-worker.sh scoped to one item.
#
# Usage: scripts/orch-start.sh <slug> [--bg] [--max-workers N]
#   slug:          exec-plan directory name (e.g., 20260307-mcp-server)
#   --bg:          background mode (detached tmux sessions + worktrees)
#   --max-workers: max concurrent workers (default: 4)
#
# Requires: jq, tmux, orch-parse-items.sh, orch-worker.sh
#
# State: writes to .orchestrator/state.json (atomic tmp+mv)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

SLUG=""
MODE="foreground"
MAX_WORKERS=4

# --- Parse args ---

while [[ $# -gt 0 ]]; do
	case "$1" in
	--bg)
		MODE="background"
		shift
		;;
	--max-workers)
		MAX_WORKERS="${2:-4}"
		shift 2
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-start.sh <slug> [--bg] [--max-workers N]" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-start.sh <slug> [--bg] [--max-workers N]" >&2
	exit 1
fi

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_STATE_DIR}/state.json"

# --- Parse items ---

PARSED=$("${SCRIPT_DIR}/orch-parse-items.sh" "${SLUG}")
ITEM_COUNT=$(printf '%s' "${PARSED}" | jq '.items | length')

if [[ "${ITEM_COUNT}" -eq 0 ]]; then
	echo "error: no items found in plan" >&2
	exit 1
fi

echo "orch-start: plan '${SLUG}' — ${ITEM_COUNT} items, max ${MAX_WORKERS} workers, mode=${MODE}"

# --- Initialize state ---

orch_ensure_done_dir "${SLUG}"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build items array for state.json from parsed items
ITEMS_JSON=$(printf '%s' "${PARSED}" | jq --argjson maxIter 3 '[
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
    iteration: (if .checked then 1 else 0 end),
    maxIterations: $maxIter,
    lastResult: (if .checked then "SHIP" else null end)
  }
]')

# Resolve "ready" status: an item is ready if all deps are done
ITEMS_JSON=$(printf '%s' "${ITEMS_JSON}" | jq '[
  . as $all |
  .[] | . as $item |
  if $item.status == "queued" then
    if ([$all[] | select(.id == ($item.deps[])) | .status] | all(. == "done")) then
      .status = "ready"
    else .
    end
  else .
  end
]')

STATE_JSON=$(jq -n \
	--argjson version 1 \
	--arg plan "${SLUG}" \
	--argjson maxWorkers "${MAX_WORKERS}" \
	--arg mode "${MODE}" \
	--argjson items "${ITEMS_JSON}" \
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

orch_write_state "${STATE_JSON}"

echo "orch-start: state initialized at ${ORCH_STATE_FILE}"

# --- Schedule ready items ---

schedule_workers() {
	local state
	state=$(cat "${ORCH_STATE_FILE}")
	local running
	running=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "running")] | length')
	local ready_ids
	ready_ids=$(printf '%s' "${state}" | jq -r '[.items[] | select(.status == "ready")] | sort_by(.id) | .[].id')

	local slots=$((MAX_WORKERS - running))
	if [[ ${slots} -le 0 ]]; then
		echo "orch-start: all ${MAX_WORKERS} worker slots occupied"
		return
	fi

	for item_id in ${ready_ids}; do
		if [[ ${slots} -le 0 ]]; then
			break
		fi

		launch_worker "${item_id}"
		slots=$((slots - 1))
	done
}

launch_worker() {
	local item_id="$1"
	local desc
	desc=$(jq -r ".items[] | select(.id == ${item_id}) | .description" "${ORCH_STATE_FILE}")

	echo "orch-start: launching worker for item ${item_id}: ${desc}"

	if [[ "${MODE}" == "foreground" ]]; then
		launch_foreground_worker "${item_id}" "${desc}"
	else
		launch_background_worker "${item_id}" "${desc}"
	fi

	# Update state: mark item as running
	orch_update_item_status "${item_id}" "running"
}

launch_foreground_worker() {
	local item_id="$1"
	local desc="$2"
	local session="orch-${SLUG}"

	if ! tmux has-session -t "${session}" 2>/dev/null; then
		echo "error: tmux session '${session}' not found — run orch-grid.sh first" >&2
		return 1
	fi

	# Find a free worker pane (worker-1 through worker-N)
	local pane_title=""
	local pane_idx=""
	local total_panes
	total_panes=$(tmux list-panes -t "${session}" -F '#{pane_index}' | wc -l | tr -d ' ')

	for idx in $(seq 2 $((total_panes - 1))); do
		local title
		title=$(tmux display-message -t "${session}:0.${idx}" -p '#{pane_title}' 2>/dev/null || true)
		if [[ "${title}" == worker-* ]]; then
			# Check if pane is idle (no running claude process)
			local pane_pid
			pane_pid=$(tmux display-message -t "${session}:0.${idx}" -p '#{pane_pid}' 2>/dev/null || true)
			local child_count
			local children
			children=$(pgrep -P "${pane_pid}" 2>/dev/null || true)
			local child_count=0
			if [[ -n "${children}" ]]; then
				child_count=$(printf '%s\n' "${children}" | wc -l | tr -d ' ')
			fi
			if [[ "${child_count}" -le 1 ]]; then
				pane_title="${title}"
				pane_idx="${idx}"
				break
			fi
		fi
	done

	if [[ -z "${pane_idx}" ]]; then
		echo "orch-start: no free worker pane for item ${item_id} — queuing" >&2
		return 1
	fi

	# Build worker command: per-item worker scoped to this item
	local worker_cmd="cd '${REPO_ROOT}' && bash '${SCRIPT_DIR}/orch-worker.sh' '${SLUG}' --item ${item_id}"
	tmux send-keys -t "${session}:0.${pane_idx}" "${worker_cmd}" Enter
	tmux select-pane -t "${session}:0.${pane_idx}" -T "worker: item ${item_id}"

	# Record pane assignment in state
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
	local updated
	updated=$(jq \
		--argjson id "${item_id}" \
		--arg pane "${pane_title}" \
		--arg now "${now}" \
		'(.items[] | select(.id == $id)).tmuxPane = $pane |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
	orch_write_state "${updated}"

	echo "orch-start: item ${item_id} → ${pane_title} (pane ${pane_idx})"
}

launch_background_worker() {
	local item_id="$1"
	local desc="$2"
	local wt_path="${REPO_ROOT}/.claude/worktrees/${SLUG}-item-${item_id}"
	local bg_session="orch-${SLUG}-item-${item_id}"

	# Create worktree if it doesn't exist
	if [[ ! -d "${wt_path}" ]]; then
		local branch="orch/${SLUG}/item-${item_id}"
		git -C "${REPO_ROOT}" worktree add "${wt_path}" -b "${branch}" 2>/dev/null ||
			git -C "${REPO_ROOT}" worktree add "${wt_path}" "${branch}" 2>/dev/null || true

		if [[ ! -d "${wt_path}" ]]; then
			echo "error: failed to create worktree at ${wt_path}" >&2
			return 1
		fi
	fi

	# Launch per-item worker in a detached tmux session
	tmux new-session -d -s "${bg_session}" -c "${wt_path}" \
		"bash '${SCRIPT_DIR}/orch-worker.sh' '${SLUG}' --item ${item_id}"

	# Record worktree in state
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

	echo "orch-start: item ${item_id} → background session '${bg_session}'"
}

# --- Launch first wave ---

schedule_workers

# Show summary
READY=$(orch_count_by_status "ready")
RUNNING=$(orch_count_by_status "running")
DONE=$(orch_count_by_status "done")
QUEUED=$(orch_count_by_status "queued")

echo ""
echo "orch-start: summary"
echo "  running: ${RUNNING}  ready: ${READY}  queued: ${QUEUED}  done: ${DONE}"
echo "  state: ${ORCH_STATE_FILE}"
echo ""
echo "Next steps:"
echo "  - Watch a worker:   bash scripts/orch-watch.sh ${SLUG} --item N"
echo "  - Check status:     bash scripts/orch-status.sh ${SLUG}"
echo "  - Stop all:         bash scripts/orch-stop.sh ${SLUG}"
