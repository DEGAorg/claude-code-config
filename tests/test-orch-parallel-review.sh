#!/usr/bin/env bash
# Tests for parallel review: sync_review_files, concurrency limits, aggregation.
# Validates state logic without tmux or claude — same pattern as test-orch-e2e.sh.
#
# Usage: bash tests/test-orch-parallel-review.sh

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

# --- Setup ---

TEST_SLUG="test-review-$$"
TEST_PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${TEST_SLUG}"

cleanup() {
  rm -rf "${TEST_PLAN_DIR}"
  rm -rf "${REPO_ROOT}/.orchestrator/plans/${TEST_SLUG}"
}
trap cleanup EXIT

mkdir -p "${TEST_PLAN_DIR}"

# Synthetic plan: 4 items, all independent (no deps)
cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Parallel Review

**Status:** In progress

## Progress log

- [x] Task alpha (deps: )
- [x] Task beta (deps: )
- [x] Task gamma (deps: )
- [x] Task delta (deps: )
PLAN

# Source orch-state.sh
export ORCH_REPO_ROOT="${REPO_ROOT}"
export ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
# shellcheck source=../scripts/orch-state.sh
source "${REPO_ROOT}/scripts/orch-state.sh"

# Build state with all items done, reviewStatus pending, maxParallelWorkers=2
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

build_state() {
  local max_workers="$1"
  jq -n \
    --argjson maxWorkers "${max_workers}" \
    --arg slug "${TEST_SLUG}" \
    --arg now "${NOW}" \
    '{
		version: 1,
		plan: $slug,
		maxParallelWorkers: $maxWorkers,
		mode: "foreground",
		items: [
			{id:1, description:"Task alpha", deps:[], status:"done", reviewStatus:"pending", iteration:1, maxIterations:3, lastResult:"SHIP"},
			{id:2, description:"Task beta",  deps:[], status:"done", reviewStatus:"pending", iteration:1, maxIterations:3, lastResult:"SHIP"},
			{id:3, description:"Task gamma", deps:[], status:"done", reviewStatus:"pending", iteration:1, maxIterations:3, lastResult:"SHIP"},
			{id:4, description:"Task delta", deps:[], status:"done", reviewStatus:"pending", iteration:1, maxIterations:3, lastResult:"SHIP"}
		],
		finalReview: { status: "pending", result: null, reworkItems: [] },
		startedAt: $now,
		updatedAt: $now
	}'
}

orch_ensure_plan_dirs "${TEST_SLUG}"

# ===================================================================
echo ""
echo "=== Test 1: orch_sync_review_files — PASS reviews ==="

STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

STATE_FILE=$(orch_plan_state_file "${TEST_SLUG}")
REVIEW_DIR=$(orch_plan_review_dir "${TEST_SLUG}")

