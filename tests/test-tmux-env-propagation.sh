#!/usr/bin/env bash
# Tests for tmux environment variable propagation (GH_SYNC, REPO_ROOT, etc.)
#
# Verifies that orch-run.sh's belt-and-suspenders approach works:
#   1. `tmux set-environment` injects vars into the session
#   2. Inline env prefix on the engine command propagates GH_SYNC
#   3. The engine diagnostic log line prints the correct value
#
# Also validates the static code paths in orch-run.sh and orch-engine.sh.
#
# Usage: bash tests/test-tmux-env-propagation.sh

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
    echo "    expected: ${expected}"
    echo "    actual:   ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "${haystack}" | grep -qF "${needle}"; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected to contain: ${needle}"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup ---

TEST_SESSION="test-env-prop-$$"
OUTPUT_FILE=$(mktemp /tmp/test-env-prop-XXXXXX)

cleanup() {
  tmux kill-session -t "${TEST_SESSION}" 2>/dev/null || true
  rm -f "${OUTPUT_FILE}"
}
trap cleanup EXIT

# =====================================================================
echo ""
echo "=== Test 1: tmux set-environment propagates GH_SYNC to new windows ==="
# =====================================================================
# Simulates orch-run.sh: create session, set-environment, spawn window
# that reads GH_SYNC, and verify the value arrives.

tmux new-session -d -s "${TEST_SESSION}" -n "init" "sleep 60"

# Inject GH_SYNC=true via set-environment (as orch-run.sh does at line 371)
tmux set-environment -t "${TEST_SESSION}" GH_SYNC "true"

# Spawn a window that reads GH_SYNC and writes it to a file
tmux new-window -d -t "${TEST_SESSION}" -n "env-check" \
  "echo \"GH_SYNC=\${GH_SYNC:-unset}\" > '${OUTPUT_FILE}'; sleep 1"

# Wait for the window to execute
sleep 3

RESULT=$(cat "${OUTPUT_FILE}" 2>/dev/null || echo "EMPTY")
assert_eq "tmux set-environment: GH_SYNC arrives in new window" \
  "GH_SYNC=true" "${RESULT}"

# =====================================================================
echo ""
echo "=== Test 2: inline env prefix propagates GH_SYNC ==="
# =====================================================================
# Simulates the inline prefix on the engine command (orch-run.sh line 388)

: >"${OUTPUT_FILE}"
tmux new-window -d -t "${TEST_SESSION}" -n "inline-check" \
  "GH_SYNC='true' bash -c 'echo \"GH_SYNC=\${GH_SYNC:-unset}\" > \"${OUTPUT_FILE}\"'; sleep 1"

sleep 3

RESULT2=$(cat "${OUTPUT_FILE}" 2>/dev/null || echo "EMPTY")
assert_eq "inline env prefix: GH_SYNC arrives in command" \
  "GH_SYNC=true" "${RESULT2}"

# =====================================================================
echo ""
echo "=== Test 3: GH_SYNC defaults to false when not set ==="
# =====================================================================
# Simulates engine behavior when GH_SYNC is not in the environment

: >"${OUTPUT_FILE}"
# Unset GH_SYNC in the session environment
tmux set-environment -t "${TEST_SESSION}" -u GH_SYNC

tmux new-window -d -t "${TEST_SESSION}" -n "default-check" \
  "bash -c 'echo \"GH_SYNC=\${GH_SYNC:-false}\" > \"${OUTPUT_FILE}\"'; sleep 1"

sleep 3

RESULT3=$(cat "${OUTPUT_FILE}" 2>/dev/null || echo "EMPTY")
assert_eq "default: GH_SYNC falls back to false" \
  "GH_SYNC=false" "${RESULT3}"

# Clean up test tmux session
tmux kill-session -t "${TEST_SESSION}" 2>/dev/null || true

# =====================================================================
echo ""
echo "=== Test 4: orch-run.sh has tmux set-environment calls ==="
# =====================================================================

RUN_SH=$(cat "${REPO_ROOT}/scripts/orch-run.sh")

assert_contains "orch-run.sh: set-environment GH_SYNC" \
  "${RUN_SH}" 'tmux set-environment -t "${TMUX_SESSION}" GH_SYNC "${GH_SYNC}"'
assert_contains "orch-run.sh: set-environment REPO_ROOT" \
  "${RUN_SH}" 'tmux set-environment -t "${TMUX_SESSION}" REPO_ROOT "${REPO_ROOT}"'
assert_contains "orch-run.sh: set-environment SLUG" \
  "${RUN_SH}" 'tmux set-environment -t "${TMUX_SESSION}" SLUG "${SLUG}"'
assert_contains "orch-run.sh: set-environment ORCH_STATE_DIR" \
  "${RUN_SH}" 'tmux set-environment -t "${TMUX_SESSION}" ORCH_STATE_DIR "${ORCH_STATE_DIR}"'

# =====================================================================
echo ""
echo "=== Test 5: orch-run.sh engine command has inline GH_SYNC prefix ==="
# =====================================================================

assert_contains "orch-run.sh: engine window inline GH_SYNC" \
  "${RUN_SH}" "GH_SYNC='\${GH_SYNC}' bash"

# =====================================================================
echo ""
echo "=== Test 6: orch-engine.sh has diagnostic log line ==="
# =====================================================================

ENGINE_SH=$(cat "${REPO_ROOT}/scripts/orch-engine.sh")

assert_contains "orch-engine.sh: diagnostic log at startup" \
  "${ENGINE_SH}" 'echo "orch-engine: GH_SYNC=${GH_SYNC}"'

# =====================================================================
echo ""
echo "=== Test 7: orch-engine.sh defaults GH_SYNC to false ==="
# =====================================================================

assert_contains "orch-engine.sh: GH_SYNC default" \
  "${ENGINE_SH}" 'GH_SYNC="${GH_SYNC:-false}"'

# =====================================================================
echo ""
echo "=== Test 8: shellcheck passes on orch-run.sh and orch-engine.sh ==="
# =====================================================================

for script in scripts/orch-run.sh scripts/orch-engine.sh; do
  if shellcheck -e SC1091 -S warning "${REPO_ROOT}/${script}" 2>&1; then
    echo "  PASS: shellcheck ${script}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: shellcheck ${script}"
    FAIL=$((FAIL + 1))
  fi
done

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
