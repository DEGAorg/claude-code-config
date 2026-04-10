#!/usr/bin/env bash
# Orchestrator garbage collector — finds and kills stale orch-* tmux sessions.
#
# A session is considered stale when:
#   1. It has no "engine" window (engine crashed or exited without cleanup), OR
#   2. Its heartbeat file is older than 10 minutes (engine is hung)
#
# Usage: scripts/orch-gc.sh [--dry-run]
#
# Options:
#   --dry-run   List stale sessions without killing them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

STALE_THRESHOLD=600 # 10 minutes in seconds
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    echo "usage: orch-gc.sh [--dry-run]" >&2
    exit 1
    ;;
  *)
    echo "error: unexpected argument: $1" >&2
    echo "usage: orch-gc.sh [--dry-run]" >&2
    exit 1
    ;;
  esac
done

# List all orch-* tmux sessions. Exit cleanly if tmux server is not running.
sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^orch-' || true)

if [[ -z "${sessions}" ]]; then
  echo "orch-gc: no orch-* sessions found"
  exit 0
fi

now=$(date +%s)
stale_count=0
total_count=0

while IFS= read -r session; do
  total_count=$((total_count + 1))
  slug="${session#orch-}"
  is_stale=false
  reason=""

  # Check 1: does the session have an "engine" window?
  has_engine=true
  if ! tmux has-session -t "${session}" 2>/dev/null; then
    # Session disappeared between list and check — skip
    continue
  fi
  if ! tmux list-windows -t "${session}" -F '#{window_name}' 2>/dev/null | grep -q '^engine$'; then
    has_engine=false
    is_stale=true
    reason="no engine window"
  fi

  # Check 2: is the heartbeat stale (>10min)?
  heartbeat_file="${ORCH_STATE_DIR}/plans/${slug}/heartbeat"
  heartbeat_age="n/a"
  if [[ -f "${heartbeat_file}" ]]; then
    heartbeat_epoch=$(cat "${heartbeat_file}")
    if [[ "${heartbeat_epoch}" =~ ^[0-9]+$ ]]; then
      heartbeat_age=$((now - heartbeat_epoch))
      if ((heartbeat_age > STALE_THRESHOLD)); then
        is_stale=true
        if [[ -n "${reason}" ]]; then
          reason="${reason} + heartbeat stale (${heartbeat_age}s)"
        else
          reason="heartbeat stale (${heartbeat_age}s)"
        fi
      fi
    else
      # Malformed heartbeat file — treat as stale if no engine window
      if [[ "${has_engine}" == false ]]; then
        is_stale=true
        reason="${reason} + malformed heartbeat"
      fi
    fi
  else
    # No heartbeat file — stale if no engine window
    if [[ "${has_engine}" == false ]]; then
      if [[ -n "${reason}" ]]; then
        reason="${reason} + no heartbeat file"
      else
        reason="no heartbeat file"
      fi
    fi
  fi

  if [[ "${is_stale}" == false ]]; then
    continue
  fi

  stale_count=$((stale_count + 1))

  # Format heartbeat age for display
  age_display="unknown"
  if [[ "${heartbeat_age}" != "n/a" && "${heartbeat_age}" =~ ^[0-9]+$ ]]; then
    age_min=$((heartbeat_age / 60))
    age_sec=$((heartbeat_age % 60))
    age_display="${age_min}m ${age_sec}s"
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo "orch-gc: [dry-run] stale session: ${session} (slug=${slug}, age=${age_display}, reason=${reason})"
  else
    echo "orch-gc: killing stale session: ${session} (slug=${slug}, age=${age_display}, reason=${reason})"
    tmux kill-session -t "${session}" 2>/dev/null || {
      echo "orch-gc: WARN — failed to kill session ${session}" >&2
    }
  fi
done <<<"${sessions}"

if [[ "${DRY_RUN}" == true ]]; then
  echo "orch-gc: found ${stale_count}/${total_count} stale session(s) (dry-run, nothing killed)"
else
  echo "orch-gc: killed ${stale_count}/${total_count} stale session(s)"
fi
