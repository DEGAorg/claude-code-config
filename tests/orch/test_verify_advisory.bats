#!/usr/bin/env bats
#
# Tests for verify-advisory mode (issue #241 follow-up).
#
# Forensics: Issue #241 (2026-04-25) — strict completion-criteria gating
# caused unbounded REVISE loops because the verifier and reviewer answer
# different questions. This plan flips the default to advisory: verify
# still runs, status is still recorded, but a non-zero verify_rc no
# longer gates SHIP. `verify.mode: enforce` opts back into the old
# behavior.
#
# Contract under test (added by item 3 of the plan to scripts/orch-state.sh
# and called from scripts/orch-engine.sh):
#
#   orch_get_verify_mode <yaml_path>
#     - Reads .verify.mode from the YAML config (yq if available, grep
#       fallback otherwise).
#     - Returns "advisory" if the file is missing, the verify block is
#       absent, or the value is empty/unknown.
#     - Returns "enforce" only when explicitly set to "enforce".
#
#   orch_verify_should_gate <verify_rc> <mode>
#     - Returns 0 (gate → REVISE) when verify_rc != 0 AND mode == enforce.
#     - Returns 1 (do not gate → SHIP) in every other case, including
#       advisory-on-failure and any-mode-on-success.
#     - Unknown modes are treated as advisory (safe default).
#
# These two helpers, together, encode the three behavioural cases the
# plan calls out:
#   (a) advisory + verify_rc=1 → SHIP, status recorded as failed
#   (b) enforce  + verify_rc=1 → REVISE (current behaviour preserved)
#   (c) advisory + verify_rc=0 → SHIP, status recorded as passed

setup() {
  TEST_TMP="$(mktemp -d -t orch-verify-adv-XXXXXX)"
  export TEST_TMP
  export ORCH_REPO_ROOT="${TEST_TMP}"
  export ORCH_STATE_DIR="${TEST_TMP}/.orchestrator"
  mkdir -p "${ORCH_STATE_DIR}"

  REPO_ROOT_REAL="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck source=../../scripts/orch-state.sh disable=SC1091
  source "${REPO_ROOT_REAL}/scripts/orch-state.sh"
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

# --- orch_get_verify_mode: config parsing ---

@test "orch_get_verify_mode defaults to advisory when verify block is absent" {
  cat >"${TEST_TMP}/dega-core.yaml" <<'YAML'
github:
  sync: true
provider: github
YAML
  result="$(orch_get_verify_mode "${TEST_TMP}/dega-core.yaml")"
  [ "${result}" = "advisory" ]
}

@test "orch_get_verify_mode returns advisory when explicitly set" {
  cat >"${TEST_TMP}/dega-core.yaml" <<'YAML'
verify:
  mode: advisory
YAML
  [ "$(orch_get_verify_mode "${TEST_TMP}/dega-core.yaml")" = "advisory" ]
}

@test "orch_get_verify_mode returns enforce when explicitly set" {
  cat >"${TEST_TMP}/dega-core.yaml" <<'YAML'
verify:
  mode: enforce
YAML
  [ "$(orch_get_verify_mode "${TEST_TMP}/dega-core.yaml")" = "enforce" ]
}

@test "orch_get_verify_mode tolerates surrounding config keys" {
  cat >"${TEST_TMP}/dega-core.yaml" <<'YAML'
provider: github
github:
  sync: true
verify:
  mode: enforce
check_command: bash
YAML
  [ "$(orch_get_verify_mode "${TEST_TMP}/dega-core.yaml")" = "enforce" ]
}

@test "orch_get_verify_mode defaults to advisory when file is missing" {
  [ "$(orch_get_verify_mode "${TEST_TMP}/nonexistent.yaml")" = "advisory" ]
}

@test "orch_get_verify_mode treats unknown mode value as advisory" {
  cat >"${TEST_TMP}/dega-core.yaml" <<'YAML'
verify:
  mode: bogus
YAML
  [ "$(orch_get_verify_mode "${TEST_TMP}/dega-core.yaml")" = "advisory" ]
}

# --- orch_verify_should_gate: gating decision ---
#
# Return-code semantics: 0 means "gate SHIP → set REVIEW_RESULT=REVISE";
# 1 means "do not gate → SHIP proceeds". This matches the bash idiom
# `if orch_verify_should_gate "$rc" "$mode"; then REVIEW_RESULT=REVISE; fi`.

@test "advisory mode + verify_rc=1 does not gate (case a: SHIP on failure)" {
  set +e
  orch_verify_should_gate 1 advisory
  rc=$?
  set -e
  [ "${rc}" -eq 1 ]
}

@test "enforce mode + verify_rc=1 gates (case b: REVISE preserves old behavior)" {
  set +e
  orch_verify_should_gate 1 enforce
  rc=$?
  set -e
  [ "${rc}" -eq 0 ]
}

@test "advisory mode + verify_rc=0 does not gate (case c: SHIP on success)" {
  set +e
  orch_verify_should_gate 0 advisory
  rc=$?
  set -e
  [ "${rc}" -eq 1 ]
}

@test "enforce mode + verify_rc=0 does not gate (success ships in either mode)" {
  set +e
  orch_verify_should_gate 0 enforce
  rc=$?
  set -e
  [ "${rc}" -eq 1 ]
}

@test "advisory mode + verify_rc=124 (timeout) does not gate" {
  set +e
  orch_verify_should_gate 124 advisory
  rc=$?
  set -e
  [ "${rc}" -eq 1 ]
}

@test "enforce mode + verify_rc=124 (timeout) gates" {
  set +e
  orch_verify_should_gate 124 enforce
  rc=$?
  set -e
  [ "${rc}" -eq 0 ]
}

@test "unknown mode + verify_rc=1 treated as advisory (no gate)" {
  set +e
  orch_verify_should_gate 1 bogus
  rc=$?
  set -e
  [ "${rc}" -eq 1 ]
}