# Mark items 1 and 2 as "reviewing" (simulates spawn_reviewer)
UPDATED=$(jq '
	(.items[] | select(.id == 1)).reviewStatus = "reviewing" |
	(.items[] | select(.id == 2)).reviewStatus = "reviewing"
' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

# Write review files for items 1 and 2
printf 'PASS\nCode looks good.\n' >"${REVIEW_DIR}/item-1-review.txt"
printf 'PASS\nNo issues found.\n' >"${REVIEW_DIR}/item-2-review.txt"

# Sync should detect reviews and mark passed
orch_sync_review_files "${TEST_SLUG}"

RS1=$(jq -r '.items[] | select(.id == 1) | .reviewStatus' "${STATE_FILE}")
RS2=$(jq -r '.items[] | select(.id == 2) | .reviewStatus' "${STATE_FILE}")
RS3=$(jq -r '.items[] | select(.id == 3) | .reviewStatus' "${STATE_FILE}")
assert_eq "item 1 review passed" "passed" "${RS1}"
assert_eq "item 2 review passed" "passed" "${RS2}"
assert_eq "item 3 still pending" "pending" "${RS3}"

# ===================================================================
echo ""
echo "=== Test 2: orch_sync_review_files — FAIL reviews ==="

# Mark items 3 and 4 as reviewing
UPDATED=$(jq '
	(.items[] | select(.id == 3)).reviewStatus = "reviewing" |
	(.items[] | select(.id == 4)).reviewStatus = "reviewing"
' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

# Item 3 passes, item 4 fails
printf 'PASS\nLooks good.\n' >"${REVIEW_DIR}/item-3-review.txt"
printf 'FAIL\nMissing error handling in edge case.\n' >"${REVIEW_DIR}/item-4-review.txt"

orch_sync_review_files "${TEST_SLUG}"

RS3=$(jq -r '.items[] | select(.id == 3) | .reviewStatus' "${STATE_FILE}")
RS4=$(jq -r '.items[] | select(.id == 4) | .reviewStatus' "${STATE_FILE}")
assert_eq "item 3 review passed" "passed" "${RS3}"
assert_eq "item 4 review failed" "failed" "${RS4}"

# ===================================================================
echo ""
echo "=== Test 3: orch_sync_review_files — unexpected decision marks failed ==="

STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

# Mark item 1 as reviewing
UPDATED=$(jq '(.items[] | select(.id == 1)).reviewStatus = "reviewing"' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

# Write garbage decision
printf 'MAYBE\nNot sure about this.\n' >"${REVIEW_DIR}/item-1-review.txt"

orch_sync_review_files "${TEST_SLUG}"

RS1=$(jq -r '.items[] | select(.id == 1) | .reviewStatus' "${STATE_FILE}")
assert_eq "unexpected decision marks failed" "failed" "${RS1}"

# ===================================================================
echo ""
echo "=== Test 4: orch_sync_review_files — no review file, stays reviewing ==="

STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

UPDATED=$(jq '(.items[] | select(.id == 2)).reviewStatus = "reviewing"' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

# Do NOT write a review file — just sync
rm -f "${REVIEW_DIR}/item-2-review.txt"
orch_sync_review_files "${TEST_SLUG}"

RS2=$(jq -r '.items[] | select(.id == 2) | .reviewStatus' "${STATE_FILE}")
assert_eq "no review file — stays reviewing" "reviewing" "${RS2}"

# ===================================================================
echo ""
echo "=== Test 5: Concurrency — available_slots calculation ==="

# Test the concurrency logic from orch-review.sh poll loop:
#   available_slots = max_workers - cnt_reviewing
#   spawn up to available_slots pending items
#
# Simulate: max_workers=2, 1 reviewing, 3 pending → should spawn 1 more

STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

UPDATED=$(jq '(.items[] | select(.id == 1)).reviewStatus = "reviewing"' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

MAX_WORKERS=$(jq '.maxParallelWorkers' "${STATE_FILE}")
cnt_reviewing=$(jq '[.items[] | select(.reviewStatus == "reviewing")] | length' "${STATE_FILE}")
cnt_pending=$(jq '[.items[] | select(.reviewStatus == "pending")] | length' "${STATE_FILE}")

available_slots=$((MAX_WORKERS - cnt_reviewing))
assert_eq "max_workers" "2" "${MAX_WORKERS}"
assert_eq "reviewing count" "1" "${cnt_reviewing}"
assert_eq "pending count" "3" "${cnt_pending}"
assert_eq "available slots (2-1)" "1" "${available_slots}"

# With 0 reviewing, should have 2 slots
STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

cnt_reviewing=$(jq '[.items[] | select(.reviewStatus == "reviewing")] | length' "${STATE_FILE}")
available_slots=$((MAX_WORKERS - cnt_reviewing))
assert_eq "available slots (2-0)" "2" "${available_slots}"

# With max_workers=4, all 4 pending should be spawnable
STATE=$(build_state 4)
orch_write_state "${TEST_SLUG}" "${STATE}"

MAX_WORKERS=$(jq '.maxParallelWorkers' "${STATE_FILE}")
cnt_reviewing=$(jq '[.items[] | select(.reviewStatus == "reviewing")] | length' "${STATE_FILE}")
cnt_pending=$(jq '[.items[] | select(.reviewStatus == "pending")] | length' "${STATE_FILE}")
available_slots=$((MAX_WORKERS - cnt_reviewing))
assert_eq "max_workers=4, all 4 pending spawnable" "4" "${available_slots}"

# ===================================================================
echo ""
echo "=== Test 6: Aggregation — all PASS yields SHIP ==="

STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

# Mark all items as passed
UPDATED=$(jq '
	(.items[] | select(.id == 1)).reviewStatus = "passed" |
	(.items[] | select(.id == 2)).reviewStatus = "passed" |
	(.items[] | select(.id == 3)).reviewStatus = "passed" |
	(.items[] | select(.id == 4)).reviewStatus = "passed"
' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

# Simulate aggregation logic from orch-review.sh
FAILED_IDS=$(jq -r '.items[] | select(.reviewStatus == "failed") | .id' "${STATE_FILE}")
FAILED_ITEMS=()
for fid in ${FAILED_IDS}; do
  FAILED_ITEMS+=("${fid}")
done

assert_eq "all passed — no failed items" "0" "${#FAILED_ITEMS[@]}"

# Write SHIP result
AGG_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq --arg now "${AGG_NOW}" \
  '.finalReview.status = "done" |
	 .finalReview.result = "SHIP" |
	 .finalReview.reworkItems = [] |
	 .updatedAt = $now' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

RESULT=$(jq -r '.finalReview.result' "${STATE_FILE}")
FR_STATUS=$(jq -r '.finalReview.status' "${STATE_FILE}")
REWORK=$(jq '.finalReview.reworkItems | length' "${STATE_FILE}")
assert_eq "final result SHIP" "SHIP" "${RESULT}"
assert_eq "final review status done" "done" "${FR_STATUS}"
assert_eq "no rework items" "0" "${REWORK}"

# ===================================================================
echo ""
echo "=== Test 7: Aggregation — any FAIL yields REVISE ==="

STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

UPDATED=$(jq '
	(.items[] | select(.id == 1)).reviewStatus = "passed" |
	(.items[] | select(.id == 2)).reviewStatus = "failed" |
	(.items[] | select(.id == 3)).reviewStatus = "passed" |
	(.items[] | select(.id == 4)).reviewStatus = "failed"
' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

# Write review files for feedback aggregation
printf 'FAIL\nItem 2 has a bug.\n' >"${REVIEW_DIR}/item-2-review.txt"
printf 'FAIL\nItem 4 missing tests.\n' >"${REVIEW_DIR}/item-4-review.txt"

FAILED_IDS=$(jq -r '.items[] | select(.reviewStatus == "failed") | .id' "${STATE_FILE}")
FAILED_ITEMS=()
for fid in ${FAILED_IDS}; do
  FAILED_ITEMS+=("${fid}")
done

assert_eq "2 failed items" "2" "${#FAILED_ITEMS[@]}"

# Build rework JSON and write REVISE result
REWORK_JSON=$(printf '%s\n' "${FAILED_ITEMS[@]}" | jq -R 'tonumber' | jq -s '.')

AGG_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq --arg now "${AGG_NOW}" --argjson rework "${REWORK_JSON}" \
  '.finalReview.status = "done" |
	 .finalReview.result = "REVISE" |
	 .finalReview.reworkItems = $rework |
	 .updatedAt = $now |
	 reduce ($rework[] | tostring | tonumber) as $id (.;
		(.items[] | select(.id == $id)).status = "ready"
	 )' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

RESULT=$(jq -r '.finalReview.result' "${STATE_FILE}")
REWORK_IDS=$(jq -c '.finalReview.reworkItems' "${STATE_FILE}")
S2=$(jq -r '.items[] | select(.id == 2) | .status' "${STATE_FILE}")
S4=$(jq -r '.items[] | select(.id == 4) | .status' "${STATE_FILE}")
S1=$(jq -r '.items[] | select(.id == 1) | .status' "${STATE_FILE}")

assert_eq "final result REVISE" "REVISE" "${RESULT}"
assert_eq "rework items [2,4]" "[2,4]" "${REWORK_IDS}"
assert_eq "failed item 2 reset to ready" "ready" "${S2}"
assert_eq "failed item 4 reset to ready" "ready" "${S4}"
assert_eq "passed item 1 stays done" "done" "${S1}"

# Write feedback file
FEEDBACK_FILE="${TEST_PLAN_DIR}/review-feedback.txt"
{
  printf 'REWORK_ITEMS: %s\n' "$(printf '%s\n' "${FAILED_ITEMS[@]}" | paste -sd ', ' -)"
  for fid in "${FAILED_ITEMS[@]}"; do
    review="${REVIEW_DIR}/item-${fid}-review.txt"
    if [[ -f "${review}" ]]; then
      printf '\n--- item %s ---\n' "${fid}"
      tail -n +2 "${review}"
    fi
  done
} >"${FEEDBACK_FILE}"

FEEDBACK=$(cat "${FEEDBACK_FILE}")
assert_contains "feedback has rework items" "${FEEDBACK}" "REWORK_ITEMS: 2,4"
assert_contains "feedback has item 2 notes" "${FEEDBACK}" "Item 2 has a bug"
assert_contains "feedback has item 4 notes" "${FEEDBACK}" "Item 4 missing tests"

# ===================================================================
echo ""
echo "=== Test 8: Poll loop termination — exits when no pending or reviewing ==="

STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

# All passed — nothing pending or reviewing
UPDATED=$(jq '
	(.items[]).reviewStatus = "passed"
' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

cnt_reviewing=$(jq '[.items[] | select(.reviewStatus == "reviewing")] | length' "${STATE_FILE}")
cnt_pending=$(jq '[.items[] | select(.reviewStatus == "pending")] | length' "${STATE_FILE}")

# The poll loop breaks when both are 0
SHOULD_BREAK="false"
if [[ "${cnt_reviewing}" -eq 0 ]] && [[ "${cnt_pending}" -eq 0 ]]; then
  SHOULD_BREAK="true"
fi
assert_eq "poll loop terminates when all complete" "true" "${SHOULD_BREAK}"

# ===================================================================
echo ""
echo "=== Test 9: Concurrency limit respected — spawned <= available_slots ==="

# With max_workers=2 and 2 already reviewing, no slots available
STATE=$(build_state 2)
orch_write_state "${TEST_SLUG}" "${STATE}"

UPDATED=$(jq '
	(.items[] | select(.id == 1)).reviewStatus = "reviewing" |
	(.items[] | select(.id == 2)).reviewStatus = "reviewing"
' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

MAX_WORKERS=$(jq '.maxParallelWorkers' "${STATE_FILE}")
cnt_reviewing=$(jq '[.items[] | select(.reviewStatus == "reviewing")] | length' "${STATE_FILE}")
available_slots=$((MAX_WORKERS - cnt_reviewing))

assert_eq "at capacity — 0 available slots" "0" "${available_slots}"

# Verify the pending items that would be spawned
cnt_pending=$(jq '[.items[] | select(.reviewStatus == "pending")] | length' "${STATE_FILE}")
assert_eq "2 items still pending" "2" "${cnt_pending}"

# Simulate: count how many would spawn
spawned=0
if ((available_slots > 0 && cnt_pending > 0)); then
  pending_ids=$(jq -r '.items[] | select(.reviewStatus == "pending") | .id' "${STATE_FILE}")
  for _ in ${pending_ids}; do
    if ((spawned >= available_slots)); then break; fi
    spawned=$((spawned + 1))
  done
fi
assert_eq "0 spawned when at capacity" "0" "${spawned}"

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
