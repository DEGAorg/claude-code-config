#!/usr/bin/env bats
# Regression test for the ship hook deletion bug (#227).
#
# The bug: SHIP step 7 committed CHANGELOG.md against REPO_ROOT. When
# REPO_ROOT was behind origin (another PR had merged in the background),
# the commit pinned to a stale local HEAD. Later sync paths could land
# that stale-tree commit on origin, silently deleting files introduced
# by the interim PR.
#
# The fix: SHIP steps 5/6/7 run inside the worktree (on the orch/<slug>
# branch) and use orch_guarded_commit to reject any staged path outside
# the allowlist. This test verifies:
#
#   1. REPO_ROOT's HEAD is untouched by the ship-step commit.
#   2. The worktree commit adds CHANGELOG.md and nothing else.
#   3. Merging the orch branch into origin/main via a three-way merge
#      preserves files added by the interim "other PR" commit.

SCRIPTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../scripts" && pwd)"

setup() {
  TEST_TMPDIR="$(mktemp -d -t orch-ship-XXXXXX)"
  ORIGIN_DIR="${TEST_TMPDIR}/origin.git"
  REPO_ROOT="${TEST_TMPDIR}/repo"
  SLUG="stale-base"

  git init --quiet --bare --initial-branch=main "${ORIGIN_DIR}"

  # REPO_ROOT: base commit, pushed to origin/main.
  git clone --quiet "${ORIGIN_DIR}" "${REPO_ROOT}"
  git -C "${REPO_ROOT}" config user.email "test@example.com"
  git -C "${REPO_ROOT}" config user.name "Test"
  git -C "${REPO_ROOT}" config commit.gpgsign false
  echo "base" >"${REPO_ROOT}/README.md"
  git -C "${REPO_ROOT}" add README.md
  git -C "${REPO_ROOT}" commit --quiet --no-verify -m "base"
  git -C "${REPO_ROOT}" push --quiet origin main

  # "Other PR" merges into origin/main adding docs/exec-plans/completed/plan-a.
  # REPO_ROOT does not fetch — it stays on the stale base.
  OTHER_DIR="${TEST_TMPDIR}/other"
  git clone --quiet "${ORIGIN_DIR}" "${OTHER_DIR}"
  git -C "${OTHER_DIR}" config user.email "test@example.com"
  git -C "${OTHER_DIR}" config user.name "Test"
  git -C "${OTHER_DIR}" config commit.gpgsign false
  mkdir -p "${OTHER_DIR}/docs/exec-plans/completed/plan-a"
  echo "# Plan A" >"${OTHER_DIR}/docs/exec-plans/completed/plan-a/plan.md"
  git -C "${OTHER_DIR}" add docs/exec-plans/completed/plan-a/plan.md
  git -C "${OTHER_DIR}" commit --quiet --no-verify -m "add plan-a"
  git -C "${OTHER_DIR}" push --quiet origin main

  # Create an orch worktree forked from REPO_ROOT's stale HEAD. The
  # worktree is placed outside REPO_ROOT so it does not appear as an
  # untracked directory in REPO_ROOT's working tree.
  ORCH_STATE_DIR="${TEST_TMPDIR}/orchestrator"
  WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"
  mkdir -p "${ORCH_STATE_DIR}/worktrees"
  git -C "${REPO_ROOT}" worktree add --quiet -b "orch/${SLUG}" \
    "${WORKTREE_DIR}" HEAD
  git -C "${WORKTREE_DIR}" config user.email "test@example.com"
  git -C "${WORKTREE_DIR}" config user.name "Test"
  git -C "${WORKTREE_DIR}" config commit.gpgsign false

  export ORCH_REPO_ROOT="${REPO_ROOT}"
  export ORCH_STATE_DIR

  # shellcheck source=/dev/null
  source "${SCRIPTS_DIR}/orch-state.sh"
}

teardown() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR}" ]]; then
    rm -rf "${TEST_TMPDIR}"
  fi
}

@test "ship step 7 commits in worktree only and preserves files added on origin" {
  local repo_head_before
  repo_head_before=$(git -C "${REPO_ROOT}" rev-parse HEAD)

  # Simulate SHIP step 7: append CHANGELOG relative to the worktree and
  # commit inside the worktree via the guarded helper.
  ORCH_REPO_ROOT="${WORKTREE_DIR}" \
    orch_changelog_append "${SLUG}" "Fix ship hook deletion" "Fixed"

  [ -f "${WORKTREE_DIR}/CHANGELOG.md" ]

  git -C "${WORKTREE_DIR}" add CHANGELOG.md
  run orch_guarded_commit "${WORKTREE_DIR}" \
    "orch: update changelog for ${SLUG}" "CHANGELOG.md"
  [ "${status}" -eq 0 ]

  # REPO_ROOT's HEAD must be untouched — no SHIP-step commit lands there.
  local repo_head_after
  repo_head_after=$(git -C "${REPO_ROOT}" rev-parse HEAD)
  [ "${repo_head_before}" = "${repo_head_after}" ]

  # REPO_ROOT's working tree must have no staged or unstaged changes.
  [ -z "$(git -C "${REPO_ROOT}" status --porcelain)" ]

  # The worktree advanced by exactly one commit whose diff adds CHANGELOG.md
  # and touches nothing else (no deletions, no unrelated paths).
  local wt_commits
  wt_commits=$(git -C "${WORKTREE_DIR}" rev-list \
    --count "${repo_head_before}..HEAD")
  [ "${wt_commits}" -eq 1 ]

  local name_status
  name_status=$(git -C "${WORKTREE_DIR}" diff --name-status HEAD~1 HEAD)
  [ "${name_status}" = "A"$'\t'"CHANGELOG.md" ]

  # End-to-end: merging orch/<slug> into origin/main via a three-way merge
  # must not drop plan-a.md (the file the interim PR added to origin).
  git -C "${WORKTREE_DIR}" push --quiet origin "orch/${SLUG}"

  local MERGE_DIR="${TEST_TMPDIR}/merge"
  git clone --quiet "${ORIGIN_DIR}" "${MERGE_DIR}"
  git -C "${MERGE_DIR}" config user.email "test@example.com"
  git -C "${MERGE_DIR}" config user.name "Test"
  git -C "${MERGE_DIR}" config commit.gpgsign false
  git -C "${MERGE_DIR}" fetch --quiet origin "orch/${SLUG}"
  git -C "${MERGE_DIR}" merge --quiet --no-ff --no-edit FETCH_HEAD

  [ -f "${MERGE_DIR}/docs/exec-plans/completed/plan-a/plan.md" ]
  [ -f "${MERGE_DIR}/CHANGELOG.md" ]
}
