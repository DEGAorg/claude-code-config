#!/usr/bin/env bash
# Phase watchdog helpers — shared between verify and review phases.
#
# Both phases have the same shape: run a long-running phase script, bound
# its wall-clock with `timeout(1)`, take action on rc=124 (timeout killed
# the process). These helpers keep that pattern in one place.
#
# Source-only. Requires orch-state.sh already sourced by the caller for
# `orch_plan_state_file` and `orch_write_state`.

# Source guard — safe to source multiple times.
if [[ -n "${ORCH_WATCHDOG_SOURCED:-}" ]]; then
  return 0
fi
ORCH_WATCHDOG_SOURCED=1

# Resolve the wall-clock timeout for a phase.
# Usage: orch_phase_timeout_secs <phase> <default_secs>
# Echoes: numeric seconds — ORCH_<PHASE>_PHASE_TIMEOUT if set, otherwise default.
orch_phase_timeout_secs() {
  local phase="$1" default_secs="$2"
  local var_name
  var_name="ORCH_$(printf '%s' "${phase}" | tr '[:lower:]' '[:upper:]')_PHASE_TIMEOUT"
  printf '%s' "${!var_name:-${default_secs}}"
}

# Run a command under a wall-clock timeout.
# Usage: orch_run_phase_with_timeout <phase> <default_secs> <cmd> [args...]
# Returns the command's exit code unchanged. rc=124 means the timeout
# killed it. The caller MUST fence with `set +e` / `set -e` (or `|| rc=$?`)
# so errexit does not abort the engine on a non-zero rc.
orch_run_phase_with_timeout() {
  local phase="$1" default_secs="$2"
  shift 2
  local secs
  secs=$(orch_phase_timeout_secs "${phase}" "${default_secs}")
  timeout "${secs}" "$@"
}

# Write a phase_timeout failure record to state at the given JSON path.
# Usage: orch_mark_phase_timeout <slug> <state_path> <timeout_secs> [blocking]
#   state_path: top-level key in state.json to mutate (e.g., "verification",
#               "finalReview"). The function sets
#               .<state_path>.status      = "failed"
#               .<state_path>.reason      = "phase_timeout"
#               .<state_path>.blocking    = <blocking>
#               .<state_path>.phaseTimeoutSeconds = <timeout_secs>
#               .updatedAt                = now
# Logs a single stderr line naming the phase and blocker.
orch_mark_phase_timeout() {
  local slug="$1" state_path="$2" timeout_secs="$3" blocking="${4:-}"
  local state_file
  state_file=$(orch_plan_state_file "${slug}")
  if [[ ! -f "${state_file}" ]]; then
    echo "orch-watchdog: state file not found for slug ${slug}" >&2
    return 1
  fi
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local updated
  updated=$(jq \
    --arg now "${now}" \
    --arg path "${state_path}" \
    --arg reason "phase_timeout" \
    --arg blocking "${blocking}" \
    --argjson timeout "${timeout_secs}" \
    '.[$path].status = "failed" |
     .[$path].reason = $reason |
     .[$path].blocking = $blocking |
     .[$path].phaseTimeoutSeconds = $timeout |
     .updatedAt = $now' "${state_file}")
  orch_write_state "${slug}" "${updated}"
  echo "orch-watchdog: ${state_path} marked failed (phase_timeout after ${timeout_secs}s)${blocking:+; blocking: ${blocking}}" >&2
}

# Bound verify-failure REVISE re-execs by MAX_ITERATIONS.
# Usage: orch_verify_iteration_exhausted <slug> <max_iterations>
#   - Reads .verification.iteration from the plan's state.json.
#   - iteration < max_iterations: returns 1 (not exhausted, no state mutation).
#   - iteration >= max_iterations: writes terminal failure to state and
#     returns 0. Sets:
#         .status                     = "failed"
#         .verification.status        = "failed"
#         .verification.reason        = "verify_iteration_exhausted"
#         .verification.maxIterations = <max_iterations>
#         .updatedAt                  = now (RFC3339 UTC)
#     .verification.iteration is preserved.
orch_verify_iteration_exhausted() {
  local slug="$1" max="$2"
  local state_file
  state_file=$(orch_plan_state_file "${slug}")
  if [[ ! -f "${state_file}" ]]; then
    echo "orch-watchdog: state file not found for slug ${slug}" >&2
    return 1
  fi
  local iter
  iter=$(jq -r '.verification.iteration // 0' "${state_file}")
  if [[ "${iter}" -lt "${max}" ]]; then
    return 1
  fi
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local updated
  updated=$(jq \
    --arg now "${now}" \
    --arg reason "verify_iteration_exhausted" \
    --argjson max "${max}" \
    '.status = "failed" |
     .verification.status = "failed" |
     .verification.reason = $reason |
     .verification.maxIterations = $max |
     .updatedAt = $now' "${state_file}")
  orch_write_state "${slug}" "${updated}"
  echo "orch-watchdog: verify-iteration exhausted (iteration=${iter}, max=${max}) — plan ${slug} marked failed" >&2
  return 0
}
