#!/usr/bin/env bash
# End-to-end tests for orchestrator: parse, wave scheduling, state management.
# Uses a synthetic plan with known dependency structure to verify behavior.
#
# Usage: bash tests/test-orch-e2e.sh
#
# Tests run without tmux or claude — they validate state logic only.

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

assert_dir_not_exists() {
  local label="$1" path="$2"
  if [[ ! -d "${path}" ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label} — directory exists: ${path}"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup synthetic test plan ---

TEST_SLUG="test-orch-e2e-$$"
TEST_PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${TEST_SLUG}"
ORCH_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE="${ORCH_DIR}/state.json"

cleanup() {
  rm -rf "${TEST_PLAN_DIR}"
  rm -rf "${ORCH_DIR}"
}
trap cleanup EXIT

mkdir -p "${TEST_PLAN_DIR}"

# Synthetic plan: 5 items with dependency waves
#   Wave 1: items 1, 2 (no deps — both ready)
#   Wave 2: item 3 (deps: 1, 2), item 4 (deps: 2)
#   Wave 3: item 5 (deps: 3, 4)
cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Orchestrator E2E

**Status:** In progress

## Requirements

Test plan for orchestrator wave scheduling verification.

## Approach

Synthetic items with known dependency structure.

## Progress log

- [ ] Alpha task — no dependencies (deps: )
- [ ] Beta task — no dependencies (deps: )
- [ ] Gamma task — depends on alpha and beta (deps: 1, 2)
- [ ] Delta task — depends on beta only (deps: 2)
- [ ] Epsilon task — depends on gamma and delta (deps: 3, 4)

## Completion criteria

- [ ] All items scheduled in correct wave order
PLAN

echo ""
echo "=== Test 1: orch-parse-items.sh ==="

PARSED=$("${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")

# Verify item count
ITEM_COUNT=$(printf '%s' "${PARSED}" | jq '.items | length')
assert_eq "item count" "5" "${ITEM_COUNT}"

# Verify slug
PARSED_SLUG=$(printf '%s' "${PARSED}" | jq -r '.slug')
assert_eq "slug" "${TEST_SLUG}" "${PARSED_SLUG}"

# Verify item 1: no deps, not checked
ITEM1_DESC=$(printf '%s' "${PARSED}" | jq -r '.items[0].description')
ITEM1_DEPS=$(printf '%s' "${PARSED}" | jq '.items[0].deps | length')
ITEM1_CHECKED=$(printf '%s' "${PARSED}" | jq '.items[0].checked')
assert_eq "item 1 description" "Alpha task — no dependencies" "${ITEM1_DESC}"
assert_eq "item 1 deps count" "0" "${ITEM1_DEPS}"
assert_eq "item 1 not checked" "false" "${ITEM1_CHECKED}"

# Verify item 3: deps [1, 2]
ITEM3_DEPS=$(printf '%s' "${PARSED}" | jq -c '.items[2].deps')
assert_eq "item 3 deps" "[1,2]" "${ITEM3_DEPS}"

# Verify item 4: deps [2]
ITEM4_DEPS=$(printf '%s' "${PARSED}" | jq -c '.items[3].deps')
assert_eq "item 4 deps" "[2]" "${ITEM4_DEPS}"

# Verify item 5: deps [3, 4]
ITEM5_DEPS=$(printf '%s' "${PARSED}" | jq -c '.items[4].deps')
assert_eq "item 5 deps" "[3,4]" "${ITEM5_DEPS}"

echo ""
echo "=== Test 2: orch-parse-items.sh with pre-checked items ==="

# Rewrite plan with items 1 and 2 already checked
cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Orchestrator E2E

**Status:** In progress

## Requirements

Test plan for orchestrator wave scheduling verification.

## Approach

Synthetic items with known dependency structure.

## Progress log

- [x] Alpha task — no dependencies (deps: )
- [x] Beta task — no dependencies (deps: )
- [ ] Gamma task — depends on alpha and beta (deps: 1, 2)
- [ ] Delta task — depends on beta only (deps: 2)
- [ ] Epsilon task — depends on gamma and delta (deps: 3, 4)

## Completion criteria

- [ ] All items scheduled in correct wave order
PLAN

PARSED2=$("${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")

ITEM1_CHECKED2=$(printf '%s' "${PARSED2}" | jq '.items[0].checked')
ITEM2_CHECKED2=$(printf '%s' "${PARSED2}" | jq '.items[1].checked')
ITEM3_CHECKED2=$(printf '%s' "${PARSED2}" | jq '.items[2].checked')
assert_eq "item 1 checked" "true" "${ITEM1_CHECKED2}"
assert_eq "item 2 checked" "true" "${ITEM2_CHECKED2}"
assert_eq "item 3 not checked" "false" "${ITEM3_CHECKED2}"

echo ""
echo "=== Test 3: State initialization — wave scheduling ==="

# Reset plan to unchecked for clean state init test
cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Orchestrator E2E

**Status:** In progress

## Requirements

Test plan for orchestrator wave scheduling verification.

## Approach

Synthetic items with known dependency structure.

## Progress log

- [ ] Alpha task — no dependencies (deps: )
- [ ] Beta task — no dependencies (deps: )
- [ ] Gamma task — depends on alpha and beta (deps: 1, 2)
- [ ] Delta task — depends on beta only (deps: 2)
- [ ] Epsilon task — depends on gamma and delta (deps: 3, 4)

## Completion criteria

- [ ] All items scheduled in correct wave order
PLAN

# Source orch-state.sh to get helper functions
ORCH_STATE_DIR="${ORCH_DIR}"
ORCH_STATE_FILE="${ORCH_STATE}"
export ORCH_REPO_ROOT="${REPO_ROOT}"
export ORCH_STATE_DIR
export ORCH_STATE_FILE
# shellcheck source=../scripts/orch-state.sh
source "${REPO_ROOT}/scripts/orch-state.sh"

# Parse items and build state (extracted from orch-start.sh logic)
PARSED3=$("${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")
orch_ensure_done_dir "${TEST_SLUG}"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ITEMS_JSON=$(printf '%s' "${PARSED3}" | jq --argjson maxIter 3 '[
  .items[] | {
    id: .id,
    description: .description,
    deps: .deps,
    status: (if .checked then "done" else
      (if (.deps | length) == 0 then "ready" else "queued" end)
    end),
    workerPid: null,
    tmuxPane: null,
    worktree: null,
    iteration: (if .checked then 1 else 0 end),
    maxIterations: $maxIter,
    lastResult: (if .checked then "SHIP" else null end)
  }
]')

# Resolve ready status based on deps
ITEMS_JSON=$(printf '%s' "${ITEMS_JSON}" | jq '[
  . as $all |
  .[] | . as $item |
  if $item.status == "queued" then
    if ([$all[] | select(.id == ($item.deps[])) | .status] | all(. == "done")) then
      .status = "ready"
    else .
    end
  else .
  end
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
    finalReview: { status: "pending", result: null, reworkItems: [] },
    startedAt: $startedAt,
    updatedAt: $updatedAt
  }')

orch_write_state "${STATE_JSON}"

# Wave 1: items 1 and 2 should be "ready" (no deps)
S1=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
S2=$(jq -r '.items[] | select(.id == 2) | .status' "${ORCH_STATE_FILE}")
assert_eq "item 1 (no deps) is ready" "ready" "${S1}"
assert_eq "item 2 (no deps) is ready" "ready" "${S2}"

# Wave 2: items 3, 4 should be "queued" (deps not done)
S3=$(jq -r '.items[] | select(.id == 3) | .status' "${ORCH_STATE_FILE}")
S4=$(jq -r '.items[] | select(.id == 4) | .status' "${ORCH_STATE_FILE}")
assert_eq "item 3 (deps: 1,2) is queued" "queued" "${S3}"
assert_eq "item 4 (deps: 2) is queued" "queued" "${S4}"

# Wave 3: item 5 should be "queued"
S5=$(jq -r '.items[] | select(.id == 5) | .status' "${ORCH_STATE_FILE}")
assert_eq "item 5 (deps: 3,4) is queued" "queued" "${S5}"

echo ""
echo "=== Test 4: Wave scheduling with pre-done items ==="

# Now test with items 1,2 already checked (simulates wave 1 complete)
cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Orchestrator E2E

**Status:** In progress

## Progress log

- [x] Alpha task — no dependencies (deps: )
- [x] Beta task — no dependencies (deps: )
- [ ] Gamma task — depends on alpha and beta (deps: 1, 2)
- [ ] Delta task — depends on beta only (deps: 2)
- [ ] Epsilon task — depends on gamma and delta (deps: 3, 4)
PLAN

PARSED4=$("${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")

ITEMS_JSON4=$(printf '%s' "${PARSED4}" | jq --argjson maxIter 3 '[
  .items[] | {
    id: .id,
    description: .description,
    deps: .deps,
    status: (if .checked then "done" else
      (if (.deps | length) == 0 then "ready" else "queued" end)
    end),
    workerPid: null,
    tmuxPane: null,
    worktree: null,
    iteration: (if .checked then 1 else 0 end),
    maxIterations: $maxIter,
    lastResult: (if .checked then "SHIP" else null end)
  }
]')

# Resolve ready
ITEMS_JSON4=$(printf '%s' "${ITEMS_JSON4}" | jq '[
  . as $all |
  .[] | . as $item |
  if $item.status == "queued" then
    if ([$all[] | select(.id == ($item.deps[])) | .status] | all(. == "done")) then
      .status = "ready"
    else .
    end
  else .
  end
]')

STATE4=$(jq -n \
  --argjson version 1 \
  --arg plan "${TEST_SLUG}" \
  --argjson maxWorkers 4 \
  --arg mode "foreground" \
  --argjson items "${ITEMS_JSON4}" \
  --arg startedAt "${NOW}" \
  --arg updatedAt "${NOW}" \
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
orch_write_state "${STATE4}"

# Items 1,2 should be done
D1=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
D2=$(jq -r '.items[] | select(.id == 2) | .status' "${ORCH_STATE_FILE}")
assert_eq "item 1 pre-checked is done" "done" "${D1}"
assert_eq "item 2 pre-checked is done" "done" "${D2}"

# Items 3,4 should now be "ready" (their deps are all done)
R3=$(jq -r '.items[] | select(.id == 3) | .status' "${ORCH_STATE_FILE}")
R4=$(jq -r '.items[] | select(.id == 4) | .status' "${ORCH_STATE_FILE}")
assert_eq "item 3 (deps done) is ready" "ready" "${R3}"
assert_eq "item 4 (deps done) is ready" "ready" "${R4}"

# Item 5 should still be queued (deps 3,4 not done yet)
Q5=$(jq -r '.items[] | select(.id == 5) | .status' "${ORCH_STATE_FILE}")
assert_eq "item 5 (deps 3,4 not done) is queued" "queued" "${Q5}"

echo ""
echo "=== Test 5: Done-file sync ==="

# Simulate: mark items 3,4 as running, then write done-files
orch_update_item_status 3 "running"
orch_update_item_status 4 "running"

DONE_DIR="${ORCH_DIR}/done/${TEST_SLUG}"
printf 'Gamma task completed: implemented the feature.\n' >"${DONE_DIR}/item-3.txt"
printf 'Delta task completed: updated the config.\n' >"${DONE_DIR}/item-4.txt"

# Sync should detect done-files and mark items done
orch_sync_done_files "${TEST_SLUG}"

SYNC3=$(jq -r '.items[] | select(.id == 3) | .status' "${ORCH_STATE_FILE}")
SYNC4=$(jq -r '.items[] | select(.id == 4) | .status' "${ORCH_STATE_FILE}")
assert_eq "item 3 synced to done" "done" "${SYNC3}"
assert_eq "item 4 synced to done" "done" "${SYNC4}"

echo ""
echo "=== Test 5b: Full 3-wave lifecycle — resolve_deps promotes waves in order ==="

# Reset to clean state: all 5 items, nothing checked
cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Test Orchestrator E2E

**Status:** In progress

## Progress log

- [ ] Alpha task — no dependencies
- [ ] Beta task — no dependencies
- [ ] Gamma task — depends on alpha and beta (deps: 1, 2)
- [ ] Delta task — depends on beta only (deps: 2)
- [ ] Epsilon task — depends on gamma and delta (deps: 3, 4)
PLAN

PARSED5=$("${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")
ITEMS_JSON5=$(printf '%s' "${PARSED5}" | jq --argjson maxIter 3 '[
  .items[] | {
    id: .id,
    description: .description,
    deps: .deps,
    status: (if .checked then "done" else
      (if (.deps | length) == 0 then "ready" else "queued" end)
    end),
    workerPid: null, tmuxPane: null, worktree: null,
    iteration: 0, maxIterations: $maxIter, lastResult: null
  }
]')

STATE5=$(jq -n \
  --argjson version 1 \
  --arg plan "${TEST_SLUG}" \
  --argjson maxWorkers 4 \
  --arg mode "foreground" \
  --argjson items "${ITEMS_JSON5}" \
  --arg startedAt "${NOW}" \
  --arg updatedAt "${NOW}" \
  '{
    version: $version, plan: $plan, maxParallelWorkers: $maxWorkers,
    mode: $mode, items: $items,
    finalReview: { status: "pending", result: null, reworkItems: [] },
    startedAt: $startedAt, updatedAt: $updatedAt
  }')
orch_write_state "${STATE5}"

# Clean done-files from previous tests
rm -rf "${ORCH_DIR}/done/${TEST_SLUG}"
orch_ensure_done_dir "${TEST_SLUG}"
DONE_DIR="${ORCH_DIR}/done/${TEST_SLUG}"

# resolve_deps mirrors orch-loop.sh — promotes queued→ready when deps are done
resolve_deps() {
  local state
  state=$(cat "${ORCH_STATE_FILE}")
  local queued_ids
  queued_ids=$(printf '%s' "${state}" | jq -r '.items[] | select(.status == "queued") | .id')
  for item_id in ${queued_ids}; do
    local all_deps_done
    all_deps_done=$(printf '%s' "${state}" | jq --argjson id "${item_id}" '
      . as $root |
      ($root.items[] | select(.id == $id) | .deps) as $deps |
      if ($deps | length) == 0 then true
      else [$root.items[] | select(.id == ($deps[])) | .status] | all(. == "done")
      end')
    if [[ "${all_deps_done}" == "true" ]]; then
      local now_ts
      now_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      state=$(printf '%s' "${state}" | jq \
        --argjson id "${item_id}" \
        --arg now "${now_ts}" \
        '(.items[] | select(.id == $id)).status = "ready" | .updatedAt = $now')
    fi
  done
  orch_write_state "${state}"
}

# --- Wave 1: items 1,2 are ready ---
W1_S1=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
W1_S2=$(jq -r '.items[] | select(.id == 2) | .status' "${ORCH_STATE_FILE}")
W1_S3=$(jq -r '.items[] | select(.id == 3) | .status' "${ORCH_STATE_FILE}")
assert_eq "wave1: item 1 ready" "ready" "${W1_S1}"
assert_eq "wave1: item 2 ready" "ready" "${W1_S2}"
assert_eq "wave1: item 3 queued" "queued" "${W1_S3}"

# Simulate wave 1 workers: mark running, write done-files, sync
orch_update_item_status 1 "running"
orch_update_item_status 2 "running"
printf 'Alpha completed.\n' >"${DONE_DIR}/item-1.txt"
printf 'Beta completed.\n' >"${DONE_DIR}/item-2.txt"
orch_sync_done_files "${TEST_SLUG}"

W1_D1=$(jq -r '.items[] | select(.id == 1) | .status' "${ORCH_STATE_FILE}")
W1_D2=$(jq -r '.items[] | select(.id == 2) | .status' "${ORCH_STATE_FILE}")
assert_eq "wave1: item 1 done after sync" "done" "${W1_D1}"
assert_eq "wave1: item 2 done after sync" "done" "${W1_D2}"

# --- Wave 2: resolve_deps should promote items 3,4 to ready ---
resolve_deps

W2_S3=$(jq -r '.items[] | select(.id == 3) | .status' "${ORCH_STATE_FILE}")
W2_S4=$(jq -r '.items[] | select(.id == 4) | .status' "${ORCH_STATE_FILE}")
W2_S5=$(jq -r '.items[] | select(.id == 5) | .status' "${ORCH_STATE_FILE}")
assert_eq "wave2: item 3 promoted to ready" "ready" "${W2_S3}"
assert_eq "wave2: item 4 promoted to ready" "ready" "${W2_S4}"
assert_eq "wave2: item 5 still queued" "queued" "${W2_S5}"

# Simulate wave 2 workers: run, done-files, sync
orch_update_item_status 3 "running"
orch_update_item_status 4 "running"
printf 'Gamma completed.\n' >"${DONE_DIR}/item-3.txt"
printf 'Delta completed.\n' >"${DONE_DIR}/item-4.txt"
orch_sync_done_files "${TEST_SLUG}"

W2_D3=$(jq -r '.items[] | select(.id == 3) | .status' "${ORCH_STATE_FILE}")
W2_D4=$(jq -r '.items[] | select(.id == 4) | .status' "${ORCH_STATE_FILE}")
assert_eq "wave2: item 3 done after sync" "done" "${W2_D3}"
assert_eq "wave2: item 4 done after sync" "done" "${W2_D4}"

# --- Wave 3: resolve_deps should promote item 5 to ready ---
resolve_deps

W3_S5=$(jq -r '.items[] | select(.id == 5) | .status' "${ORCH_STATE_FILE}")
assert_eq "wave3: item 5 promoted to ready" "ready" "${W3_S5}"

# Simulate wave 3 worker: run, done-file, sync
orch_update_item_status 5 "running"
printf 'Epsilon completed.\n' >"${DONE_DIR}/item-5.txt"
orch_sync_done_files "${TEST_SLUG}"

W3_D5=$(jq -r '.items[] | select(.id == 5) | .status' "${ORCH_STATE_FILE}")
assert_eq "wave3: item 5 done after sync" "done" "${W3_D5}"

# All done
ALL_DONE=$(jq '[.items[] | select(.status == "done")] | length' "${ORCH_STATE_FILE}")
assert_eq "all 5 items done" "5" "${ALL_DONE}"

echo ""
echo "=== Test 5c: Wave order enforced — item 5 never ready before deps ==="

# Verify: if only item 1 is done, item 3 (deps: 1,2) should NOT be ready
rm -rf "${ORCH_DIR}/done/${TEST_SLUG}"
orch_ensure_done_dir "${TEST_SLUG}"

orch_write_state "${STATE5}"
orch_update_item_status 1 "running"
printf 'Alpha done.\n' >"${DONE_DIR}/item-1.txt"
orch_sync_done_files "${TEST_SLUG}"
resolve_deps

# Item 3 needs both 1 AND 2 — only 1 is done
PARTIAL_S3=$(jq -r '.items[] | select(.id == 3) | .status' "${ORCH_STATE_FILE}")
assert_eq "partial deps: item 3 still queued (only dep 1 done)" "queued" "${PARTIAL_S3}"

# Item 4 needs only 2 — 2 is still ready (not done)
PARTIAL_S4=$(jq -r '.items[] | select(.id == 4) | .status' "${ORCH_STATE_FILE}")
assert_eq "partial deps: item 4 still queued (dep 2 not done)" "queued" "${PARTIAL_S4}"

echo ""
echo "=== Test 6: No items/ directory created ==="

assert_dir_not_exists "no items/ subdirectory" "${ORCH_DIR}/items"

echo ""
echo "=== Test 7: orch-worker.sh arg validation ==="

# Missing args should fail
if bash "${REPO_ROOT}/scripts/orch-worker.sh" 2>/dev/null; then
  echo "  FAIL: orch-worker.sh should fail with no args"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: orch-worker.sh rejects no args"
  PASS=$((PASS + 1))
fi

if bash "${REPO_ROOT}/scripts/orch-worker.sh" "${TEST_SLUG}" 2>/dev/null; then
  echo "  FAIL: orch-worker.sh should fail without --item"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: orch-worker.sh rejects missing --item"
  PASS=$((PASS + 1))
fi

echo ""
echo "=== Test 8: orch-review.sh blocks if items not all done ==="

# Item 5 is still queued — review should fail
if bash "${REPO_ROOT}/scripts/orch-review.sh" "${TEST_SLUG}" 2>/dev/null; then
  echo "  FAIL: orch-review.sh should fail when items not all done"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: orch-review.sh blocks when items not all done"
  PASS=$((PASS + 1))
fi

echo ""
echo "=== Test 9: orch-status.sh runs without error ==="

if bash "${REPO_ROOT}/scripts/orch-status.sh" "${TEST_SLUG}" >/dev/null 2>&1; then
  echo "  PASS: orch-status.sh runs cleanly"
  PASS=$((PASS + 1))
else
  echo "  FAIL: orch-status.sh exited with error"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Test 10: State query helpers ==="

PLAN_NAME=$(orch_get_plan)
assert_eq "orch_get_plan" "${TEST_SLUG}" "${PLAN_NAME}"

MODE=$(orch_get_mode)
assert_eq "orch_get_mode" "foreground" "${MODE}"

DONE_COUNT=$(orch_count_by_status "done")
assert_eq "done count" "1" "${DONE_COUNT}"

READY_COUNT=$(orch_count_by_status "ready")
assert_eq "ready count" "1" "${READY_COUNT}"

QUEUED_COUNT=$(orch_count_by_status "queued")
assert_eq "queued count" "3" "${QUEUED_COUNT}"

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
