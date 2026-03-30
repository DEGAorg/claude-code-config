#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"

PROJECT_DIR="$(pwd)"
STATE="${PROJECT_DIR}/.canon/state.json"
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
# Priority: toad > terminal-ui (global) > terminal-ui (bundled) > cat loop
_canon_dashboard_cmd() {
  if command -v toad >/dev/null 2>&1; then
    echo "toad --project ${PROJECT_DIR}"
    return
  fi
  if command -v terminal-ui >/dev/null 2>&1; then
    echo "terminal-ui --state ${STATE}"
    return
  fi
  if [[ -f "${DEGA_CORE_HOME}/scripts/terminal-ui/dist/cli.js" ]]; then
    echo "node ${DEGA_CORE_HOME}/scripts/terminal-ui/dist/cli.js --state ${STATE}"
    return
  fi
  echo "bash -c 'while true; do clear; cat \"${STATE}\" 2>/dev/null; sleep 1; done'"
}
RIGHT_CMD="$(_canon_dashboard_cmd)"

# ── Create tmux: left=agent, right=dashboard ─────────────────────────
# When the agent exits, update dashboard status to idle and keep the pane alive
HEADLESS_FLAGS="$(dega_agent_headless_flags)"
AGENT_CMD="$(dega_agent_command) ${HEADLESS_FLAGS}; "
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
