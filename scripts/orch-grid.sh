#!/usr/bin/env bash
# Set up a foreground tmux grid for the orchestrator.
# Creates a tmux session with: orchestrator (top-left), dashboard (top-right),
# and up to N worker panes (bottom row).
#
# Usage: scripts/orch-grid.sh <slug> [--max-panes N]
#   slug: exec-plan directory name (e.g., 20260307-mcp-server)
#   --max-panes: number of worker panes in the bottom row (default: 4, max: 6)
#
# Layout:
#   +-------------------+-------------------+
#   |   orchestrator    |    dashboard      |
#   +--------+----+-----+----+--------+-----+
#   | work 1 | work 2 | work 3 | work 4     |
#   +--------+--------+--------+------------+

set -euo pipefail

SLUG="${1:-}"
MAX_PANES=4

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-grid.sh <slug> [--max-panes N]" >&2
	exit 1
fi

shift
while [[ $# -gt 0 ]]; do
	case "$1" in
	--max-panes)
		MAX_PANES="${2:-4}"
		shift 2
		;;
	*)
		echo "error: unknown option: $1" >&2
		exit 1
		;;
	esac
done

if [[ "${MAX_PANES}" -lt 1 || "${MAX_PANES}" -gt 6 ]]; then
	echo "error: --max-panes must be between 1 and 6" >&2
	exit 1
fi

PLAN_DIR="docs/exec-plans/active/${SLUG}"
if [[ ! -d "${PLAN_DIR}" ]]; then
	echo "error: plan directory not found: ${PLAN_DIR}" >&2
	exit 1
fi

SESSION="orch-${SLUG}"

# Kill existing session if present
if tmux has-session -t "${SESSION}" 2>/dev/null; then
	echo "warning: session '${SESSION}' already exists, killing it" >&2
	tmux kill-session -t "${SESSION}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Create session with first pane (will become orchestrator)
tmux new-session -d -s "${SESSION}" -x 220 -y 50 -c "${REPO_ROOT}"

# Split top row: orchestrator (left) | dashboard (right)
tmux split-window -h -t "${SESSION}:0.0" -c "${REPO_ROOT}"

# The top row is now pane 0 (orchestrator) and pane 1 (dashboard).
# Split pane 0 (orchestrator) vertically to create the bottom-left worker area.
tmux split-window -v -t "${SESSION}:0.0" -c "${REPO_ROOT}" -p 50

# Split pane 2 (dashboard, now index shifted) vertically for bottom-right.
tmux split-window -v -t "${SESSION}:0.2" -c "${REPO_ROOT}" -p 50

# Now we have 4 panes:
#   0: orchestrator (top-left)
#   1: worker-1 (bottom-left)
#   2: dashboard (top-right)
#   3: worker-2 (bottom-right)
#
# Need to create additional worker panes by splitting the bottom ones.
# Split bottom-left for more workers.
workers_created=2

if [[ "${MAX_PANES}" -ge 3 ]]; then
	tmux split-window -h -t "${SESSION}:0.1" -c "${REPO_ROOT}"
	workers_created=3
fi

if [[ "${MAX_PANES}" -ge 4 ]]; then
	# Split bottom-right area
	tmux split-window -h -t "${SESSION}:0.$((workers_created + 1))" -c "${REPO_ROOT}"
	workers_created=4
fi

# For 5-6 panes, split existing bottom panes further
if [[ "${MAX_PANES}" -ge 5 ]]; then
	tmux split-window -v -t "${SESSION}:0.1" -c "${REPO_ROOT}"
	workers_created=5
fi

if [[ "${MAX_PANES}" -ge 6 ]]; then
	tmux split-window -v -t "${SESSION}:0.3" -c "${REPO_ROOT}"
	workers_created=6
fi

# Name panes for easy reference
tmux select-pane -t "${SESSION}:0.0" -T "orchestrator"

# Find the dashboard pane — it's the top-right pane (index 2 in standard layout)
# After all splits, use select-layout to normalize, then set titles.
tmux select-layout -t "${SESSION}:0" tiled

# Apply a clean layout: top row 40% height, bottom row 60%
# Use main-horizontal as base, then manually resize
tmux select-layout -t "${SESSION}:0" tiled

# Label all panes
tmux select-pane -t "${SESSION}:0.0" -T "orchestrator"
tmux select-pane -t "${SESSION}:0.1" -T "dashboard"
pane_idx=2
for i in $(seq 1 "${workers_created}"); do
	tmux select-pane -t "${SESSION}:0.${pane_idx}" -T "worker-${i}"
	pane_idx=$((pane_idx + 1))
done

# Start the Ink dashboard in the dashboard pane
DASH_CMD="cd '${REPO_ROOT}' && echo '[dashboard] waiting for orch-dash.sh to start...'"
tmux send-keys -t "${SESSION}:0.1" "${DASH_CMD}" Enter

# Label worker panes with placeholder text
pane_idx=2
for i in $(seq 1 "${workers_created}"); do
	tmux send-keys -t "${SESSION}:0.${pane_idx}" \
		"echo '[worker-${i}] idle — waiting for orchestrator to assign work'" Enter
	pane_idx=$((pane_idx + 1))
done

# Select the orchestrator pane so the user lands there
tmux select-pane -t "${SESSION}:0.0"

# Enable pane border status to show titles
tmux set-option -t "${SESSION}" pane-border-status top
tmux set-option -t "${SESSION}" pane-border-format " #{pane_title} "

echo "tmux session '${SESSION}' created with ${workers_created} worker panes"
echo "layout: orchestrator + dashboard + ${workers_created} workers"
echo ""
echo "attach with: tmux attach -t ${SESSION}"
echo "or if already in tmux: tmux switch-client -t ${SESSION}"

# If not already inside tmux, attach
if [[ -z "${TMUX:-}" ]]; then
	exec tmux attach -t "${SESSION}"
fi
