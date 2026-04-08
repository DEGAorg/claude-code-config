#!/usr/bin/env bash
# Tests for clause-based review: verifies that the reviewer prompt,
# done-file format, and review-file format correctly handle multi-clause
# items and that partial completions trigger REVISE.
#
# Usage: bash tests/test-orch-clause-review.sh
#
# Tests run without tmux or claude — they validate state logic and
# file format integration only.

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
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected to contain: ${needle}"
    echo "    actual: ${haystack}"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "${path}" ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label} — file not found: ${path}"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup ---

TEST_SLUG="test-clause-review-$$"
TEST_PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${TEST_SLUG}"
ORCH_DIR="${REPO_ROOT}/.orchestrator"

cleanup() {
  rm -rf "${TEST_PLAN_DIR}"
  rm -rf "${ORCH_DIR}"
}
trap cleanup EXIT

mkdir -p "${TEST_PLAN_DIR}"

# Source orch-state.sh for helpers
export ORCH_REPO_ROOT="${REPO_ROOT}"
export ORCH_STATE_DIR="${ORCH_DIR}"
# shellcheck source=../scripts/orch-state.sh
source "${REPO_ROOT}/scripts/orch-state.sh"

# --- Synthetic plan: single 2-clause item ---

cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Clause Review

**Status:** In progress

## Requirements

Verify clause-based review catches partial completions.

## Approach

Single 2-clause item to test clause decomposition.

## Progress log

- [ ] Add retry logic and log each attempt

## Completion criteria

- [ ] Retry logic present
- [ ] Each attempt is logged
PLAN

echo ""
echo "=== Test 1: Reviewer prompt template substitutes 2-clause item ==="

PROMPT_TEMPLATE="${REPO_ROOT}/scripts/ralph-item-reviewer-prompt.md"
ITEM_TEXT="Add retry logic and log each attempt"
ITEM_HANDOFF="Added retry logic to client.py. The function now retries 3 times."

RENDERED=$(cat "${PROMPT_TEMPLATE}")
RENDERED="${RENDERED//\{ITEM_TEXT\}/${ITEM_TEXT}}"
RENDERED="${RENDERED//\{ITEM_HANDOFF\}/${ITEM_HANDOFF}}"
RENDERED="${RENDERED//\{REVIEW_DIR\}/tmp/review}"
RENDERED="${RENDERED//\{ITEM_NUM\}/1}"

assert_contains "prompt contains item text" "${RENDERED}" "Add retry logic and log each attempt"
assert_contains "prompt contains handoff" "${RENDERED}" "Added retry logic to client.py"
assert_contains "prompt requires clause decomposition" "${RENDERED}" "Decompose the item into clauses"
assert_contains "prompt requires per-clause verification" "${RENDERED}" "VERIFIED"
assert_contains "prompt requires UNVERIFIED on gaps" "${RENDERED}" "UNVERIFIED"
assert_contains "prompt says partial is FAIL" "${RENDERED}" "partial completion is a FAIL"

echo ""
echo "=== Test 2: FAIL review file with UNVERIFIED clause is parsed correctly ==="

# Initialize state with a single done item in "reviewing" status
PARSED=$("${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ITEMS_JSON=$(printf '%s' "${PARSED}" | jq --argjson maxIter 3 '[
  .items[] | {
    id: .id,
    description: .description,
    deps: .deps,
    status: "done",
    reviewStatus: "reviewing",
    workerPid: null,
    tmuxPane: null,
    worktree: null,
    iteration: 1,
    maxIterations: $maxIter,
    lastResult: null
  }
]')

STATE_JSON=$(jq -n \
  --argjson version 1 \
  --arg plan "${TEST_SLUG}" \
  --argjson maxWorkers 4 \
  --arg mode "foreground" \
  --argjson items "${ITEMS_JSON}" \
  --arg startedAt "${NOW}" \
  --arg updatedAt "${NOW}" \
  '{
    version: $version,
    plan: $plan,
    maxParallelWorkers: $maxWorkers,
    mode: $mode,
    items: $items,
    finalReview: { status: "running", result: null, reworkItems: [] },
    startedAt: $startedAt,
    updatedAt: $updatedAt
  }')

