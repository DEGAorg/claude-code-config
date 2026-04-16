#!/usr/bin/env bash
# Canon Runner — launches a strategy runner as a managed background process.
#
# Handles dashboard state updates on start, stop, crash, and each poll cycle.
# Proper signal traps ensure the dashboard always reflects actual state.
#
# Usage:
#   bash "$DEGA_CORE_HOME/scripts/canon-runner.sh" [--dry-run]
#
# Must be run from a Canon project root (where src/main.ts and
# .canon/state.json exist).
#
# Writes:
#   .canon/execution/runner.log    — raw runner stdout
#   .canon/execution/<date>.jsonl  — structured decision log (by runner)
#   .canon/state.json              — dashboard state (metrics + logs)
#   .canon/execution/runner.pid    — PID file for stop/status checks

set -euo pipefail

STATE=".canon/state.json"
RUNNER_LOG=".canon/execution/runner.log"
PID_FILE=".canon/execution/runner.pid"
TAIL_FIFO=".canon/execution/.tail-fifo"
DEGA_CORE_HOME="${DEGA_CORE_HOME:-${HOME}/.degacore}"
TUI_WRITE="${DEGA_CORE_HOME}/scripts/terminal-ui-write.sh"

# ── Guard: must be in a Canon project ────────────────────────────────────────
if [[ ! -f "src/main.ts" ]]; then
  echo "error: src/main.ts not found — run from Canon project root" >&2
  exit 1
fi

mkdir -p .canon/execution

# ── Guard: check for already-running instance ────────────────────────────────
if [[ -f "${PID_FILE}" ]]; then
  OLD_PID=$(cat "${PID_FILE}")
  if kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "error: runner already running (PID ${OLD_PID})" >&2
    echo "  stop it first: kill ${OLD_PID}" >&2
    exit 1
  fi
  rm -f "${PID_FILE}"
fi

# ── Dashboard helper ─────────────────────────────────────────────────────────
tui() {
  if [[ -f "${TUI_WRITE}" ]]; then
    bash "${TUI_WRITE}" "${STATE}" "$@" || true
  fi
}

# ── Flags ────────────────────────────────────────────────────────────────────
DRY_RUN_FLAG=""
MODE="live"
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN_FLAG="--dry-run"
  MODE="dry-run"
fi

# ── Counters ─────────────────────────────────────────────────────────────────
_CYCLES=0
_SIGNALS=0
_ERRORS=0
_GAMES=0
_MARKETS=0

# ── Load .env if present ─────────────────────────────────────────────────────
# Node.js does not auto-load .env files. Export vars so the runner child
# process inherits them.
if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# ── Reset dashboard for execution phase ──────────────────────────────────────
tui phase=run status=executing metrics=reset \
  "metric.mode=${MODE}" \
  metric.cycles=0 metric.signals=0 metric.errors=0 \
  metric.games=0 metric.markets=0 \
  log.info="Launching strategy runner (${MODE})..."

# ── Cleanup trap — always fires on exit/signal ───────────────────────────────
RUNNER_PID=""
TAIL_PID=""
WATCHER_PID=""

cleanup() {
  local exit_code=$?

  # Kill monitoring processes
  if [[ -n "${TAIL_PID}" ]] && kill -0 "${TAIL_PID}" 2>/dev/null; then
    kill "${TAIL_PID}" 2>/dev/null || true
  fi
  if [[ -n "${WATCHER_PID}" ]] && kill -0 "${WATCHER_PID}" 2>/dev/null; then
    kill "${WATCHER_PID}" 2>/dev/null || true
  fi
  rm -f "${TAIL_FIFO}"

  # Kill runner if still alive
  if [[ -n "${RUNNER_PID}" ]] && kill -0 "${RUNNER_PID}" 2>/dev/null; then
    kill "${RUNNER_PID}" 2>/dev/null || true
    wait "${RUNNER_PID}" 2>/dev/null || true
  fi

  rm -f "${PID_FILE}"

  # Signal exits (INT=130, TERM=143) are clean stops, not crashes
  if [[ ${exit_code} -eq 0 || ${exit_code} -eq 130 || ${exit_code} -eq 143 ]]; then
    tui status=idle \
      log.warn="Runner stopped — ${_CYCLES} cycles, ${_SIGNALS} signals, ${_ERRORS} errors"
  else
    tui status=error \
      log.error="Runner crashed (exit ${exit_code}) — ${_CYCLES} cycles, ${_SIGNALS} signals, ${_ERRORS} errors"
  fi
}
trap cleanup EXIT

