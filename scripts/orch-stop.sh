#!/usr/bin/env bash
# Stop orchestrator workers — by item, by plan, or all.
# Updates state files and cleans up tmux panes/sessions.
#
# Usage:
#   scripts/orch-stop.sh <slug> [--item N]   Stop one item's worker
#   scripts/orch-stop.sh <slug>              Stop all workers for a plan
#   scripts/orch-stop.sh --all               Stop all orchestrator sessions
#
# Requires: jq, tmux

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

SLUG=""
ITEM_ID=""
STOP_ALL=false

# --- Parse args ---

while [[ $# -gt 0 ]]; do
	case "$1" in
	--all)
		STOP_ALL=true
		shift
		;;
	--item)
		ITEM_ID="${2:-}"
		if [[ -z "${ITEM_ID}" ]]; then
			echo "error: --item requires a number" >&2
			exit 1
		fi
		shift 2
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-stop.sh <slug> [--item N] | --all" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_STATE_DIR}/state.json"

# --- Helpers ---

# Stop a foreground worker by clearing its tmux pane
stop_foreground_worker() {
	local slug="$1"
	local pane="$2"
	local session="orch-${slug}"

	if ! tmux has-session -t "${session}" 2>/dev/null; then
		return 0
	fi

	# Find pane index by title
	local pane_count
	pane_count=$(tmux list-panes -t "${session}" -F '#{pane_index}' | wc -l | tr -d ' ')

	for idx in $(seq 0 $((pane_count - 1))); do
		local title
		title=$(tmux display-message -t "${session}:0.${idx}" -p '#{pane_title}' 2>/dev/null || true)
		if [[ "${title}" == "${pane}" || "${title}" == worker:* ]]; then
			# Send Ctrl-C then clear the pane
			tmux send-keys -t "${session}:0.${idx}" C-c 2>/dev/null || true
			sleep 0.5
			tmux send-keys -t "${session}:0.${idx}" C-c 2>/dev/null || true
			tmux select-pane -t "${session}:0.${idx}" -T "${pane}" 2>/dev/null || true
			echo "orch-stop: sent interrupt to pane ${pane} (index ${idx})"
			return 0
		fi
	done
}

# Stop a background worker by killing its detached tmux session
stop_background_worker() {
	local slug="$1"
	local item_id="$2"
	local bg_session="orch-${slug}-item-${item_id}"

	if tmux has-session -t "${bg_session}" 2>/dev/null; then
		tmux kill-session -t "${bg_session}"
		echo "orch-stop: killed background session '${bg_session}'"
	fi
}

# Stop all workers for a given plan slug
stop_plan_workers() {
	local slug="$1"

	if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
		echo "error: no state file at ${ORCH_STATE_FILE}" >&2
		return 1
	fi

	local plan
	plan=$(jq -r '.plan' "${ORCH_STATE_FILE}")
	if [[ "${plan}" != "${slug}" ]]; then
		echo "error: state file is for plan '${plan}', not '${slug}'" >&2
		return 1
	fi

	local mode
	mode=$(jq -r '.mode' "${ORCH_STATE_FILE}")

	# Get all running items
	local running_ids
	running_ids=$(jq -r '.items[] | select(.status == "running") | .id' "${ORCH_STATE_FILE}")

	local stopped=0
	for id in ${running_ids}; do
		if [[ "${mode}" == "foreground" ]]; then
			local pane
			pane=$(jq -r ".items[] | select(.id == ${id}) | .tmuxPane // empty" "${ORCH_STATE_FILE}")
			if [[ -n "${pane}" ]]; then
				stop_foreground_worker "${slug}" "${pane}"
			fi
		else
			stop_background_worker "${slug}" "${id}"
		fi
		orch_mark_item_stopped "${id}"
		stopped=$((stopped + 1))
	done

	echo "orch-stop: stopped ${stopped} workers for plan '${slug}'"
}

# --- Main ---

if [[ "${STOP_ALL}" == "true" ]]; then
	# Kill all orchestrator tmux sessions
	stopped=0
	while IFS= read -r session; do
		[[ -z "${session}" ]] && continue
		tmux kill-session -t "${session}" 2>/dev/null || true
		echo "orch-stop: killed session '${session}'"
		stopped=$((stopped + 1))
	done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^orch-' || true)

	if [[ ${stopped} -eq 0 ]]; then
		echo "orch-stop: no orchestrator sessions found"
	else
		echo "orch-stop: killed ${stopped} orchestrator sessions"
	fi
	exit 0
fi

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-stop.sh <slug> [--item N] | --all" >&2
	exit 1
fi

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
	echo "error: no state file at ${ORCH_STATE_FILE}" >&2
	exit 1
fi

if [[ -n "${ITEM_ID}" ]]; then
	# Stop a single item's worker
	local_mode=$(jq -r '.mode' "${ORCH_STATE_FILE}")
	item_status=$(jq -r ".items[] | select(.id == ${ITEM_ID}) | .status" "${ORCH_STATE_FILE}")

	if [[ -z "${item_status}" ]]; then
		echo "error: item ${ITEM_ID} not found in state" >&2
		exit 1
	fi

	if [[ "${item_status}" != "running" ]]; then
		echo "orch-stop: item ${ITEM_ID} is not running (status: ${item_status})"
		exit 0
	fi

	if [[ "${local_mode}" == "foreground" ]]; then
		pane=$(jq -r ".items[] | select(.id == ${ITEM_ID}) | .tmuxPane // empty" "${ORCH_STATE_FILE}")
		if [[ -n "${pane}" ]]; then
			stop_foreground_worker "${SLUG}" "${pane}"
		fi
	else
		stop_background_worker "${SLUG}" "${ITEM_ID}"
	fi

	orch_mark_item_stopped "${ITEM_ID}"
	echo "orch-stop: stopped worker for item ${ITEM_ID}"
else
	# Stop all workers for this plan
	stop_plan_workers "${SLUG}"
fi