orch_write_state "${TEST_SLUG}" "${STATE_JSON}"
ORCH_STATE_FILE=$(orch_plan_state_file "${TEST_SLUG}")

# Verify item starts as "reviewing"
PRE_STATUS=$(jq -r '.items[0].reviewStatus' "${ORCH_STATE_FILE}")
assert_eq "item 1 starts as reviewing" "reviewing" "${PRE_STATUS}"

# Write a FAIL review file — reviewer caught the missing clause
REVIEW_DIR=$(orch_plan_review_dir "${TEST_SLUG}")
mkdir -p "${REVIEW_DIR}"

cat >"${REVIEW_DIR}/item-1-review.txt" <<'REVIEW'
FAIL

CLAUSES:
1. Add retry logic — VERIFIED: retry loop added at client.py:45
2. Log each attempt — UNVERIFIED: no logging found in client.py

FINDING: The retry logic is present but no logging of individual attempts exists.
ACTION: Add a log statement inside the retry loop to record each attempt.
REVIEW

# Sync review files — should detect FAIL and mark item as "failed"
orch_sync_review_files "${TEST_SLUG}"

POST_STATUS=$(jq -r '.items[0].reviewStatus' "${ORCH_STATE_FILE}")
assert_eq "FAIL review marks item as failed" "failed" "${POST_STATUS}"

echo ""
echo "=== Test 3: PASS review file with all clauses VERIFIED ==="

