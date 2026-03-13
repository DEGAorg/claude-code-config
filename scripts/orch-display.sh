#!/usr/bin/env bash
# orch-display.sh — open terminal windows attached (read-only) to an
# orchestrator tmux session.
#
# Usage: orch-display.sh <tmux-session-name>
#
# Platform detection order:
#   macOS + iTerm2     → osascript opens new iTerm2 tab
#   macOS + Terminal   → osascript opens new Terminal.app window
#   WSL               → wt.exe opens new Windows Terminal tab
#   Linux + desktop   → gnome-terminal / konsole / xterm
#   Fallback          → prints the command for manual attach

set -euo pipefail

if [[ $# -lt 1 ]]; then
	echo "usage: orch-display.sh <tmux-session-name>" >&2
	exit 1
fi

SESSION="$1"

# Verify the tmux session exists before trying to attach
if ! tmux has-session -t "${SESSION}" 2>/dev/null; then
	echo "error: tmux session '${SESSION}' does not exist" >&2
	exit 1
fi

ATTACH_CMD="tmux attach-session -t '${SESSION}' -r"

# Portable timeout: works on macOS without GNU coreutils
run_with_timeout() {
	local secs="$1"
	shift
	"$@" &
	local pid=$!
	(
		sleep "${secs}"
		kill "${pid}" 2>/dev/null
	) &
	local watchdog=$!
	if wait "${pid}" 2>/dev/null; then
		kill "${watchdog}" 2>/dev/null
		wait "${watchdog}" 2>/dev/null || true
		return 0
	else
		kill "${watchdog}" 2>/dev/null
		wait "${watchdog}" 2>/dev/null || true
		return 1
	fi
}

# --- Platform detection ---

open_iterm2() {
	if run_with_timeout 10 osascript <<-APPLESCRIPT; then
		    tell application "iTerm2"
		      activate
		      tell current window
		        create tab with default profile
		        tell current session
		          write text "${ATTACH_CMD}"
		        end tell
		      end tell
		    end tell
	APPLESCRIPT
		echo "orch-display: opened iTerm2 tab (read-only attach)"
	else
		echo "orch-display: iTerm2 automation timed out or failed" >&2
		print_fallback
	fi
}

open_terminal_app() {
	if run_with_timeout 10 osascript <<-APPLESCRIPT; then
		    tell application "Terminal"
		      activate
		      do script "${ATTACH_CMD}"
		    end tell
	APPLESCRIPT
		echo "orch-display: opened Terminal.app window (read-only attach)"
	else
		echo "orch-display: Terminal.app automation timed out or failed" >&2
		print_fallback
	fi
}

open_wsl() {
	wt.exe new-tab -- wsl bash -c "${ATTACH_CMD}" &
	echo "orch-display: opened Windows Terminal tab (read-only attach)"
}

open_linux_terminal() {
	if command -v gnome-terminal >/dev/null 2>&1; then
		gnome-terminal -- bash -c "${ATTACH_CMD}; exec bash" &
		echo "orch-display: opened gnome-terminal (read-only attach)"
	elif command -v konsole >/dev/null 2>&1; then
		konsole -e bash -c "${ATTACH_CMD}" &
		echo "orch-display: opened konsole (read-only attach)"
	elif command -v xterm >/dev/null 2>&1; then
		xterm -e bash -c "${ATTACH_CMD}" &
		echo "orch-display: opened xterm (read-only attach)"
	else
		print_fallback
	fi
}

print_fallback() {
	echo "orch-display: no supported terminal detected"
	echo "  Run manually: ${ATTACH_CMD}"
}

# --- Dispatch ---

case "$(uname -s)" in
Darwin)
	if [[ -d "/Applications/iTerm.app" ]]; then
		open_iterm2
	else
		open_terminal_app
	fi
	;;
Linux)
	if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
		open_wsl
	else
		open_linux_terminal
	fi
	;;
*)
	print_fallback
	;;
esac
