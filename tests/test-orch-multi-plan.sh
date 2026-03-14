#!/usr/bin/env bash
# Smoke test: two plans running simultaneously with isolated state and
# master registry updates. Exercises orch-state.sh multi-plan functions
# without tmux or claude — pure state-logic verification.
#
# Usage: bash tests/test-orch-multi-plan.sh

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

assert_dir_exists() {
	local label="$1" path="$2"
	if [[ -d "${path}" ]]; then
		echo "  PASS: ${label}"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: ${label} — directory not found: ${path}"
		FAIL=$((FAIL + 1))
	fi
}

# --- Setup ---

SLUG_A="test-plan-alpha-$$"
SLUG_B="test-plan-beta-$$"
ORCH_DIR="${REPO_ROOT}/.orchestrator-test-$$"

cleanup() {
	rm -rf "${ORCH_DIR}"
}
trap cleanup EXIT

# Override orchestrator paths to use test directory
export ORCH_REPO_ROOT="${REPO_ROOT}"
export ORCH_STATE_DIR="${ORCH_DIR}"
export ORCH_MASTER_FILE="${ORCH_DIR}/master.json"

# shellcheck source=../scripts/orch-state.sh
source "${REPO_ROOT}/scripts/orch-state.sh"

# --- Helper: build a minimal state.json for a plan ---

build_plan_state() {
	local slug="$1"
	local item_count="$2"
	local now
	now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	local items="[]"
	for ((i = 1; i <= item_count; i++)); do
		items=$(printf '%s' "${items}" | jq \
			--argjson id "${i}" \
			'. + [{
				id: $id,
				description: ("task-" + ($id | tostring)),
				deps: [],
				status: "ready",
				workerPid: null,
				tmuxPane: null,
				worktree: null,
				iteration: 0,
				maxIterations: 3,
				lastResult: null
			}]')
	done

	jq -n \
		--argjson version 1 \
		--arg plan "${slug}" \
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
		}'
}

echo ""
echo "=== Test 1: Per-plan directory isolation ==="

orch_ensure_plan_dirs "${SLUG_A}"
orch_ensure_plan_dirs "${SLUG_B}"

assert_dir_exists "plan A dir exists" "$(orch_plan_dir "${SLUG_A}")"
assert_dir_exists "plan B dir exists" "$(orch_plan_dir "${SLUG_B}")"
assert_dir_exists "plan A done dir" "$(orch_plan_done_dir "${SLUG_A}")"
assert_dir_exists "plan B done dir" "$(orch_plan_done_dir "${SLUG_B}")"
assert_dir_exists "plan A review dir" "$(orch_plan_review_dir "${SLUG_A}")"
assert_dir_exists "plan B review dir" "$(orch_plan_review_dir "${SLUG_B}")"

# Paths are distinct
STATE_A=$(orch_plan_state_file "${SLUG_A}")
STATE_B=$(orch_plan_state_file "${SLUG_B}")
if [[ "${STATE_A}" != "${STATE_B}" ]]; then
	echo "  PASS: state file paths are distinct"
	PASS=$((PASS + 1))
else
	echo "  FAIL: state file paths collide: ${STATE_A}"
	FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Test 2: Write and read per-plan state independently ==="

STATE_JSON_A=$(build_plan_state "${SLUG_A}" 3)
STATE_JSON_B=$(build_plan_state "${SLUG_B}" 5)

orch_write_state "${SLUG_A}" "${STATE_JSON_A}"
orch_write_state "${SLUG_B}" "${STATE_JSON_B}"

assert_file_exists "plan A state file written" "${STATE_A}"
assert_file_exists "plan B state file written" "${STATE_B}"

COUNT_A=$(jq '.items | length' "${STATE_A}")
COUNT_B=$(jq '.items | length' "${STATE_B}")
assert_eq "plan A has 3 items" "3" "${COUNT_A}"
assert_eq "plan B has 5 items" "5" "${COUNT_B}"

PLAN_A_NAME=$(jq -r '.plan' "${STATE_A}")
PLAN_B_NAME=$(jq -r '.plan' "${STATE_B}")
assert_eq "plan A name" "${SLUG_A}" "${PLAN_A_NAME}"
assert_eq "plan B name" "${SLUG_B}" "${PLAN_B_NAME}"

echo ""
echo "=== Test 3: Master state registration ==="