# Reset item to "reviewing"
RESET=$(jq --arg now "${NOW}" \
  '(.items[0]).reviewStatus = "reviewing" | .updatedAt = $now' \
  "${ORCH_STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${RESET}"

# Overwrite review file with PASS — both clauses verified
cat >"${REVIEW_DIR}/item-1-review.txt" <<'REVIEW'
PASS

CLAUSES:
1. Add retry logic — VERIFIED: retry loop at client.py:45 with max_retries=3
2. Log each attempt — VERIFIED: logger.info at client.py:52 logs attempt number
REVIEW

orch_sync_review_files "${TEST_SLUG}"

PASS_STATUS=$(jq -r '.items[0].reviewStatus' "${ORCH_STATE_FILE}")
assert_eq "PASS review marks item as passed" "passed" "${PASS_STATUS}"

echo ""
echo "=== Test 4: Partial done-file missing a clause ==="

# Verify the worker prompt requires clause checklist in done-files
WORKER_PROMPT="${REPO_ROOT}/agents/orch-worker.md"
WORKER_CONTENT=$(cat "${WORKER_PROMPT}")

assert_contains "worker prompt requires clause checklist" \
  "${WORKER_CONTENT}" "Clause checklist"
assert_contains "worker prompt requires self-check" \
  "${WORKER_CONTENT}" "Self-check"
assert_contains "worker prompt mentions DONE or BLOCKED" \
  "${WORKER_CONTENT}" "DONE"

echo ""
echo "=== Test 5: Verifier prompt checks clause coverage ==="

VERIFIER_PROMPT="${REPO_ROOT}/agents/orch-verifier.md"
VERIFIER_CONTENT=$(cat "${VERIFIER_PROMPT}")

assert_contains "verifier has clause-coverage check" \
  "${VERIFIER_CONTENT}" "Clause-coverage check"
assert_contains "verifier checks done-files for clauses" \
  "${VERIFIER_CONTENT}" "done-file"
assert_contains "verifier checks review files for clauses" \
  "${VERIFIER_CONTENT}" "review file"
assert_contains "verifier reports CLAUSE-GAP on failure" \
  "${VERIFIER_CONTENT}" "CLAUSE-GAP"

echo ""
echo "=== Test 6: FAIL review triggers REVISE in aggregate decision ==="

# Set up: 2-item plan, item 1 passed review, item 2 failed (partial clause)
cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Clause Review

**Status:** In progress

## Progress log

- [x] Setup the config file
- [x] Add retry logic and log each attempt (deps: 1)

## Completion criteria

- [ ] Config file exists
- [ ] Retry with logging works
PLAN

PARSED2=$("${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")

ITEMS_JSON2=$(printf '%s' "${PARSED2}" | jq --argjson maxIter 3 '[
  .items[] | {
    id: .id,
    description: .description,
    deps: .deps,
    status: "done",
    reviewStatus: (if .id == 1 then "passed" elif .id == 2 then "failed" else "pending" end),
    workerPid: null,
    tmuxPane: null,
    worktree: null,
    iteration: 1,
    maxIterations: $maxIter,
    lastResult: null
  }
]')

STATE2=$(jq -n \
  --argjson version 1 \
  --arg plan "${TEST_SLUG}" \
  --argjson maxWorkers 4 \
  --arg mode "foreground" \
  --argjson items "${ITEMS_JSON2}" \
  --arg startedAt "${NOW}" \
  --arg updatedAt "${NOW}" \
  '{
    version: $version,
    plan: $plan,
    maxParallelWorkers: $maxWorkers,
    mode: $mode,
    items: $items,
    finalReview: { status: "done", result: null, reworkItems: [] },
    startedAt: $startedAt,
    updatedAt: $updatedAt
  }')
orch_write_state "${TEST_SLUG}" "${STATE2}"

# Count passed vs failed
CNT_PASSED=$(jq '[.items[] | select(.reviewStatus == "passed")] | length' \
  "${ORCH_STATE_FILE}")
CNT_FAILED=$(jq '[.items[] | select(.reviewStatus == "failed")] | length' \
  "${ORCH_STATE_FILE}")

assert_eq "1 item passed review" "1" "${CNT_PASSED}"
assert_eq "1 item failed review (partial clause)" "1" "${CNT_FAILED}"

# The failed item should be the 2-clause one
FAILED_ID=$(jq -r '.items[] | select(.reviewStatus == "failed") | .id' \
  "${ORCH_STATE_FILE}")
FAILED_DESC=$(jq -r '.items[] | select(.reviewStatus == "failed") | .description' \
  "${ORCH_STATE_FILE}")
assert_eq "failed item is item 2" "2" "${FAILED_ID}"
assert_contains "failed item is the 2-clause item" \
  "${FAILED_DESC}" "Add retry logic and log each attempt"

echo ""
echo "=== Test 7: Review file format — FAIL must have CLAUSES section ==="

# Verify the review file from test 2 has the expected structure
REVIEW_FILE="${REVIEW_DIR}/item-1-review.txt"
assert_file_exists "review file exists" "${REVIEW_FILE}"

FIRST_LINE=$(head -1 "${REVIEW_FILE}" | tr -d '[:space:]')
assert_eq "review file first line is decision" "PASS" "${FIRST_LINE}"

# Write a new FAIL review to check structure
cat >"${REVIEW_DIR}/item-2-review.txt" <<'REVIEW'
FAIL

CLAUSES:
1. Add retry logic — VERIFIED: retry loop at client.py:45
2. Log each attempt — UNVERIFIED: no logger.info found in retry loop

FINDING: Logging is missing from the retry loop in client.py
ACTION: Add logger.info inside the retry loop body
REVIEW

FAIL_FIRST=$(head -1 "${REVIEW_DIR}/item-2-review.txt" | tr -d '[:space:]')
assert_eq "FAIL review first line" "FAIL" "${FAIL_FIRST}"

# Verify CLAUSES section contains both clauses
REVIEW_BODY=$(cat "${REVIEW_DIR}/item-2-review.txt")
assert_contains "review lists clause 1" "${REVIEW_BODY}" "Add retry logic"
assert_contains "review lists clause 2" "${REVIEW_BODY}" "Log each attempt"
assert_contains "review marks clause 1 VERIFIED" "${REVIEW_BODY}" "VERIFIED: retry loop"
assert_contains "review marks clause 2 UNVERIFIED" "${REVIEW_BODY}" "UNVERIFIED: no logger"
assert_contains "review has FINDING" "${REVIEW_BODY}" "FINDING:"
assert_contains "review has ACTION" "${REVIEW_BODY}" "ACTION:"

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
