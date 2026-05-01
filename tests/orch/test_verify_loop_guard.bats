#!/usr/bin/env bats
#
# Unit tests for the verify-iteration guard.
#
# Forensics: Issue #241 (2026-04-25) — verify-failure REVISE re-execs were
# unbounded because verification.iteration was incremented but never compared
# to MAX_ITERATIONS. The guard `orch_verify_iteration_exhausted` short-circuits
# the REVISE/exec path once verification.iteration >= MAX_ITERATIONS.
#
# Contract (added in scripts/orch-watchdog.sh by item 4 of the plan):
#   orch_verify_iteration_exhausted <slug> <max_iterations>
#     - Reads .verification.iteration from the plan's state.json.
#     - If iteration < max_iterations: returns 1 (not exhausted, no state change).
#     - If iteration >= max_iterations: writes terminal failure to state and
#       returns 0 (exhausted).
#         .status                   = "failed"
#         .verification.status      = "failed"
#         .verification.reason      = "verify_iteration_exhausted"
#         .verification.maxIterations = <max_iterations>
#         .updatedAt                = now (RFC3339 UTC)

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
  PLAN_DIR="${ORCH_STATE_DIR}/plans/${SLUG}"
  STATE_FILE="${PLAN_DIR}/state.json"
  mkdir -p "${PLAN_DIR}"
}

teardown() {
  rm -rf "${TEST_TMP}"
}

# Write a state.json with verification.iteration = $1.
write_state_with_iter() {
  local iter="$1"
  jq -n \
    --argjson iter "${iter}" \
    '{
      status: "verifying",
      verification: {
        status: "failed",
        uncheckedCount: 1,
        iteration: $iter
      },
      updatedAt: "2026-04-27T00:00:00Z"
    }' >"${STATE_FILE}"
}

# --- iteration < MAX_ITERATIONS: not exhausted, no state mutation ---

@test "orch_verify_iteration_exhausted returns 1 when iteration is 2 and max is 3" {
  write_state_with_iter 2
  set +e
  orch_verify_iteration_exhausted "${SLUG}" 3
  rc=$?
  set -e
  [ "${rc}" -eq 1 ]
}

@test "orch_verify_iteration_exhausted does not mutate state when iteration is below max" {
  write_state_with_iter 2
  before=$(cat "${STATE_FILE}")
  set +e
  orch_verify_iteration_exhausted "${SLUG}" 3
  set -e
  after=$(cat "${STATE_FILE}")
  [ "${before}" = "${after}" ]
  # Plan status remains the engine's pre-guard value (verifying).
  [ "$(jq -r '.status' "${STATE_FILE}")" = "verifying" ]
}

# --- iteration >= MAX_ITERATIONS: exhausted, terminal failure written ---

@test "orch_verify_iteration_exhausted returns 0 when iteration equals max" {
  write_state_with_iter 3
  set +e
  orch_verify_iteration_exhausted "${SLUG}" 3
  rc=$?
  set -e
  [ "${rc}" -eq 0 ]
}

@test "orch_verify_iteration_exhausted writes terminal failed status when exhausted" {
  write_state_with_iter 3
  orch_verify_iteration_exhausted "${SLUG}" 3 || true
  [ "$(jq -r '.status' "${STATE_FILE}")" = "failed" ]
  [ "$(jq -r '.verification.status' "${STATE_FILE}")" = "failed" ]
  [ "$(jq -r '.verification.reason' "${STATE_FILE}")" = "verify_iteration_exhausted" ]
  [ "$(jq -r '.verification.maxIterations' "${STATE_FILE}")" = "3" ]
}

@test "orch_verify_iteration_exhausted refreshes updatedAt when exhausted" {
  write_state_with_iter 3
  orch_verify_iteration_exhausted "${SLUG}" 3 || true
  updated_at=$(jq -r '.updatedAt' "${STATE_FILE}")
  [ -n "${updated_at}" ]
  [ "${updated_at}" != "2026-04-27T00:00:00Z" ]
  # RFC3339 UTC shape.
  [[ "${updated_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "orch_verify_iteration_exhausted treats iteration > max as exhausted" {
  write_state_with_iter 5
  set +e
  orch_verify_iteration_exhausted "${SLUG}" 3
  rc=$?
  set -e
  [ "${rc}" -eq 0 ]
  [ "$(jq -r '.status' "${STATE_FILE}")" = "failed" ]
}

# --- preserves prior verification fields when marking exhausted ---

@test "orch_verify_iteration_exhausted preserves verification.iteration when exhausted" {
  write_state_with_iter 3
  orch_verify_iteration_exhausted "${SLUG}" 3 || true
  [ "$(jq -r '.verification.iteration' "${STATE_FILE}")" = "3" ]
}
