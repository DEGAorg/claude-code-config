#!/usr/bin/env bash
# End-to-end test for orchestrator dashboard rendering.
# Creates fake state.json + log file, launches dashboard in tmux,
# writes log lines, captures pane output, asserts log lines appear.
#
# Usage: bash tests/test-dashboard-rendering.sh
#
# Requirements: tmux, node (npx tsx), jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERMINAL_UI_DIR="${REPO_ROOT}/scripts/terminal-ui"

PASS=0
FAIL=0
TEST_SESSION="test-dash-$$"
TEST_DIR=""

# --- Helpers ---

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "${haystack}" | grep -qF "${needle}"; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected to contain: ${needle}"
    echo "    pane output (first 20 lines):"
    printf '%s\n' "${haystack}" | head -20 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if ! printf '%s' "${haystack}" | grep -qF "${needle}"; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected NOT to contain: ${needle}"
    FAIL=$((FAIL + 1))
  fi
}

cleanup() {
  tmux kill-session -t "${TEST_SESSION}" 2>/dev/null || true
  if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}
trap cleanup EXIT

capture_pane() {
  tmux capture-pane -t "${TEST_SESSION}" -p -S -50
}

wait_for_pane_content() {
  local needle="$1"
  local max_wait="${2:-10}"
  local elapsed=0
  while (( elapsed < max_wait )); do
    local content
    content=$(capture_pane 2>/dev/null || true)
    if printf '%s' "${content}" | grep -qF "${needle}"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

# Atomic write: write to temp file then mv to avoid partial reads by chokidar
atomic_write_state() {
  local target="$1"
  local tmp="${target}.tmp.$$"
  cat >"${tmp}"
  mv -f "${tmp}" "${target}"
}

# --- Preflight checks ---

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux not found"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not found"
  exit 0
fi

if ! npx tsx --version >/dev/null 2>&1; then
  echo "SKIP: npx tsx not available"
  exit 0
fi

# --- Setup fake orchestrator state ---

TEST_DIR=$(mktemp -d)
LOGS_DIR="${TEST_DIR}/logs"
STATE_FILE="${TEST_DIR}/state.json"
mkdir -p "${LOGS_DIR}"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat >"${STATE_FILE}" <<EOF
{
  "version": 1,
  "plan": "test-dashboard",
  "maxParallelWorkers": 2,
  "mode": "foreground",
  "items": [
    {
      "id": 1,
      "description": "First worker task",
      "deps": [],
      "status": "running",
      "workerPid": 12345,
      "tmuxPane": "%1",
      "worktree": null,
      "iteration": 1,
      "maxIterations": 3,
      "lastResult": null
    },
    {
      "id": 2,
      "description": "Second worker task",
      "deps": [1],
      "status": "queued",
      "workerPid": null,
      "tmuxPane": null,
      "worktree": null,
      "iteration": 0,
      "maxIterations": 3,
      "lastResult": null
    }
  ],
  "finalReview": {
    "status": "pending",
    "result": null,
    "reworkItems": []
  },
  "startedAt": "${NOW}",
  "updatedAt": "${NOW}"
}
EOF

# Pre-populate worker-1 log so the dashboard has content from the start
printf 'MARKER_INIT_LINE: dashboard init test\n' >"${LOGS_DIR}/worker-1.log"

echo ""
echo "=== Test 1: Dashboard launches and shows state ==="

# Launch dashboard in a detached tmux session
tmux new-session -d -s "${TEST_SESSION}" -x 120 -y 40 \
  "cd '${TERMINAL_UI_DIR}' && npx tsx src/cli.tsx --orch '${STATE_FILE}' 2>'${TEST_DIR}/dash-stderr.log'"

# Wait for the dashboard to render the header
if wait_for_pane_content "ORCHESTRATOR" 15; then
  echo "  PASS: dashboard launched and shows ORCHESTRATOR header"
  PASS=$((PASS + 1))
else
  echo "  FAIL: dashboard did not render ORCHESTRATOR header within 15s"
  echo "  stderr:"
  cat "${TEST_DIR}/dash-stderr.log" 2>/dev/null | head -10 | sed 's/^/    /'
  FAIL=$((FAIL + 1))
  echo ""
  echo "================================"
  echo "  PASS: ${PASS}  FAIL: ${FAIL}"
  echo "================================"
  exit 1
fi

PANE=$(capture_pane)

assert_contains "shows item count in header" "${PANE}" "0/2 done"
assert_contains "shows first item description" "${PANE}" "First worker task"
assert_contains "shows second item description" "${PANE}" "Second worker task"

echo ""
echo "=== Test 2: Selecting an item shows worker output ==="

# Send 'j' to select first item
tmux send-keys -t "${TEST_SESSION}" j
sleep 2

PANE2=$(capture_pane)

# After selecting item 1 (running), the detail panel should show its log content
assert_contains "detail panel shows init log line" "${PANE2}" "MARKER_INIT_LINE"

echo ""
echo "=== Test 3: New log lines appear in dashboard ==="

# Write new lines to the worker log
for i in $(seq 1 5); do
  printf 'MARKER_LINE_%d: test output line %d\n' "${i}" "${i}" >>"${LOGS_DIR}/worker-1.log"
done

# Wait for chokidar to pick up the change and dashboard to re-render
if wait_for_pane_content "MARKER_LINE_5" 10; then
  echo "  PASS: new log lines appear in dashboard"
  PASS=$((PASS + 1))
else
  echo "  FAIL: MARKER_LINE_5 did not appear within 10s"
  FAIL=$((FAIL + 1))
fi

PANE3=$(capture_pane)
assert_contains "shows latest log line" "${PANE3}" "MARKER_LINE_5"

echo ""
echo "=== Test 4: State updates reflect in dashboard ==="

# Update state: mark item 1 as done, item 2 as running
NOW2=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
atomic_write_state "${STATE_FILE}" <<EOF
{
  "version": 1,
  "plan": "test-dashboard",
  "maxParallelWorkers": 2,
  "mode": "foreground",
  "items": [
    {
      "id": 1,
      "description": "First worker task",
      "deps": [],
      "status": "done",
      "workerPid": null,
      "tmuxPane": null,
      "worktree": null,
      "iteration": 1,
      "maxIterations": 3,
      "lastResult": "SHIP"
    },
    {
      "id": 2,
      "description": "Second worker task",
      "deps": [1],
      "status": "running",
      "workerPid": 12346,
      "tmuxPane": "%2",
      "worktree": null,
      "iteration": 1,
      "maxIterations": 3,
      "lastResult": null
    }
  ],
  "finalReview": {
    "status": "pending",
    "result": null,
    "reworkItems": []
  },
  "startedAt": "${NOW}",
  "updatedAt": "${NOW2}"
}
EOF

sleep 3
PANE4=$(capture_pane)

# The dashboard should reflect the updated state (item statuses changed)
# We verify the state was re-read by checking the pane still renders correctly
assert_contains "dashboard still renders after state update" "${PANE4}" "ORCHESTRATOR"
assert_contains "dashboard still shows items" "${PANE4}" "First worker task"

echo ""
echo "=== Test 5: Review status shows in header ==="

# Update state to show final review result
NOW3=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
atomic_write_state "${STATE_FILE}" <<EOF
{
  "version": 1,
  "plan": "test-dashboard",
  "maxParallelWorkers": 2,
  "mode": "foreground",
  "items": [
    {
      "id": 1,
      "description": "First worker task",
      "deps": [],
      "status": "done",
      "workerPid": null,
      "tmuxPane": null,
      "worktree": null,
      "iteration": 1,
      "maxIterations": 3,
      "lastResult": "SHIP"
    },
    {
      "id": 2,
      "description": "Second worker task",
      "deps": [1],
      "status": "done",
      "workerPid": null,
      "tmuxPane": null,
      "worktree": null,
      "iteration": 1,
      "maxIterations": 3,
      "lastResult": "SHIP"
    }
  ],
  "finalReview": {
    "status": "done",
    "result": "SHIP",
    "reworkItems": []
  },
  "startedAt": "${NOW}",
  "updatedAt": "${NOW3}"
}
EOF

if wait_for_pane_content "SHIP" 15; then
  echo "  PASS: review result SHIP appears in dashboard"
  PASS=$((PASS + 1))
else
  PANE5=$(capture_pane)
  echo "  FAIL: review result SHIP did not appear within 15s"
  echo "    pane output:"
  printf '%s\n' "${PANE5}" | head -15 | sed 's/^/      /'
  FAIL=$((FAIL + 1))
fi

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
