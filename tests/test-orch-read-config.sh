#!/usr/bin/env bash
# Regression test for orch_read_config() — verifies anchored grep
# prevents prefix collisions between poll_interval_seconds,
# review_poll_interval_seconds, and verify_poll_interval_seconds.
#
# Usage: bash tests/test-orch-read-config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# --- Helpers ---

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected: '${expected}'"
    echo "    actual:   '${actual}'"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup: create a temp config with prefix collisions ---

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

cat >"${TMPDIR_TEST}/dega-core.yaml" <<'EOF'
version: 1
max_iterations: 3
poll_interval_seconds: 15
review_poll_interval_seconds: 10
verify_poll_interval_seconds: 10
check_command: echo ok
EOF

# Point orch-state.sh at the temp directory
export ORCH_REPO_ROOT="${TMPDIR_TEST}"
export ORCH_STATE_DIR="${TMPDIR_TEST}/.orchestrator"

# Source the library (guard against direct execution is fine — we source it)
# shellcheck source=../scripts/orch-state.sh
source "${REPO_ROOT}/scripts/orch-state.sh"

# --- Tests ---

echo "=== orch_read_config prefix collision regression ==="

# Test 1: poll_interval_seconds must return exactly "15"
result=$(orch_read_config "poll_interval_seconds")
assert_eq "poll_interval_seconds returns 15" "15" "${result}"

# Test 2: review_poll_interval_seconds must return exactly "10"
result=$(orch_read_config "review_poll_interval_seconds")
assert_eq "review_poll_interval_seconds returns 10" "10" "${result}"

# Test 3: verify_poll_interval_seconds must return exactly "10"
result=$(orch_read_config "verify_poll_interval_seconds")
assert_eq "verify_poll_interval_seconds returns 10" "10" "${result}"

# Test 4: poll_interval_seconds must be a single line (no newlines)
result=$(orch_read_config "poll_interval_seconds")
line_count=$(printf '%s' "${result}" | wc -l | tr -d ' ')
assert_eq "poll_interval_seconds is single value (no newlines)" "0" "${line_count}"

# Test 5: nonexistent key returns empty string
result=$(orch_read_config "nonexistent_key")
assert_eq "nonexistent key returns empty" "" "${result}"

# Test 6: max_iterations (no prefix collision risk, sanity check)
result=$(orch_read_config "max_iterations")
assert_eq "max_iterations returns 3" "3" "${result}"

# --- Summary ---

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
