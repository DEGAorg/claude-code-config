#!/usr/bin/env bash
# Tests for orchestrator stale worker detection.
# Requires tmux to be installed (creates ephemeral sessions).
#
# Usage: bash tests/test-orch-stale-detection.sh
#
# Tests:
#   1. Live worker pane is NOT marked stale
#   2. Dead worker pane is detected and item reset to "ready"
#   3. Iteration counter increments on each stale detection
#   4. Kill worker 3 times — item marked "failed" after maxIterations

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

# --- Preflight: tmux must be available ---

if ! command -v tmux &>/dev/null; then
  echo "SKIP: tmux not installed"
  exit 0
fi

# --- Setup ---

TEST_SLUG="test-stale-$$"
TMUX_SESSION="orch-${TEST_SLUG}"
ORCH_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_DIR}/state.json"

cleanup() {
  tmux kill-session -t "${TMUX_SESSION}" 2>/dev/null || true
  rm -rf "${ORCH_DIR}"
}
trap cleanup EXIT

mkdir -p "${ORCH_DIR}/done/${TEST_SLUG}"

# Source the library under test
ORCH_REPO_ROOT="${REPO_ROOT}"
ORCH_STATE_DIR="${ORCH_DIR}"
export ORCH_REPO_ROOT ORCH_STATE_DIR ORCH_STATE_FILE
# shellcheck source=../scripts/orch-state.sh
source "${REPO_ROOT}/scripts/orch-state.sh"

# --- Helper: write state with N items, all "running" ---

write_running_state() {
  local item_count="$1"
  local max_iter="${2:-3}"
  local items="[]"
  for ((i = 1; i <= item_count; i++)); do
    items=$(printf '%s' "${items}" | jq \
      --argjson id "${i}" \
      --argjson maxIter "${max_iter}" \
      '. + [{
				id: $id,
				description: ("item-" + ($id | tostring)),
				deps: [],
				status: "running",
				workerPid: null,
				tmuxPane: null,
				worktree: null,
				iteration: 0,
				maxIterations: $maxIter,
				lastResult: null
			}]')
  done

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local state
  state=$(jq -n \
    --argjson version 1 \
    --arg plan "${TEST_SLUG}" \
    --argjson maxWorkers 4 \
    --arg mode "foreground" \
    --argjson items "${items}" \
    --arg startedAt "${now}" \
    --arg updatedAt "${now}" \
    '{
			version: $version,
			plan: $plan,
			maxParallelWorkers: $maxWorkers,
			mode: $mode,
			items: $items,
			finalReview: { status: "pending", result: null, reworkItems: [] },
			startedAt: $startedAt,
			updatedAt: $updatedAt
		}')
  orch_write_state "${state}"
}

# --- Create tmux session ---

tmux new-session -d -s "${TMUX_SESSION}" -n "dashboard" "sleep 300"

echo ""
echo "=== Test 1: Live worker pane is NOT marked stale ==="

write_running_state 1

# Create a live worker-1 window
tmux new-window -t "${TMUX_SESSION}" -n "worker-1" "sleep 300"
sleep 0.5

orch_detect_stale_workers "${TEST_SLUG}"

S1=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
assert_eq "live pane: item 1 still running" "running" "${S1}"

# Clean up the window
tmux kill-window -t "${TMUX_SESSION}:worker-1" 2>/dev/null || true
sleep 0.5

echo ""
echo "=== Test 2: Dead/missing pane detected — item reset to ready ==="

write_running_state 1

# No worker-1 window exists — pane is "missing"
orch_detect_stale_workers "${TEST_SLUG}"

S2=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
I2=$(jq '.items[] | select(.id == 1) | .iteration' "${ORCH_STATE_FILE}")
LR2=$(jq -r '.items[] | select(.id == 1) | .lastResult' "${ORCH_STATE_FILE}")
assert_eq "missing pane: item 1 reset to ready" "ready" "${S2}"
assert_eq "missing pane: iteration incremented to 1" "1" "${I2}"
assert_eq "missing pane: lastResult is stale-retry" "stale-retry" "${LR2}"

echo ""
echo "=== Test 3: Iteration increments on repeated stale detection ==="

# Item is now "ready" with iteration=1. Set it back to "running" to
# simulate the orchestrator re-spawning it, then detect stale again.
orch_update_item_status 1 "running"

orch_detect_stale_workers "${TEST_SLUG}"

S3=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
I3=$(jq '.items[] | select(.id == 1) | .iteration' "${ORCH_STATE_FILE}")
assert_eq "second stale: item 1 reset to ready" "ready" "${S3}"
assert_eq "second stale: iteration incremented to 2" "2" "${I3}"

echo ""
echo "=== Test 4: Kill worker 3 times — item marked failed after maxIterations ==="

# Fresh state: iteration=0, maxIterations=3, status=running
write_running_state 1 3

# Kill 1: iteration 0→1, status → ready
orch_detect_stale_workers "${TEST_SLUG}"
S4a=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
I4a=$(jq '.items[] | select(.id == 1) | .iteration' "${ORCH_STATE_FILE}")
assert_eq "kill 1/3: item reset to ready" "ready" "${S4a}"
assert_eq "kill 1/3: iteration is 1" "1" "${I4a}"

# Re-spawn: set back to running
orch_update_item_status 1 "running"

# Kill 2: iteration 1→2, status → ready
orch_detect_stale_workers "${TEST_SLUG}"
S4b=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
I4b=$(jq '.items[] | select(.id == 1) | .iteration' "${ORCH_STATE_FILE}")
assert_eq "kill 2/3: item reset to ready" "ready" "${S4b}"
assert_eq "kill 2/3: iteration is 2" "2" "${I4b}"

# Re-spawn: set back to running
orch_update_item_status 1 "running"

# Kill 3: iteration 2→3 >= maxIterations(3), status → failed
orch_detect_stale_workers "${TEST_SLUG}"
S4c=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
LR4c=$(jq -r '.items[] | select(.id == 1) | .lastResult' "${ORCH_STATE_FILE}")
assert_eq "kill 3/3: item marked failed" "failed" "${S4c}"
assert_eq "kill 3/3: lastResult is stale-max-retries" "stale-max-retries" "${LR4c}"

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
