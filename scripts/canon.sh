#!/usr/bin/env bash
set -euo pipefail

STATE="$(pwd)/.canon/state.json"
TUI_WRITE="${HOME}/.claude/scripts/terminal-ui-write.sh"

# ── Init state file ──────────────────────────────────────────────────
mkdir -p .canon
if [[ -f "${TUI_WRITE}" ]]; then
	bash "${TUI_WRITE}" "${STATE}" \
		phase=init status=idle log.info="Waiting for /canon-start..."
else
	printf '{"phase":"init","status":"idle","startedAt":"%s","updatedAt":"%s","logs":[],"error":null,"metrics":{}}\n' \
		"$(date -u +%FT%TZ)" "$(date -u +%FT%TZ)" >"${STATE}"
fi

# ── Dashboard renderer (best available) ──────────────────────────────
RIGHT_CMD="bash -c 'while true; do clear; cat \"${STATE}\" 2>/dev/null; sleep 1; done'"
[[ -f "${HOME}/.claude/scripts/terminal-ui/dist/cli.js" ]] &&
	RIGHT_CMD="node ${HOME}/.claude/scripts/terminal-ui/dist/cli.js --state ${STATE}"
command -v terminal-ui >/dev/null 2>&1 &&
	RIGHT_CMD="terminal-ui --state ${STATE}"

# ── Create tmux: left=claude, right=dashboard ────────────────────────
# When Claude exits, update dashboard status to idle and keep the pane alive
CLAUDE_CMD="claude --dangerously-skip-permissions; "
CLAUDE_CMD+="[[ -f '${TUI_WRITE}' ]] && bash '${TUI_WRITE}' '${STATE}' status=idle log.info='Claude session ended'; "
CLAUDE_CMD+="echo 'Claude exited. Run ./canon.sh to restart, or Ctrl-D to close.'; "
CLAUDE_CMD+="exec bash"
tmux new-session -d -s canon "${CLAUDE_CMD}"
tmux split-window -h -t canon -p 40 "${RIGHT_CMD}"
tmux select-pane -t canon:.0

# ── Pre-type /canon-start (user hits Enter to confirm) ──────────────
tmux send-keys -t canon:.0 "/canon-start" ""

# ── Status bar ───────────────────────────────────────────────────────
tmux set-option -t canon status-left " Canon "
tmux set-option -t canon status-right " %H:%M "

exec tmux attach-session -t canon
