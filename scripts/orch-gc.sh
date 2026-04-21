#!/usr/bin/env bash
# Orchestrator garbage collector — finds and cleans up stale plans.
#
# A plan (registered "running" in .orchestrator/master.json) is considered
# stale when:
#   1. Its engine handle is no longer alive (engine crashed or exited
#      without deregistering), OR
#   2. Its heartbeat file is older than 10 minutes (engine is hung)
#
# Stale plans are cleaned up by terminating any leftover handles via the
# harness backend and marking the master registry entry as "failed".
#
# Usage: scripts/orch-gc.sh [--dry-run]
#
# Options:
#   --dry-run   List stale plans without killing processes or updating state

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=harness/dispatcher.sh
source "${SCRIPT_DIR}/harness/dispatcher.sh"

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

# --- Enumerate candidate plans ---
#
# Source of truth is master.json (plans with status=="running"). If
# master.json is missing or has no running plans, fall back to scanning
# plan directories that contain a pids/ folder — catches cases where the
# engine crashed before master-registering.

collect_running_slugs() {
  if [[ -f "${ORCH_MASTER_FILE}" ]]; then
    jq -r '.plans[] | select(.status == "running") | .slug' \
      "${ORCH_MASTER_FILE}" 2>/dev/null || true
  fi
}

collect_plan_dirs_with_pids() {
  local plans_root="${ORCH_STATE_DIR}/plans"
  [[ -d "${plans_root}" ]] || return 0
  local dir slug
  for dir in "${plans_root}"/*/; do
    [[ -d "${dir}" ]] || continue
    if [[ -d "${dir}pids" ]]; then
      slug="$(basename "${dir}")"
      printf '%s\n' "${slug}"
    fi
  done
}

# Build unique sorted list of candidate slugs from both sources.
slugs_tmp="$(
  {
    collect_running_slugs
    collect_plan_dirs_with_pids
  } | sort -u | sed '/^$/d'
)"

if [[ -z "${slugs_tmp}" ]]; then
  echo "orch-gc: no running plans found"
  exit 0
fi

now=$(date +%s)
stale_count=0
total_count=0

# --- Per-plan stale check and cleanup ---

terminate_plan_handles() {
  local slug="$1"
  local pid_dir="$(orch_plan_dir "${slug}")/pids"
  [[ -d "${pid_dir}" ]] || return 0

  local active
  active="$(harness::list_active pid_dir="${pid_dir}" 2>/dev/null || true)"
  [[ -n "${active}" ]] || return 0

  local role id handle
  while read -r role id handle; do
    [[ -n "${handle}" ]] || continue
    echo "orch-gc:   terminating ${role}-${id} (handle=${handle})"
    harness::terminate handle="${handle}" 2>/dev/null || {
      echo "orch-gc:   WARN — failed to terminate ${role}-${id} (handle=${handle})" >&2
    }
  done <<<"${active}"
}

while IFS= read -r slug; do
  [[ -n "${slug}" ]] || continue
  total_count=$((total_count + 1))

  is_stale=false
  reason=""

  pid_dir="$(orch_plan_dir "${slug}")/pids"
  engine_alive=false
  if [[ -d "${pid_dir}" ]]; then
    # Any alive handle whose role is "engine" counts as live engine.
    if harness::list_active pid_dir="${pid_dir}" 2>/dev/null |
      awk '{print $1}' | grep -qx 'engine'; then
      engine_alive=true
    fi
  fi

  if [[ "${engine_alive}" == false ]]; then
    is_stale=true
    reason="no alive engine handle"
  fi

  # Heartbeat staleness.
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
      if [[ "${engine_alive}" == false ]]; then
        reason="${reason:+${reason} + }malformed heartbeat"
      fi
    fi
  else
    if [[ "${engine_alive}" == false ]]; then
      reason="${reason:+${reason} + }no heartbeat file"
    fi
  fi

  if [[ "${is_stale}" == false ]]; then
    continue
  fi

  stale_count=$((stale_count + 1))

  age_display="unknown"
  if [[ "${heartbeat_age}" != "n/a" && "${heartbeat_age}" =~ ^[0-9]+$ ]]; then
    age_min=$((heartbeat_age / 60))
    age_sec=$((heartbeat_age % 60))
    age_display="${age_min}m ${age_sec}s"
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo "orch-gc: [dry-run] stale plan: ${slug} (age=${age_display}, reason=${reason})"
  else
    echo "orch-gc: cleaning stale plan: ${slug} (age=${age_display}, reason=${reason})"
    terminate_plan_handles "${slug}"
    # Mark as failed in master registry (no-op if not registered).
    orch_master_deregister "${slug}" "failed" >/dev/null 2>&1 || true
  fi
done <<<"${slugs_tmp}"

if [[ "${DRY_RUN}" == true ]]; then
  echo "orch-gc: found ${stale_count}/${total_count} stale plan(s) (dry-run, nothing cleaned)"
else
  echo "orch-gc: cleaned ${stale_count}/${total_count} stale plan(s)"
fi