orch_master_register "${SLUG_A}"
assert_file_exists "master.json created after first register" "${ORCH_MASTER_FILE}"

PLAN_COUNT=$(jq '.plans | length' "${ORCH_MASTER_FILE}")
assert_eq "master has 1 plan after first register" "1" "${PLAN_COUNT}"

FIRST_SLUG=$(jq -r '.plans[0].slug' "${ORCH_MASTER_FILE}")
FIRST_STATUS=$(jq -r '.plans[0].status' "${ORCH_MASTER_FILE}")
assert_eq "first plan slug" "${SLUG_A}" "${FIRST_SLUG}"
assert_eq "first plan status" "running" "${FIRST_STATUS}"

orch_master_register "${SLUG_B}"
PLAN_COUNT=$(jq '.plans | length' "${ORCH_MASTER_FILE}")
assert_eq "master has 2 plans after second register" "2" "${PLAN_COUNT}"

SECOND_SLUG=$(jq -r '.plans[1].slug' "${ORCH_MASTER_FILE}")
assert_eq "second plan slug" "${SLUG_B}" "${SECOND_SLUG}"

echo ""
echo "=== Test 4: Master progress updates are isolated ==="

# Mark item 1 in plan A as running, item 2 as done
orch_update_item_status "${SLUG_A}" 1 "running"
orch_update_item_status "${SLUG_A}" 2 "done"

# Mark items 1-3 in plan B as running
orch_update_item_status "${SLUG_B}" 1 "running"
orch_update_item_status "${SLUG_B}" 2 "running"
orch_update_item_status "${SLUG_B}" 3 "running"

orch_master_update_progress "${SLUG_A}"
orch_master_update_progress "${SLUG_B}"

PROG_A_DONE=$(jq '.plans[] | select(.slug == "'"${SLUG_A}"'") | .progress.done' \
	"${ORCH_MASTER_FILE}")
PROG_A_RUNNING=$(jq '.plans[] | select(.slug == "'"${SLUG_A}"'") | .progress.running' \
	"${ORCH_MASTER_FILE}")
PROG_A_TOTAL=$(jq '.plans[] | select(.slug == "'"${SLUG_A}"'") | .progress.total' \
	"${ORCH_MASTER_FILE}")
assert_eq "plan A progress: done=1" "1" "${PROG_A_DONE}"
assert_eq "plan A progress: running=1" "1" "${PROG_A_RUNNING}"
assert_eq "plan A progress: total=3" "3" "${PROG_A_TOTAL}"

PROG_B_DONE=$(jq '.plans[] | select(.slug == "'"${SLUG_B}"'") | .progress.done' \
	"${ORCH_MASTER_FILE}")
PROG_B_RUNNING=$(jq '.plans[] | select(.slug == "'"${SLUG_B}"'") | .progress.running' \
	"${ORCH_MASTER_FILE}")
PROG_B_TOTAL=$(jq '.plans[] | select(.slug == "'"${SLUG_B}"'") | .progress.total' \
	"${ORCH_MASTER_FILE}")
assert_eq "plan B progress: done=0" "0" "${PROG_B_DONE}"
assert_eq "plan B progress: running=3" "3" "${PROG_B_RUNNING}"
assert_eq "plan B progress: total=5" "5" "${PROG_B_TOTAL}"

echo ""
echo "=== Test 5: Done-file sync is plan-scoped ==="

DONE_A=$(orch_plan_done_dir "${SLUG_A}")
DONE_B=$(orch_plan_done_dir "${SLUG_B}")

# Write done-file for plan A item 1
printf 'Item 1 of plan A completed.\n' >"${DONE_A}/item-1.txt"

# Write done-file for plan B item 2
printf 'Item 2 of plan B completed.\n' >"${DONE_B}/item-2.txt"

# Sync plan A — should only pick up A's done-files
orch_sync_done_files "${SLUG_A}"

A1_STATUS=$(jq -r '.items[] | select(.id == 1) | .status' "${STATE_A}")
assert_eq "plan A item 1 synced to done" "done" "${A1_STATUS}"

# Plan B item 2 is still running (we haven't synced B yet)
B2_STATUS=$(jq -r '.items[] | select(.id == 2) | .status' "${STATE_B}")
assert_eq "plan B item 2 still running before sync" "running" "${B2_STATUS}"

