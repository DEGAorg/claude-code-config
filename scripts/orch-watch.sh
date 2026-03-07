#!/usr/bin/env bash
# Capture live output from a worker's tmux pane or session.
# Shows the last N lines of terminal output for a specific item's worker.
#
# Usage:
#   scripts/orch-watch.sh <slug> --item N [--lines 30]
#     slug:    exec-plan directory name
#     --item:  item number to watch (required)
#     --lines: number of lines to capture (default: 30)
#
# Foreground mode: captures from the worker's pane in orch-<slug> session.
# Background mode: captures from the detached orch-<slug>-item-<N> session.
#
# Requires: jq, tmux

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATE_DIR="${REPO_ROOT}/.orchestrator"
STATE_FILE="${STATE_DIR}/state.json"

SLUG=""
ITEM_ID=""
LINES=30

# --- Parse args ---

while [[ $# -gt 0 ]]; do
	case "$1" in
	--item)
		ITEM_ID="${2:-}"
		if [[ -z "${ITEM_ID}" ]]; then
			echo "error: --item requires a number" >&2
			exit 1
		fi
		shift 2
		;;
	--lines)
		LINES="${2:-30}"
		shift 2
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-watch.sh <slug> --item N [--lines 30]" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" || -z "${ITEM_ID}" ]]; then
	echo "error: usage: orch-watch.sh <slug> --item N [--lines 30]" >&2
	exit 1
fi

# --- Validate state ---

if [[ ! -f "${STATE_FILE}" ]]; then
	echo "error: no state file at ${STATE_FILE}" >&2
	echo "hint: run orch-start.sh first" >&2
	exit 1
fi

STATE_PLAN=$(jq -r '.plan' "${STATE_FILE}")
if [[ "${STATE_PLAN}" != "${SLUG}" ]]; then
	echo "error: state file is for plan '${STATE_PLAN}', not '${SLUG}'" >&2
	exit 1
fi

# Verify item exists
ITEM_STATUS=$(jq -r ".items[] | select(.id == ${ITEM_ID}) | .status" "${STATE_FILE}")
if [[ -z "${ITEM_STATUS}" ]]; then
	echo "error: item ${ITEM_ID} not found in state" >&2
	exit 1
fi

ITEM_DESC=$(jq -r ".items[] | select(.id == ${ITEM_ID}) | .description" "${STATE_FILE}")
MODE=$(jq -r '.mode' "${STATE_FILE}")

# --- Capture output ---

capture_foreground() {
	local session="orch-${SLUG}"

	if ! tmux has-session -t "${session}" 2>/dev/null; then
		echo "error: tmux session '${session}' not found" >&2
		exit 1
	fi

	# Find the pane assigned to this item
	local pane_name
	pane_name=$(jq -r \
		".items[] | select(.id == ${ITEM_ID}) | .tmuxPane // empty" \
		"${STATE_FILE}")

	if [[ -z "${pane_name}" ]]; then
		echo "error: item ${ITEM_ID} has no assigned pane" >&2
		echo "hint: item status is '${ITEM_STATUS}'" >&2
		exit 1
	fi

	# Find pane index by title
	local pane_idx=""
	local total_panes
	total_panes=$(tmux list-panes -t "${session}" -F '#{pane_index}' |
		wc -l | tr -d ' ')

	for idx in $(seq 0 $((total_panes - 1))); do
		local title
		title=$(tmux display-message -t "${session}:0.${idx}" \
			-p '#{pane_title}' 2>/dev/null || true)
		if [[ "${title}" == "${pane_name}" ]] ||
			[[ "${title}" == "worker: item ${ITEM_ID}" ]]; then
			pane_idx="${idx}"
			break
		fi
	done

	if [[ -z "${pane_idx}" ]]; then
		echo "error: pane '${pane_name}' not found in session '${session}'" >&2
		exit 1
	fi

	echo "--- item ${ITEM_ID}: ${ITEM_DESC} ---"
	echo "--- pane: ${pane_name} (index ${pane_idx}) | status: ${ITEM_STATUS} ---"
	echo ""
	tmux capture-pane -t "${session}:0.${pane_idx}" -p -S "-${LINES}"
}

capture_background() {
	local bg_session="orch-${SLUG}-item-${ITEM_ID}"

	if ! tmux has-session -t "${bg_session}" 2>/dev/null; then
		echo "error: background session '${bg_session}' not found" >&2
		echo "hint: item status is '${ITEM_STATUS}'" >&2
		exit 1
	fi

	echo "--- item ${ITEM_ID}: ${ITEM_DESC} ---"
	echo "--- session: ${bg_session} | status: ${ITEM_STATUS} ---"
	echo ""
	tmux capture-pane -t "${bg_session}" -p -S "-${LINES}"
}

if [[ "${MODE}" == "foreground" ]]; then
	capture_foreground
else
	capture_background
fi
