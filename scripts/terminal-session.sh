#!/usr/bin/env bash
# Launch a named tmux session: left pane (60%) user shell, right pane (40%) dashboard.
# Usage: terminal-session.sh --name <session> --state <state-file>

set -euo pipefail

NAME=""
STATE=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--name) NAME="${2:-}" && shift 2 ;;
	--state) STATE="${2:-}" && shift 2 ;;
	*)
		echo "error: unknown flag: $1" >&2
		echo "usage: terminal-session.sh --name <session> --state <path>" >&2
		exit 1
		;;
	esac
done
if [[ -z "${NAME}" || -z "${STATE}" ]]; then
	echo "error: --name and --state are required" >&2
	exit 1
fi

# Idempotent: attach if session already exists
if tmux has-session -t "${NAME}" 2>/dev/null; then
	exec tmux attach-session -t "${NAME}"
fi

# Right-pane command: terminal-ui > built cli.js > watch > shell loop
if command -v terminal-ui >/dev/null 2>&1; then
	RIGHT_CMD="terminal-ui --state ${STATE}"
elif [[ -f "${HOME}/.claude/scripts/terminal-ui/dist/cli.js" ]]; then
	RIGHT_CMD="node ${HOME}/.claude/scripts/terminal-ui/dist/cli.js --state ${STATE}"
elif command -v watch >/dev/null 2>&1; then
	RIGHT_CMD="watch -n1 cat ${STATE}"
else
	RIGHT_CMD="bash -c 'while true; do clear && cat \"${STATE}\"; sleep 1; done'"
fi

# Create session, split panes, focus left pane
tmux new-session -d -s "${NAME}"
tmux split-window -h -t "${NAME}" -p 40 "${RIGHT_CMD}"
tmux select-pane -t "${NAME}:.0"

# Status bar
tmux set-option -t "${NAME}" status-left " #S "
tmux set-option -t "${NAME}" status-right " %H:%M "

exec tmux attach-session -t "${NAME}"
