#!/usr/bin/env bash
# Launch the Ink orchestrator dashboard.
#
# Watches .orchestrator/state.json and renders a live terminal UI
# with item status, worker assignments, and iteration counts.
#
# Usage:
#   scripts/orch-dash.sh <slug> [--pane <tmux-pane>]
#
# Arguments:
#   slug              exec-plan directory name (e.g., 20260307-mcp-server)
#   --pane <target>   send the dashboard command to a tmux pane instead of
#                     running in the current terminal (e.g., "orch-slug:0.1")
#
# Examples:
#   # Run in the current terminal
#   scripts/orch-dash.sh 20260307-mcp-server
#
#   # Launch inside the dashboard pane of a tmux grid
#   scripts/orch-dash.sh 20260307-mcp-server --pane "orch-20260307-mcp-server:0.1"

set -euo pipefail

SLUG="${1:-}"
PANE=""

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-dash.sh <slug> [--pane <tmux-pane>]" >&2
	exit 1
fi

shift
while [[ $# -gt 0 ]]; do
	case "$1" in
	--pane)
		PANE="${2:-}"
		if [[ -z "${PANE}" ]]; then
			echo "error: --pane requires a tmux pane target" >&2
			exit 1
		fi
		shift 2
		;;
	*)
		echo "error: unknown option: $1" >&2
		exit 1
		;;
	esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_FILE="${REPO_ROOT}/.orchestrator/state.json"
TERMINAL_UI_DIR="${SCRIPT_DIR}/terminal-ui"

if [[ ! -d "${TERMINAL_UI_DIR}" ]]; then
	echo "error: terminal-ui directory not found: ${TERMINAL_UI_DIR}" >&2
	exit 1
fi

# Verify tsx is available via the terminal-ui project
TSX="${TERMINAL_UI_DIR}/node_modules/.bin/tsx"
if [[ ! -x "${TSX}" ]]; then
	echo "error: tsx not found — run 'pnpm install' in ${TERMINAL_UI_DIR}" >&2
	exit 1
fi

DASH_CMD="cd '${REPO_ROOT}' && '${TSX}' '${TERMINAL_UI_DIR}/src/cli.tsx' --state '${STATE_FILE}'"

if [[ -n "${PANE}" ]]; then
	# Verify the target pane exists
	if ! tmux display-message -t "${PANE}" -p "#{pane_id}" >/dev/null 2>&1; then
		echo "error: tmux pane not found: ${PANE}" >&2
		exit 1
	fi
	tmux send-keys -t "${PANE}" "${DASH_CMD}" Enter
	echo "dashboard launched in tmux pane: ${PANE}"
	echo "watching: ${STATE_FILE}"
else
	echo "launching dashboard for plan: ${SLUG}"
	echo "watching: ${STATE_FILE}"
	exec "${TSX}" "${TERMINAL_UI_DIR}/src/cli.tsx" --state "${STATE_FILE}"
fi
