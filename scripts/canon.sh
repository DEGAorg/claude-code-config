#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"

STATE="$(pwd)/.canon/state.json"
TUI_WRITE="${DEGA_CORE_HOME}/scripts/terminal-ui-write.sh"

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
[[ -f "${DEGA_CORE_HOME}/scripts/terminal-ui/dist/cli.js" ]] &&
	RIGHT_CMD="node ${DEGA_CORE_HOME}/scripts/terminal-ui/dist/cli.js --state ${STATE}"
command -v terminal-ui >/dev/null 2>&1 &&
	RIGHT_CMD="terminal-ui --state ${STATE}"

# ── Create tmux: left=agent, right=dashboard ─────────────────────────
# When the agent exits, update dashboard status to idle and keep the pane alive
AGENT_CMD="$(dega_agent_command) --dangerously-skip-permissions; "
AGENT_CMD+="[[ -f '${TUI_WRITE}' ]] && bash '${TUI_WRITE}' '${STATE}' status=idle log.info='Agent session ended'; "
AGENT_CMD+="echo 'Agent exited. Run ./canon.sh to restart, or Ctrl-D to close.'; "
AGENT_CMD+="exec bash"
tmux new-session -d -s canon "${AGENT_CMD}"
tmux split-window -h -t canon -p 40 "${RIGHT_CMD}"
tmux select-pane -t canon:.0

# ── Pre-type /canon-start (user hits Enter to confirm) ──────────────
tmux send-keys -t canon:.0 "/canon-start" ""

# ── Status bar ───────────────────────────────────────────────────────
tmux set-option -t canon status-left " Canon "
tmux set-option -t canon status-right " %H:%M "

exec tmux attach-session -t canon