# Now sync plan B
orch_sync_done_files "${SLUG_B}"
B2_STATUS=$(jq -r '.items[] | select(.id == 2) | .status' "${STATE_B}")
assert_eq "plan B item 2 synced to done after B sync" "done" "${B2_STATUS}"

# Verify plan A wasn't affected by plan B sync
A_DONE_COUNT=$(jq '[.items[] | select(.status == "done")] | length' "${STATE_A}")
assert_eq "plan A still has exactly 2 done items" "2" "${A_DONE_COUNT}"

echo ""
echo "=== Test 6: Deregister one plan — other remains ==="

orch_master_deregister "${SLUG_A}" "completed"

A_MASTER_STATUS=$(jq -r '.plans[] | select(.slug == "'"${SLUG_A}"'") | .status' \
	"${ORCH_MASTER_FILE}")
B_MASTER_STATUS=$(jq -r '.plans[] | select(.slug == "'"${SLUG_B}"'") | .status' \
	"${ORCH_MASTER_FILE}")
assert_eq "plan A deregistered as completed" "completed" "${A_MASTER_STATUS}"
assert_eq "plan B still running in master" "running" "${B_MASTER_STATUS}"

PLAN_COUNT=$(jq '.plans | length' "${ORCH_MASTER_FILE}")
assert_eq "master still has 2 entries" "2" "${PLAN_COUNT}"

echo ""
echo "=== Test 7: Re-register replaces stale entry ==="

orch_master_register "${SLUG_A}"
A_STATUS_AFTER=$(jq -r '.plans[] | select(.slug == "'"${SLUG_A}"'") | .status' \
	"${ORCH_MASTER_FILE}")
assert_eq "re-registered plan A is running" "running" "${A_STATUS_AFTER}"

PLAN_COUNT=$(jq '.plans | length' "${ORCH_MASTER_FILE}")
assert_eq "master has 2 entries (no duplicate)" "2" "${PLAN_COUNT}"

echo ""
echo "=== Test 8: orch_count_by_status is plan-scoped ==="

A_READY=$(orch_count_by_status "${SLUG_A}" "ready")
B_READY=$(orch_count_by_status "${SLUG_B}" "ready")
assert_eq "plan A ready count" "1" "${A_READY}"
assert_eq "plan B ready count" "2" "${B_READY}"

echo ""
echo "=== Test 9: orch_promote_ready_items is plan-scoped ==="

# Add a plan with dependencies to test promotion isolation
SLUG_C="test-plan-gamma-$$"
orch_ensure_plan_dirs "${SLUG_C}"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ITEMS_C=$(jq -n '[
	{ id: 1, description: "first", deps: [],
	  status: "done", workerPid: null, tmuxPane: null,
	  worktree: null, iteration: 0, maxIterations: 3,
	  lastResult: "SHIP" },
	{ id: 2, description: "second", deps: [1],
	  status: "queued", workerPid: null, tmuxPane: null,
	  worktree: null, iteration: 0, maxIterations: 3,
	  lastResult: null }
]')
STATE_C=$(jq -n \
	--argjson version 1 \
	--arg plan "${SLUG_C}" \
	--argjson maxWorkers 4 \
	--arg mode "foreground" \
	--argjson items "${ITEMS_C}" \
	--arg startedAt "${NOW}" \
	--arg updatedAt "${NOW}" \
	'{
		version: $version, plan: $plan,
		maxParallelWorkers: $maxWorkers, mode: $mode,
		items: $items,
		finalReview: { status: "pending", result: null, reworkItems: [] },
		startedAt: $startedAt, updatedAt: $updatedAt
	}')
orch_write_state "${SLUG_C}" "${STATE_C}"

# Promote plan C — item 2 should become ready (dep 1 is done)
orch_promote_ready_items "${SLUG_C}"
C2_STATUS=$(jq -r '.items[] | select(.id == 2) | .status' \
	"$(orch_plan_state_file "${SLUG_C}")")
assert_eq "plan C item 2 promoted to ready" "ready" "${C2_STATUS}"

# Verify plan B was not affected by plan C promotion
B4_STATUS=$(jq -r '.items[] | select(.id == 4) | .status' "${STATE_B}")
assert_eq "plan B item 4 unchanged after plan C promote" "ready" "${B4_STATUS}"

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
	exit 1
fi
