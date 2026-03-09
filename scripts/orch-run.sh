#!/usr/bin/env bash
# One-command orchestrator launcher — foreground mode.
# Creates tmux session with visible worker panes:
#
#   +-------------------+-------------------+
#   |      claude       |    dashboard      |
#   +-------------------+-------------------+
#   | orchestrator loop | worker-1 |worker-2|
#   +-------------------+----------+--------+
#   |   worker-3   |   worker-4   |
#   +--------------+--------------+
#
# Usage: scripts/orch-run.sh <slug> [--timeout N] [--max-workers N]
#
# Example: scripts/orch-run.sh 20260309-orch-smoke-test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SLUG="${1:-}"
MAX_WORKERS=4
TIMEOUT=600

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-run.sh <slug> [--timeout N] [--max-workers N]" >&2
	exit 1
fi
shift

while [[ $# -gt 0 ]]; do
	case "$1" in
	--timeout)
		TIMEOUT="${2:-600}"
		shift 2
		;;
	--max-workers)
		MAX_WORKERS="${2:-4}"
		shift 2
		;;
	*)
		echo "error: unknown option: $1" >&2
		exit 1
		;;
	esac
done

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

SESSION="orch-${SLUG}"

# Kill existing session if present
if tmux has-session -t "${SESSION}" 2>/dev/null; then
	echo "warning: session '${SESSION}' already exists, killing it" >&2
	tmux kill-session -t "${SESSION}"
fi

# --- Resolve dashboard command (best available) ---

STATE_FILE="${REPO_ROOT}/.orchestrator/state.json"
DASH_CMD="bash -c '"
DASH_CMD+='while true; do clear; '
DASH_CMD+="cat \"${STATE_FILE}\" 2>/dev/null | jq . 2>/dev/null || echo \"waiting for state...\"; "
DASH_CMD+="sleep 2; done'"
[[ -f "${REPO_ROOT}/scripts/terminal-ui/dist/cli.js" ]] &&
	DASH_CMD="node '${REPO_ROOT}/scripts/terminal-ui/dist/cli.js' --state '${STATE_FILE}'"

# --- Orchestrator loop command ---

LOOP_CMD="cd '${REPO_ROOT}' && bash '${SCRIPT_DIR}/orch-loop.sh' '${SLUG}'"
LOOP_CMD+=" --timeout ${TIMEOUT} --max-workers ${MAX_WORKERS}"
LOOP_CMD+="; echo ''; echo 'Orchestrator finished.'; exec bash"

# --- Claude interactive command ---

CLAUDE_CMD="claude --dangerously-skip-permissions; "
CLAUDE_CMD+="echo 'Claude exited. Ctrl-D to close.'; exec bash"

# --- Create tmux session ---

# Row 1: claude (left, 60%) | dashboard (right, 40%)
tmux new-session -d -s "${SESSION}" -x 220 -y 55 -c "${REPO_ROOT}" "${CLAUDE_CMD}"
tmux split-window -h -t "${SESSION}:.0" -p 40 -c "${REPO_ROOT}" "${DASH_CMD}"

# Row 2: orchestrator loop (bottom-left, 35% of left column)
tmux split-window -v -t "${SESSION}:.0" -p 35 -c "${REPO_ROOT}" "${LOOP_CMD}"

# Worker panes: split the bottom-right area
# First worker pane (below dashboard)
tmux split-window -v -t "${SESSION}:.1" -p 65 -c "${REPO_ROOT}"

# Split the worker area into columns based on max-workers
FIRST_WORKER_PANE=3
if [[ "${MAX_WORKERS}" -ge 2 ]]; then
	tmux split-window -h -t "${SESSION}:.${FIRST_WORKER_PANE}" -p 50 -c "${REPO_ROOT}"
fi
if [[ "${MAX_WORKERS}" -ge 3 ]]; then
	tmux split-window -v -t "${SESSION}:.${FIRST_WORKER_PANE}" -p 50 -c "${REPO_ROOT}"
fi
if [[ "${MAX_WORKERS}" -ge 4 ]]; then
	# Split the second worker column
	tmux split-window -v -t "${SESSION}:.$((FIRST_WORKER_PANE + 2))" -p 50 -c "${REPO_ROOT}"
fi

# --- Label all panes ---

tmux select-pane -t "${SESSION}:.0" -T "claude"
tmux select-pane -t "${SESSION}:.1" -T "dashboard"
tmux select-pane -t "${SESSION}:.2" -T "orchestrator"

# Label worker panes
pane_idx="${FIRST_WORKER_PANE}"
for i in $(seq 1 "${MAX_WORKERS}"); do
	tmux select-pane -t "${SESSION}:.${pane_idx}" -T "worker-${i}"
	tmux send-keys -t "${SESSION}:.${pane_idx}" \
		"echo '[worker-${i}] idle — waiting for orchestrator'" Enter
	pane_idx=$((pane_idx + 1))
done

# --- Status bar and pane borders ---

tmux set-option -t "${SESSION}" pane-border-status top
tmux set-option -t "${SESSION}" pane-border-format " #{pane_title} "
tmux set-option -t "${SESSION}" status-left " Orch: ${SLUG} "
tmux set-option -t "${SESSION}" status-right " %H:%M "

# Focus on claude pane
tmux select-pane -t "${SESSION}:.0"

echo "Launching orchestrator for '${SLUG}' (${MAX_WORKERS} workers, ${TIMEOUT}s timeout)..."
exec tmux attach-session -t "${SESSION}"
