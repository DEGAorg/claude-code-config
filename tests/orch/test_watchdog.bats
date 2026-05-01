#!/usr/bin/env bats
#
# Unit tests for scripts/orch-watchdog.sh — the phase watchdog helper
# shared by orch-engine.sh verify and review calls.

setup() {
  TEST_TMP=$(mktemp -d)
  export TEST_TMP
  export ORCH_STATE_DIR="${TEST_TMP}/.orchestrator"
  export ORCH_REPO_ROOT="${TEST_TMP}"
  mkdir -p "${ORCH_STATE_DIR}"

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck source=../../scripts/orch-state.sh disable=SC1091
  source "${REPO_ROOT}/scripts/orch-state.sh"
  # shellcheck source=../../scripts/orch-watchdog.sh disable=SC1091
  source "${REPO_ROOT}/scripts/orch-watchdog.sh"

  SLUG="test-plan"
  mkdir -p "${ORCH_STATE_DIR}/plans/${SLUG}"
  printf '%s' '{"verification":{},"updatedAt":""}' \
    >"${ORCH_STATE_DIR}/plans/${SLUG}/state.json"
}

teardown() {
  rm -rf "${TEST_TMP}"
}

# --- orch_phase_timeout_secs ---

@test "orch_phase_timeout_secs uses default when env var unset" {
  unset ORCH_VERIFY_PHASE_TIMEOUT
  run orch_phase_timeout_secs verify 300
  [ "${status}" -eq 0 ]
  [ "${output}" = "300" ]
}

@test "orch_phase_timeout_secs prefers env var when set" {
  ORCH_VERIFY_PHASE_TIMEOUT=42 run orch_phase_timeout_secs verify 300
  [ "${status}" -eq 0 ]
  [ "${output}" = "42" ]
}

@test "orch_phase_timeout_secs uppercases phase name for env var lookup" {
  ORCH_REVIEW_PHASE_TIMEOUT=7 run orch_phase_timeout_secs review 600
  [ "${status}" -eq 0 ]
  [ "${output}" = "7" ]
}

# --- orch_run_phase_with_timeout ---

@test "orch_run_phase_with_timeout returns 0 when command succeeds under timeout" {
  set +e
  orch_run_phase_with_timeout verify 10 true
  rc=$?
  set -e
  [ "${rc}" -eq 0 ]
}

@test "orch_run_phase_with_timeout returns command rc when command fails under timeout" {
  set +e
  orch_run_phase_with_timeout verify 10 bash -c 'exit 7'
  rc=$?
  set -e
  [ "${rc}" -eq 7 ]
}

@test "orch_run_phase_with_timeout returns 124 when command exceeds timeout" {
  set +e
  ORCH_VERIFY_PHASE_TIMEOUT=1 orch_run_phase_with_timeout verify 99 sleep 5
  rc=$?
  set -e
  [ "${rc}" -eq 124 ]
}

@test "orch_run_phase_with_timeout respects env override for default" {
  set +e
  ORCH_VERIFY_PHASE_TIMEOUT=1 orch_run_phase_with_timeout verify 99 sleep 5
  rc=$?
  set -e
  [ "${rc}" -eq 124 ]
}

# --- orch_mark_phase_timeout ---

@test "orch_mark_phase_timeout writes failed state with reason and blocking" {
  orch_mark_phase_timeout "${SLUG}" verification 300 "test-blocker"
  state_file="${ORCH_STATE_DIR}/plans/${SLUG}/state.json"
  [ -f "${state_file}" ]
  [ "$(jq -r '.verification.status' "${state_file}")" = "failed" ]
  [ "$(jq -r '.verification.reason' "${state_file}")" = "phase_timeout" ]
  [ "$(jq -r '.verification.blocking' "${state_file}")" = "test-blocker" ]
  [ "$(jq -r '.verification.phaseTimeoutSeconds' "${state_file}")" = "300" ]
  [ -n "$(jq -r '.updatedAt' "${state_file}")" ]
}

@test "orch_mark_phase_timeout works for arbitrary state path" {
  orch_mark_phase_timeout "${SLUG}" finalReview 600 "reviewer-3 (age=700s)"
  state_file="${ORCH_STATE_DIR}/plans/${SLUG}/state.json"
  [ "$(jq -r '.finalReview.status' "${state_file}")" = "failed" ]
  [ "$(jq -r '.finalReview.blocking' "${state_file}")" = "reviewer-3 (age=700s)" ]
  [ "$(jq -r '.finalReview.phaseTimeoutSeconds' "${state_file}")" = "600" ]
}

@test "orch_mark_phase_timeout accepts empty blocking detail" {
  orch_mark_phase_timeout "${SLUG}" verification 300 ""
  state_file="${ORCH_STATE_DIR}/plans/${SLUG}/state.json"
  [ "$(jq -r '.verification.status' "${state_file}")" = "failed" ]
  [ "$(jq -r '.verification.blocking' "${state_file}")" = "" ]
}