# Forward signals so the runner child gets killed cleanly
trap 'exit 130' INT
trap 'exit 143' TERM

# ── Launch runner ────────────────────────────────────────────────────────────
# shellcheck disable=SC2086
pnpm exec tsx src/main.ts ${DRY_RUN_FLAG} >>"${RUNNER_LOG}" 2>&1 &
RUNNER_PID=$!
echo "${RUNNER_PID}" >"${PID_FILE}"

# Verify it started
sleep 1
if ! kill -0 "${RUNNER_PID}" 2>/dev/null; then
  echo "error: runner failed to start — check ${RUNNER_LOG}" >&2
  tui status=error log.error="Runner failed to start"
  rm -f "${PID_FILE}"
  exit 1
fi

echo "canon-runner: started (PID ${RUNNER_PID}, ${MODE})"
echo "  log: ${RUNNER_LOG}"
echo "  pid: ${PID_FILE}"

tui log.info="Runner started (PID ${RUNNER_PID})"

# ── Tail the log and parse tagged output ─────────────────────────────────────
# A pipe (tail | while) runs the loop in a subshell — counter variables
# don't propagate back, and `read` blocks forever when the runner dies
# (no new lines = no chance to check liveness). Fix: use a FIFO so the
# while loop runs in the main shell, and a background watcher that kills
# tail when the runner exits, giving the FIFO an EOF.

rm -f "${TAIL_FIFO}"
mkfifo "${TAIL_FIFO}"

tail -n 0 -F "${RUNNER_LOG}" >"${TAIL_FIFO}" 2>/dev/null &
TAIL_PID=$!

# Watcher: poll runner liveness, kill tail on death so FIFO gets EOF
(
  while kill -0 "${RUNNER_PID}" 2>/dev/null; do sleep 3; done
  kill "${TAIL_PID}" 2>/dev/null || true
) &
WATCHER_PID=$!

while IFS= read -r line; do
  # Parse tag from first word (START, SCAN, NO_EDGE, SIGNAL, SCAN_ERROR, STOP)
  tag="${line%% *}"
  msg="${line#* }"
  level="info"

  case "${tag}" in
  SCAN) ;; # cycle started, just log it
  NO_EDGE)
    _CYCLES=$((_CYCLES + 1))
    # Extract games/markets counts from message if present
    # Format: "Cycle N — X games, Y markets, Z matched, no edges"
    if [[ "${msg}" =~ ([0-9]+)\ games ]]; then
      _GAMES="${BASH_REMATCH[1]}"
    fi
    if [[ "${msg}" =~ ([0-9]+)\ markets ]]; then
      _MARKETS="${BASH_REMATCH[1]}"
    fi
    ;;
  SIGNAL)
    _SIGNALS=$((_SIGNALS + 1))
    level="warn"
    ;;
  SCAN_ERROR)
    _CYCLES=$((_CYCLES + 1))
    _ERRORS=$((_ERRORS + 1))
    level="error"
    ;;
  STOP) level="warn" ;;
  esac

  tui "log.${level}=${msg}" \
    "metric.cycles=${_CYCLES}" \
    "metric.signals=${_SIGNALS}" \
    "metric.errors=${_ERRORS}" \
    "metric.games=${_GAMES}" \
    "metric.markets=${_MARKETS}"
done <"${TAIL_FIFO}"

# Clean up monitoring processes
kill "${TAIL_PID}" 2>/dev/null || true
kill "${WATCHER_PID}" 2>/dev/null || true
wait "${TAIL_PID}" 2>/dev/null || true
wait "${WATCHER_PID}" 2>/dev/null || true
rm -f "${TAIL_FIFO}"

# Wait for runner to fully exit
wait "${RUNNER_PID}" 2>/dev/null || true
