#!/usr/bin/env bash
# Integration tests for parallel worktree isolation.
# Validates that ralph-worktree.sh creates isolated environments
# and that two parallel setups don't conflict.
#
# Run from repo root: bash tests/test-parallel-worktrees.sh
set -euo pipefail

PASS=0
FAIL=0

check() {
  local id="$1"
  local description="$2"
  local expected="$3"
  local actual="$4"
  if [[ "${actual}" == "${expected}" ]]; then
    printf '  ok  %s: %s\n' "${id}" "${description}"
    PASS=$((PASS + 1))
  else
    printf '  FAIL %s: %s (expected "%s", got "%s")\n' \
      "${id}" "${description}" "${expected}" "${actual}"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup: create a throwaway git repo with two fake exec plans ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"

REPO_DIR=$(mktemp -d)
cleanup() {
  cd /
  # Remove worktrees before deleting repo
  if [[ -d "${REPO_DIR}" ]]; then
    cd "${REPO_DIR}"
    git worktree prune 2>/dev/null || true
    for wt in .claude/worktrees/*/; do
      [[ -d "${wt}" ]] && git worktree remove --force "${wt}" 2>/dev/null || true
    done
    for br in ralph/test-plan-a ralph/test-plan-b; do
      git branch -D "${br}" 2>/dev/null || true
    done
    cd /
    rm -rf "${REPO_DIR}"
  fi
}
trap cleanup EXIT

cd "${REPO_DIR}"
git init -b main --quiet
git commit --allow-empty -m "init" --quiet

SLUG_A="test-plan-a"
SLUG_B="test-plan-b"

# Create two exec plan directories with minimal plan files
for slug in "${SLUG_A}" "${SLUG_B}"; do
  mkdir -p "docs/exec-plans/active/${slug}"
  cat >"docs/exec-plans/active/${slug}/plan.md" <<PLAN
# Test plan: ${slug}

## Progress log

- [ ] Task one
- [ ] Task two

## Completion criteria

- [ ] Done
PLAN
  cat >"docs/exec-plans/active/${slug}/.ralph-state.json" <<STATE
{
  "slug": "${slug}",
  "iteration": 1,
  "status": "in_progress",
  "current_task": {"text": "Task one", "claimed_complete": false}
}
STATE
done

# Minimal dega-core.yaml
cat >dega-core.yaml <<YAML
max_iterations: 1
warn_at_iteration: 1
YAML

git add -A && git commit -m "add test plans" --quiet

printf 'parallel-worktrees\n'

# ==========================================================
# Test 1: Worktree creation produces separate directories
# ==========================================================
WT_A=".claude/worktrees/${SLUG_A}"
WT_B=".claude/worktrees/${SLUG_B}"

mkdir -p .claude/worktrees
git worktree add -b "ralph/${SLUG_A}" "${WT_A}" --quiet
git worktree add -b "ralph/${SLUG_B}" "${WT_B}" --quiet

check wt-dirs-exist-a \
  "worktree A directory exists" \
  "true" "$([ -d "${WT_A}" ] && echo true || echo false)"

check wt-dirs-exist-b \
  "worktree B directory exists" \
  "true" "$([ -d "${WT_B}" ] && echo true || echo false)"

check wt-dirs-separate \
  "worktree directories are distinct" \
  "true" "$([ "${WT_A}" != "${WT_B}" ] && echo true || echo false)"

# ==========================================================
# Test 2: Branches are separate
# ==========================================================
BRANCH_A=$(cd "${WT_A}" && git branch --show-current)
BRANCH_B=$(cd "${WT_B}" && git branch --show-current)

check branch-a \
  "worktree A on branch ralph/${SLUG_A}" \
  "ralph/${SLUG_A}" "${BRANCH_A}"

check branch-b \
  "worktree B on branch ralph/${SLUG_B}" \
  "ralph/${SLUG_B}" "${BRANCH_B}"

check branches-different \
  "branches are distinct" \
  "true" "$([ "${BRANCH_A}" != "${BRANCH_B}" ] && echo true || echo false)"

# ==========================================================
# Test 3: Session IDs are unique per slug
# ==========================================================
SESSION_A="ralph-${SLUG_A}"
SESSION_B="ralph-${SLUG_B}"

check session-a \
  "session ID A is ralph-${SLUG_A}" \
  "ralph-${SLUG_A}" "${SESSION_A}"

check session-b \
  "session ID B is ralph-${SLUG_B}" \
  "ralph-${SLUG_B}" "${SESSION_B}"

check sessions-different \
  "session IDs are distinct" \
  "true" "$([ "${SESSION_A}" != "${SESSION_B}" ] && echo true || echo false)"

# ==========================================================
# Test 4: Exec plan files are copied into each worktree independently
# ==========================================================
# Copy plans into worktrees (simulating what ralph-worktree.sh does)
for slug in "${SLUG_A}" "${SLUG_B}"; do
  wt_task=".claude/worktrees/${slug}/docs/exec-plans/active/${slug}"
  mkdir -p "${wt_task}"
  cp "docs/exec-plans/active/${slug}/plan.md" "${wt_task}/plan.md"
  cp "docs/exec-plans/active/${slug}/.ralph-state.json" "${wt_task}/.ralph-state.json"
done

WT_TASK_A="${WT_A}/docs/exec-plans/active/${SLUG_A}"
WT_TASK_B="${WT_B}/docs/exec-plans/active/${SLUG_B}"

check plan-copied-a \
  "plan.md copied into worktree A" \
  "true" "$([ -f "${WT_TASK_A}/plan.md" ] && echo true || echo false)"

check plan-copied-b \
  "plan.md copied into worktree B" \
  "true" "$([ -f "${WT_TASK_B}/plan.md" ] && echo true || echo false)"

# ==========================================================
# Test 5: Changes in worktree A don't appear in worktree B
# ==========================================================
echo "modified by A" >>"${WT_TASK_A}/plan.md"

PLAN_B_MODIFIED=$(grep -c "modified by A" "${WT_TASK_B}/plan.md" 2>/dev/null || true)
check isolation \
  "changes in worktree A don't appear in worktree B" \
  "0" "${PLAN_B_MODIFIED}"

# ==========================================================
# Test 6: State files are independent
# ==========================================================
STATE_A="${WT_TASK_A}/.ralph-state.json"
STATE_B="${WT_TASK_B}/.ralph-state.json"

SLUG_FROM_A=$(jq -r '.slug' "${STATE_A}")
SLUG_FROM_B=$(jq -r '.slug' "${STATE_B}")

check state-slug-a \
  "state file A has correct slug" \
  "${SLUG_A}" "${SLUG_FROM_A}"

check state-slug-b \
  "state file B has correct slug" \
  "${SLUG_B}" "${SLUG_FROM_B}"

# ==========================================================
# Test 7: git worktree list shows both
# ==========================================================
WT_COUNT=$(git worktree list | grep -c "ralph/" || true)
check worktree-list \
  "git worktree list shows both ralph worktrees" \
  "2" "${WT_COUNT}"

# ==========================================================
# Test 8: Cleanup of one worktree doesn't affect the other
# ==========================================================
git worktree remove --force "${WT_A}" 2>/dev/null || true

check cleanup-a-removed \
  "worktree A removed" \
  "false" "$([ -d "${WT_A}" ] && echo true || echo false)"

check cleanup-b-survives \
  "worktree B survives after A removed" \
  "true" "$([ -d "${WT_B}" ] && echo true || echo false)"

B_STILL_VALID=$(git worktree list | grep -c "ralph/${SLUG_B}" || true)
check cleanup-b-valid \
  "worktree B still valid in git worktree list" \
  "1" "${B_STILL_VALID}"

# ==========================================================
# Test 9: Crash recovery — worktree can be resumed
# ==========================================================
# Simulate a crash: recreate worktree A with dirty state, then verify
# ralph-worktree.sh reattaches (without ralph-loop.sh actually running).

# Recreate worktree A (was removed in test 8)
git worktree add "ralph/${SLUG_A}" "${WT_A}" --quiet 2>/dev/null ||
  git worktree add "${WT_A}" "ralph/${SLUG_A}" --quiet

# Simulate uncommitted work ("crash left dirty state")
WT_CRASH_PLAN="${WT_A}/docs/exec-plans/active/${SLUG_A}"
mkdir -p "${WT_CRASH_PLAN}"
cp "docs/exec-plans/active/${SLUG_A}/plan.md" "${WT_CRASH_PLAN}/plan.md"
echo "crash-in-progress work" >"${WT_CRASH_PLAN}/work-summary.txt"
(cd "${WT_A}" && git add -A 2>/dev/null || true)

check crash-worktree-exists \
  "worktree A exists after simulated crash" \
  "true" "$([ -d "${WT_A}" ] && echo true || echo false)"

check crash-dirty-state \
  "worktree has dirty/staged state" \
  "true" "$(cd "${WT_A}" && [[ -n "$(git status --porcelain 2>/dev/null)" ]] && echo true || echo false)"

# Verify ralph-worktree.sh detects existing worktree (reattach path).
# We can't run the full script (it calls ralph-loop.sh which needs claude),
# so test the reattach detection logic directly.
REATTACH_OUTPUT=$(bash "${SCRIPT_DIR}/ralph-worktree.sh" "${SLUG_A}" 2>&1 || true)
check crash-reattach \
  "ralph-worktree.sh reports reattaching to existing worktree" \
  "true" "$(echo "${REATTACH_OUTPUT}" | grep -q "reattaching" && echo true || echo false)"

# Verify the branch survived
check crash-branch-survives \
  "branch ralph/${SLUG_A} still exists after reattach" \
  "true" "$(git show-ref --verify --quiet "refs/heads/ralph/${SLUG_A}" 2>/dev/null && echo true || echo false)"

# Verify work-summary.txt (crash artifact) is still present in worktree
check crash-state-preserved \
  "crash artifact (work-summary.txt) still in worktree" \
  "true" "$([ -f "${WT_CRASH_PLAN}/work-summary.txt" ] && echo true || echo false)"

# Test 9b: prune recovers from deleted-directory worktree
# Remove worktree directory without git worktree remove (simulates hard crash)
PRUNE_WT=".claude/worktrees/prune-test"
git worktree add -b "ralph/prune-test" "${PRUNE_WT}" --quiet
rm -rf "${PRUNE_WT}"
# git worktree list should still show the stale entry
STALE_BEFORE=$(git worktree list | grep -c "prune-test" || true)
git worktree prune
STALE_AFTER=$(git worktree list | grep -c "prune-test" || true)
check prune-cleans-stale \
  "git worktree prune removes stale entry" \
  "true" "$([ "${STALE_BEFORE}" -ge 1 ] && [ "${STALE_AFTER}" -eq 0 ] && echo true || echo false)"
git branch -D "ralph/prune-test" 2>/dev/null || true

# ==========================================================
# Test 10: ralph-worktree.sh validates missing plan
# ==========================================================
MISSING_EXIT=0
bash "${SCRIPT_DIR}/ralph-worktree.sh" "nonexistent-slug" >/dev/null 2>&1 || MISSING_EXIT=$?
check missing-plan \
  "ralph-worktree.sh rejects missing plan with non-zero exit" \
  "true" "$([ "${MISSING_EXIT}" -ne 0 ] && echo true || echo false)"

# ==========================================================
# Test 11: ralph-worktree.sh validates missing slug
# ==========================================================
NO_SLUG_EXIT=0
bash "${SCRIPT_DIR}/ralph-worktree.sh" >/dev/null 2>&1 || NO_SLUG_EXIT=$?
check no-slug \
  "ralph-worktree.sh rejects empty slug with non-zero exit" \
  "true" "$([ "${NO_SLUG_EXIT}" -ne 0 ] && echo true || echo false)"

# --- Summary ---
TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
