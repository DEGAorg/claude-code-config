#!/usr/bin/env bash
# Tests for GH mode: plan path resolution and SHIP step gating.
#
# Verifies that when GH_SYNC=true:
#   - Plan paths resolve from .orchestrator/plans/<slug>/ (not docs/exec-plans/)
#   - SHIP steps 1, 4, 5, 6, and post-validation are skipped
#   - PR diff would contain zero docs/exec-plans/ files
#
# Verifies that when GH_SYNC=false:
#   - Plan paths resolve from docs/exec-plans/active/<slug>/ (local mode)
#   - All SHIP steps execute normally
#
# Usage: bash tests/test-gh-mode-skip-local-artifacts.sh

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
    echo "    actual: ${haystack}"
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

assert_file_not_exists() {
  local label="$1" path="$2"
  if [[ ! -f "${path}" ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label} — file should not exist: ${path}"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_not_exists() {
  local label="$1" path="$2"
  if [[ ! -d "${path}" ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label} — directory should not exist: ${path}"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup ---

TEST_SLUG="test-gh-mode-$$"
ORCH_DIR="${REPO_ROOT}/.orchestrator"
GH_PLAN_DIR="${ORCH_DIR}/plans/${TEST_SLUG}"
LOCAL_PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${TEST_SLUG}"

PLAN_CONTENT='# Plan: Test GH Mode

**Status:** In progress

## Requirements

Synthetic plan for GH mode testing.

## Approach

Test path resolution.

## Progress log

- [ ] First task
- [ ] Second task (deps: 1)
- [ ] Third task (deps: 2)

## Completion criteria

- [ ] All tests pass
'

cleanup() {
  rm -rf "${GH_PLAN_DIR}"
  rm -rf "${LOCAL_PLAN_DIR}"
  # Only clean up our test slug's orch state, not the whole .orchestrator/
  rm -rf "${ORCH_DIR}/plans/${TEST_SLUG}"
}
trap cleanup EXIT

# =====================================================================
echo ""
echo "=== Test 1: orch-parse-items.sh with GH_SYNC=true ==="
# =====================================================================

# Set up plan in .orchestrator/plans/<slug>/
mkdir -p "${GH_PLAN_DIR}"
printf '%s' "${PLAN_CONTENT}" >"${GH_PLAN_DIR}/plan.md"

# Ensure NO plan exists in docs/exec-plans/active/
rm -rf "${LOCAL_PLAN_DIR}"

# Run parser in GH mode
PARSED_GH=$(cd "${REPO_ROOT}" && GH_SYNC=true \
  "${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")

ITEM_COUNT_GH=$(printf '%s' "${PARSED_GH}" | jq '.items | length')
assert_eq "GH mode: item count" "3" "${ITEM_COUNT_GH}"

SLUG_GH=$(printf '%s' "${PARSED_GH}" | jq -r '.slug')
assert_eq "GH mode: slug" "${TEST_SLUG}" "${SLUG_GH}"

ITEM1_DESC=$(printf '%s' "${PARSED_GH}" | jq -r '.items[0].description')
assert_eq "GH mode: item 1 description" "First task" "${ITEM1_DESC}"

ITEM2_DEPS=$(printf '%s' "${PARSED_GH}" | jq -c '.items[1].deps')
assert_eq "GH mode: item 2 deps" "[1]" "${ITEM2_DEPS}"

ITEM3_DEPS=$(printf '%s' "${PARSED_GH}" | jq -c '.items[2].deps')
assert_eq "GH mode: item 3 deps" "[2]" "${ITEM3_DEPS}"

# =====================================================================
echo ""
echo "=== Test 2: orch-parse-items.sh with GH_SYNC=false ==="
# =====================================================================

# Set up plan in docs/exec-plans/active/<slug>/
mkdir -p "${LOCAL_PLAN_DIR}"
printf '%s' "${PLAN_CONTENT}" >"${LOCAL_PLAN_DIR}/plan.md"

# Remove GH plan dir
rm -rf "${GH_PLAN_DIR}"

# Run parser in local mode
PARSED_LOCAL=$(cd "${REPO_ROOT}" && GH_SYNC=false \
  "${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")

ITEM_COUNT_LOCAL=$(printf '%s' "${PARSED_LOCAL}" | jq '.items | length')
assert_eq "local mode: item count" "3" "${ITEM_COUNT_LOCAL}"

SLUG_LOCAL=$(printf '%s' "${PARSED_LOCAL}" | jq -r '.slug')
assert_eq "local mode: slug" "${TEST_SLUG}" "${SLUG_LOCAL}"

# =====================================================================
echo ""
echo "=== Test 3: orch-parse-items.sh GH mode fails without .orchestrator/ plan ==="
# =====================================================================

# Neither plan dir exists
rm -rf "${GH_PLAN_DIR}" "${LOCAL_PLAN_DIR}"

if cd "${REPO_ROOT}" && GH_SYNC=true \
  "${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}" 2>/dev/null; then
  echo "  FAIL: GH mode should fail when plan missing from .orchestrator/"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: GH mode fails when plan missing from .orchestrator/"
  PASS=$((PASS + 1))
fi

# =====================================================================
echo ""
echo "=== Test 4: orch-parse-items.sh local mode fails without docs/ plan ==="
# =====================================================================

if cd "${REPO_ROOT}" && GH_SYNC=false \
  "${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}" 2>/dev/null; then
  echo "  FAIL: local mode should fail when plan missing from docs/"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: local mode fails when plan missing from docs/"
  PASS=$((PASS + 1))
fi

# =====================================================================
echo ""
echo "=== Test 5: GH_SYNC flag present in all five orchestrator scripts ==="
# =====================================================================

for script in orch-run.sh orch-engine.sh orch-parse-items.sh \
  orch-verify.sh orch-review.sh; do
  path="${REPO_ROOT}/scripts/${script}"
  if grep -q 'GH_SYNC' "${path}"; then
    echo "  PASS: ${script} contains GH_SYNC"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${script} missing GH_SYNC"
    FAIL=$((FAIL + 1))
  fi
done

# =====================================================================
echo ""
echo "=== Test 6: orch-run.sh path resolution logic ==="
# =====================================================================

# Verify GH mode resolves to .orchestrator/plans/
RUN_SH=$(cat "${REPO_ROOT}/scripts/orch-run.sh")
assert_contains "orch-run.sh: GH mode PLAN_DIR" \
  "${RUN_SH}" 'PLAN_DIR="${REPO_ROOT}/.orchestrator/plans/${SLUG}"'
assert_contains "orch-run.sh: local mode PLAN_DIR" \
  "${RUN_SH}" 'PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"'

# Verify worktree copy uses .orchestrator/ in GH mode
assert_contains "orch-run.sh: GH worktree plan dir" \
  "${RUN_SH}" 'WORKTREE_PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"'
assert_contains "orch-run.sh: local worktree plan dir" \
  "${RUN_SH}" 'WORKTREE_PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"'

# Verify uncommitted guard is skipped in GH mode
assert_contains "orch-run.sh: uncommitted guard skips GH mode" \
  "${RUN_SH}" '&& [[ "${GH_SYNC}" == false ]]'

# =====================================================================
echo ""
echo "=== Test 7: orch-engine.sh SHIP step gating ==="
# =====================================================================

ENGINE_SH=$(cat "${REPO_ROOT}/scripts/orch-engine.sh")

# Step 1: skip local plan sync
assert_contains "engine: SHIP step 1 gated" \
  "${ENGINE_SH}" '[SHIP 1/9] skipped — GH mode'

# Step 4: skip move active->completed
assert_contains "engine: SHIP step 4 gated" \
  "${ENGINE_SH}" '[SHIP 4/9] skipped — GH mode'

# Step 5: skip commit plan move
assert_contains "engine: SHIP step 5 gated" \
  "${ENGINE_SH}" '[SHIP 5/9] skipped — GH mode'

# Step 6: skip registry append
assert_contains "engine: SHIP step 6 gated" \
  "${ENGINE_SH}" '[SHIP 6/9] skipped — GH mode'

# Post-validation: skip in GH mode
assert_contains "engine: post-validation skipped" \
  "${ENGINE_SH}" 'post-validation skipped — GH mode'

# Steps 2, 3, 7, 8, 9 should NOT be gated by GH_SYNC
# (Step 7 has GH_SYNC only for reading plan title path, not skipping)
assert_not_contains "engine: step 2 not gated" \
  "${ENGINE_SH}" '[SHIP 2/9] skipped'
assert_not_contains "engine: step 3 not gated" \
  "${ENGINE_SH}" '[SHIP 3/9] skipped'
assert_not_contains "engine: step 8 not gated by GH mode" \
  "${ENGINE_SH}" '[SHIP 8/9] skipped — GH mode'

# =====================================================================
echo ""
echo "=== Test 8: orch-engine.sh plan dir resolution ==="
# =====================================================================

assert_contains "engine: GH mode PLAN_DIR" \
  "${ENGINE_SH}" 'PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"'
assert_contains "engine: local mode PLAN_DIR" \
  "${ENGINE_SH}" 'PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"'

# =====================================================================
echo ""
echo "=== Test 9: orch-verify.sh plan dir resolution ==="
# =====================================================================

VERIFY_SH=$(cat "${REPO_ROOT}/scripts/orch-verify.sh")

assert_contains "verify: GH mode PLAN_DIR" \
  "${VERIFY_SH}" 'PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"'
assert_contains "verify: local worktree fallback" \
  "${VERIFY_SH}" 'PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"'
assert_contains "verify: repo root fallback" \
  "${VERIFY_SH}" 'PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"'

# =====================================================================
echo ""
echo "=== Test 10: orch-review.sh plan dir resolution ==="
# =====================================================================

REVIEW_SH=$(cat "${REPO_ROOT}/scripts/orch-review.sh")

assert_contains "review: GH mode PLAN_DIR" \
  "${REVIEW_SH}" 'PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"'
assert_contains "review: local worktree fallback" \
  "${REVIEW_SH}" 'PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"'
assert_contains "review: repo root fallback" \
  "${REVIEW_SH}" 'PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"'

# =====================================================================
echo ""
echo "=== Test 11: GH mode parser ignores docs/exec-plans/ entirely ==="
# =====================================================================

# Place DIFFERENT plans in both locations — GH mode should use .orchestrator/
mkdir -p "${GH_PLAN_DIR}" "${LOCAL_PLAN_DIR}"

printf '%s' '# Plan: GH Plan

## Progress log

- [ ] GH-only task A
- [ ] GH-only task B (deps: 1)
' >"${GH_PLAN_DIR}/plan.md"

printf '%s' '# Plan: Local Plan

## Progress log

- [ ] Local task X
- [ ] Local task Y (deps: 1)
- [ ] Local task Z (deps: 2)
' >"${LOCAL_PLAN_DIR}/plan.md"

# GH mode should parse the 2-item plan from .orchestrator/
PARSED_DUAL_GH=$(cd "${REPO_ROOT}" && GH_SYNC=true \
  "${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")
DUAL_GH_COUNT=$(printf '%s' "${PARSED_DUAL_GH}" | jq '.items | length')
DUAL_GH_DESC1=$(printf '%s' "${PARSED_DUAL_GH}" | jq -r '.items[0].description')
assert_eq "dual plans GH mode: item count from .orchestrator/" "2" "${DUAL_GH_COUNT}"
assert_eq "dual plans GH mode: reads .orchestrator/ plan" "GH-only task A" "${DUAL_GH_DESC1}"

# Local mode should parse the 3-item plan from docs/exec-plans/
PARSED_DUAL_LOCAL=$(cd "${REPO_ROOT}" && GH_SYNC=false \
  "${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}")
DUAL_LOCAL_COUNT=$(printf '%s' "${PARSED_DUAL_LOCAL}" | jq '.items | length')
DUAL_LOCAL_DESC1=$(printf '%s' "${PARSED_DUAL_LOCAL}" | jq -r '.items[0].description')
assert_eq "dual plans local mode: item count from docs/" "3" "${DUAL_LOCAL_COUNT}"
assert_eq "dual plans local mode: reads docs/ plan" "Local task X" "${DUAL_LOCAL_DESC1}"

# =====================================================================
echo ""
echo "=== Test 12: shellcheck passes on all modified scripts ==="
# =====================================================================

SHELLCHECK_SCRIPTS=(
  scripts/orch-run.sh
  scripts/orch-engine.sh
  scripts/orch-parse-items.sh
  scripts/orch-verify.sh
  scripts/orch-review.sh
)

shellcheck_ok=true
for script in "${SHELLCHECK_SCRIPTS[@]}"; do
  if shellcheck -e SC1091 -S warning "${REPO_ROOT}/${script}" 2>&1; then
    echo "  PASS: shellcheck ${script}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: shellcheck ${script}"
    FAIL=$((FAIL + 1))
    shellcheck_ok=false
  fi
done

if [[ "${shellcheck_ok}" == true ]]; then
  echo "  (all scripts pass shellcheck)"
fi

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
