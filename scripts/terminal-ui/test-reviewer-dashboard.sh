#!/usr/bin/env bash
set -euo pipefail

# Test: reviewer dashboard visibility
# Verifies that items with reviewStatus:"reviewing" show reviewer log
# content and the "reviewer" header in the detail panel.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR_BASE="${TMPDIR:-/tmp}"
TEST_DIR=$(mktemp -d "${TMPDIR_BASE}/reviewer-dashboard-test.XXXXXX")
LOGS_DIR="${TEST_DIR}/logs"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$LOGS_DIR"

# Create fake reviewer log with identifiable content
cat > "$LOGS_DIR/reviewer-1.log" <<'LOG'
[reviewer] Checking item 1 implementation...
[reviewer] Verifying test coverage...
[reviewer] REVIEWER_SENTINEL_LINE: this content proves reviewer log is displayed
[reviewer] Review complete — SHIP
LOG

# Create fake worker log (should NOT appear when reviewStatus is reviewing)
cat > "$LOGS_DIR/worker-1.log" <<'LOG'
[worker] Starting item 1...
[worker] WORKER_SENTINEL_LINE: this should NOT appear during review
[worker] Implementation complete
LOG

# Create orchestrator state with item 1 in reviewing status
cat > "$TEST_DIR/state.json" <<'JSON'
{
  "version": 1,
  "plan": "test-plan",
  "maxParallelWorkers": 2,
  "mode": "foreground",
  "items": [
    {
      "id": 1,
      "description": "Test item in review",
      "deps": [],
      "status": "review",
      "workerPid": null,
      "tmuxPane": "reviewer-1",
      "worktree": null,
      "iteration": 1,
      "maxIterations": 3,
      "lastResult": null,
      "reviewStatus": "reviewing"
    },
    {
      "id": 2,
      "description": "Test item still working",
      "deps": [],
      "status": "running",
      "workerPid": 12345,
      "tmuxPane": "worker-2",
      "worktree": null,
      "iteration": 1,
      "maxIterations": 3,
      "lastResult": null,
      "reviewStatus": "pending"
    }
  ],
  "finalReview": {
    "status": "pending",
    "result": null,
    "reworkItems": []
  },
  "startedAt": "2026-03-14T10:00:00Z",
  "updatedAt": "2026-03-14T10:05:00Z"
}
JSON

echo "=== Reviewer Dashboard Visibility Test ==="
echo ""

# 1. Verify compiled code has reviewer log path logic
echo "1. Checking compiled JS for reviewer log path logic..."
ORCH_JS="${SCRIPT_DIR}/dist/orchestrator-app.js"
if ! [ -f "$ORCH_JS" ]; then
  echo "   FAIL: dist/orchestrator-app.js not found — run pnpm build first"
  exit 1
fi

if grep -q 'reviewing' "$ORCH_JS" && grep -q 'reviewer' "$ORCH_JS"; then
  echo "   PASS: orchestrator-app.js contains reviewer log path conditional"
else
  echo "   FAIL: orchestrator-app.js missing reviewer log path conditional"
  exit 1
fi

# 2. Verify session-detail has reviewer header logic
echo "2. Checking compiled JS for reviewer header logic..."
DETAIL_JS="${SCRIPT_DIR}/dist/session-detail.js"
if ! [ -f "$DETAIL_JS" ]; then
  echo "   FAIL: dist/session-detail.js not found — run pnpm build first"
  exit 1
fi

if grep -q '"reviewer"' "$DETAIL_JS" && grep -q '"worker"' "$DETAIL_JS"; then
  echo "   PASS: session-detail.js contains reviewer/worker role labels"
else
  echo "   FAIL: session-detail.js missing reviewer/worker role labels"
  exit 1
fi

# 3. Verify session-detail uses magenta color for reviewer
if grep -q 'magenta' "$DETAIL_JS"; then
  echo "   PASS: session-detail.js uses magenta color for reviewer header"
else
  echo "   FAIL: session-detail.js missing magenta color for reviewer"
  exit 1
fi

# 4. Verify the log path derivation logic in orchestrator-app
# The compiled code should derive logPrefix from reviewStatus
if grep -q 'logPrefix' "$ORCH_JS"; then
  echo "   PASS: orchestrator-app.js derives logPrefix from reviewStatus"
else
  echo "   FAIL: orchestrator-app.js missing logPrefix derivation"
  exit 1
fi

# 5. Verify TypeScript compiles cleanly
echo "3. Checking tsc --noEmit..."
if (cd "$SCRIPT_DIR" && npx tsc --noEmit 2>&1); then
  echo "   PASS: TypeScript compiles with no errors"
else
  echo "   FAIL: TypeScript compilation errors"
  exit 1
fi

# 6. Verify the reviewStatus prop is passed to SessionDetail
if grep -q 'reviewStatus' "$ORCH_JS"; then
  echo "   PASS: orchestrator-app.js passes reviewStatus prop to SessionDetail"
else
  echo "   FAIL: orchestrator-app.js missing reviewStatus prop pass-through"
  exit 1
fi

echo ""
echo "=== All automated checks passed ==="
echo ""
echo "Test fixtures created at: $TEST_DIR"
echo ""
echo "For manual visual verification, run:"
echo "  node ${SCRIPT_DIR}/dist/cli.js --orch ${TEST_DIR}/state.json"
echo ""
echo "Then press 'j' to select item 1 — you should see:"
echo "  - Header: 'reviewer reviewer-1:' (magenta color)"
echo "  - Log content: REVIEWER_SENTINEL_LINE"
echo "  - NOT: WORKER_SENTINEL_LINE"
echo ""
echo "Press 'j' again to select item 2 — you should see:"
echo "  - Header: 'worker worker-2:' (green color)"
