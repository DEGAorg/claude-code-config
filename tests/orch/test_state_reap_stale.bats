#!/usr/bin/env bats
#
# Unit tests for orch_state_reap_stale (scripts/orch-state.sh).
#
# Closes the canon-tui status-watchdog ask: when the engine dies
# ungracefully (Ctrl-C, kill, OOM, sleep, network drop) state.json
# stays at "running" forever and canon-tui's plan-execution panel
# rendered "● LIVE" for a corpse. The reaper sweeps every plan's
# heartbeat sidecar and flips status to "aborted" when it's stale.

setup() {
  TEST_TMP=$(mktemp -d)
  export TEST_TMP
  export ORCH_STATE_DIR="${TEST_TMP}/.orchestrator"
  export ORCH_REPO_ROOT="${TEST_TMP}"
  mkdir -p "${ORCH_STATE_DIR}"

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck source=../../scripts/orch-state.sh disable=SC1091
  source "${REPO_ROOT}/scripts/orch-state.sh"
}

teardown() {
  trash "${TEST_TMP}" 2>/dev/null || rm -rf "${TEST_TMP}"
}

# Helper: drop a plan with a given status + heartbeat age (seconds).
# heartbeat=-1 means no sidecar at all.
make_plan() {
  local slug="$1" status="$2" hb_age="$3"
  local plan_dir="${ORCH_STATE_DIR}/plans/${slug}"
  mkdir -p "${plan_dir}"
  printf '%s' "{\"status\":\"${status}\",\"items\":[],\"finalReview\":{\"status\":\"running\"}}" \
    >"${plan_dir}/state.json"
  if [[ "${hb_age}" != "-1" ]]; then
    local now hb
    now=$(date -u +%s)
    hb=$((now - hb_age))
    printf '%s\n' "${hb}" >"${plan_dir}/heartbeat"
  fi
}

@test "reaps a running plan whose heartbeat is older than the threshold" {
  ORCH_STALE_HEARTBEAT_SECS=10 make_plan "stale" "running" 60
  ORCH_STALE_HEARTBEAT_SECS=10 orch_state_reap_stale

  state_file="${ORCH_STATE_DIR}/plans/stale/state.json"
  [ "$(jq -r '.status' "${state_file}")" = "aborted" ]
  [ "$(jq -r '.finalReview.status' "${state_file}")" = "aborted" ]
  jq -e '.lastError | test("heartbeat stale")' "${state_file}" >/dev/null
}

@test "leaves a fresh-heartbeat running plan alone" {
  ORCH_STALE_HEARTBEAT_SECS=120 make_plan "fresh" "running" 5
  ORCH_STALE_HEARTBEAT_SECS=120 orch_state_reap_stale

  state_file="${ORCH_STATE_DIR}/plans/fresh/state.json"
  [ "$(jq -r '.status' "${state_file}")" = "running" ]
  [ "$(jq -r '.finalReview.status' "${state_file}")" = "running" ]
}

@test "does not touch terminal states (done, failed)" {
  ORCH_STALE_HEARTBEAT_SECS=10 make_plan "done" "done" 9999
  ORCH_STALE_HEARTBEAT_SECS=10 make_plan "failed" "failed" 9999
  ORCH_STALE_HEARTBEAT_SECS=10 orch_state_reap_stale

  [ "$(jq -r '.status' "${ORCH_STATE_DIR}/plans/done/state.json")" = "done" ]
  [ "$(jq -r '.status' "${ORCH_STATE_DIR}/plans/failed/state.json")" = "failed" ]
}

@test "treats a missing heartbeat sidecar as stale" {
  ORCH_STALE_HEARTBEAT_SECS=10 make_plan "no-hb" "running" -1
  ORCH_STALE_HEARTBEAT_SECS=10 orch_state_reap_stale

  state_file="${ORCH_STATE_DIR}/plans/no-hb/state.json"
  [ "$(jq -r '.status' "${state_file}")" = "aborted" ]
}

@test "is a no-op when the plans dir does not exist" {
  trash "${ORCH_STATE_DIR}/plans" 2>/dev/null || rm -rf "${ORCH_STATE_DIR}/plans"
  run orch_state_reap_stale
  [ "${status}" -eq 0 ]
}

@test "preserves a running finalReview when the top-level status is also flipped" {
  ORCH_STALE_HEARTBEAT_SECS=10 make_plan "review-running" "running" 60
  state_file="${ORCH_STATE_DIR}/plans/review-running/state.json"
  ORCH_STALE_HEARTBEAT_SECS=10 orch_state_reap_stale
  # finalReview was "running" so it must transition to "aborted"
  [ "$(jq -r '.finalReview.status' "${state_file}")" = "aborted" ]
}

@test "does not flip a finalReview that is not running" {
  ORCH_STALE_HEARTBEAT_SECS=10
  local plan_dir="${ORCH_STATE_DIR}/plans/review-done"
  mkdir -p "${plan_dir}"
  printf '%s' '{"status":"running","items":[],"finalReview":{"status":"passed"}}' \
    >"${plan_dir}/state.json"
  local hb
  hb=$(($(date -u +%s) - 60))
  printf '%s\n' "${hb}" >"${plan_dir}/heartbeat"
  ORCH_STALE_HEARTBEAT_SECS=10 orch_state_reap_stale

  [ "$(jq -r '.status' "${plan_dir}/state.json")" = "aborted" ]
  [ "$(jq -r '.finalReview.status' "${plan_dir}/state.json")" = "passed" ]
}
