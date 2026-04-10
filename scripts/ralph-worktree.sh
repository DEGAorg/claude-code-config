#!/usr/bin/env bash
# Ralph Worktree wrapper.
# Creates a git worktree for isolated parallel execution, runs ralph-loop.sh
# inside it, and cleans up on exit.
#
# Usage: bash ~/.degacore/scripts/ralph-worktree.sh <task-slug>
# Example: bash ~/.degacore/scripts/ralph-worktree.sh 20260306-docs-update
#
# Creates worktree at .claude/worktrees/<slug> on branch ralph/<slug>.
# On SHIP: reports branch name for PR/merge.
# On clean exit (no changes): removes worktree and branch.
# On dirty exit: keeps worktree and reports location.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK_SLUG="${1:-}"
if [[ -z "${TASK_SLUG}" ]]; then
  echo "error: usage: ralph-worktree.sh <task-slug>" >&2
  echo "  task-slug must match a directory in docs/exec-plans/active/" >&2
  exit 1
fi

TASK_DIR="docs/exec-plans/active/${TASK_SLUG}"
if [[ ! -f "${TASK_DIR}/plan.md" ]]; then
  echo "error: no plan found at ${TASK_DIR}/plan.md" >&2
  exit 1
fi

WORKTREE_BASE=".claude/worktrees"
WORKTREE_DIR="${WORKTREE_BASE}/${TASK_SLUG}"
BRANCH="ralph/${TASK_SLUG}"

# Prune stale worktree entries from crashed loops
git worktree prune 2>/dev/null || true

# Create or reattach worktree
if [[ -d "${WORKTREE_DIR}" ]]; then
  echo "ralph-worktree: reattaching to existing worktree at ${WORKTREE_DIR}"
  # Verify it's still a valid worktree
  if ! git worktree list --porcelain | grep -q "worktree.*${TASK_SLUG}"; then
    echo "error: directory ${WORKTREE_DIR} exists but is not a valid worktree" >&2
    echo "  remove it manually or run: git worktree prune" >&2
    exit 1
  fi
elif git show-ref --verify --quiet "refs/heads/${BRANCH}" 2>/dev/null; then
  # Branch exists but worktree doesn't — reattach
  echo "ralph-worktree: branch ${BRANCH} exists, creating worktree from it"
  mkdir -p "${WORKTREE_BASE}"
  git worktree add "${WORKTREE_DIR}" "${BRANCH}"
else
  # Fresh start — create branch and worktree
  echo "ralph-worktree: creating worktree at ${WORKTREE_DIR} on branch ${BRANCH}"
  mkdir -p "${WORKTREE_BASE}"
  git worktree add -b "${BRANCH}" "${WORKTREE_DIR}"
fi

# Copy exec plan into worktree so the worker has a local copy
WORKTREE_TASK_DIR="${WORKTREE_DIR}/${TASK_DIR}"
mkdir -p "${WORKTREE_TASK_DIR}"
# Copy plan and state files; skip iteration archives
for f in plan.md .ralph-state.json review-feedback.txt work-summary.txt context-handoff.txt; do
  [[ -f "${TASK_DIR}/${f}" ]] && cp "${TASK_DIR}/${f}" "${WORKTREE_TASK_DIR}/${f}"
done

echo "ralph-worktree: exec plan copied to ${WORKTREE_TASK_DIR}"
echo ""

# Run the loop inside the worktree
LOOP_EXIT=0
bash "${SCRIPT_DIR}/ralph-loop.sh" --workdir "${WORKTREE_DIR}" "${TASK_SLUG}" || LOOP_EXIT=$?

# Post-loop: handle cleanup based on exit code and worktree state
echo ""
if [[ ${LOOP_EXIT} -eq 0 ]]; then
  # SHIP — sync exec plan state back to main repo
  echo "ralph-worktree: syncing exec plan state back to main repo"
  for f in plan.md .ralph-state.json work-summary.txt context-handoff.txt review-result.txt review-feedback.txt; do
    if [[ -f "${WORKTREE_TASK_DIR}/${f}" ]]; then
      cp "${WORKTREE_TASK_DIR}/${f}" "${TASK_DIR}/${f}"
      echo "  synced: ${f}"
    fi
  done

  echo ""
  echo "ralph-worktree: SHIP on branch ${BRANCH}"
  echo "  worktree: ${WORKTREE_DIR}"
  echo ""
  echo "  Next steps:"
  echo "    1. Review changes: git log ${BRANCH} --oneline"
  echo "    2. Create PR:      gh pr create --head ${BRANCH}"
  echo "    3. After merge:    git worktree remove ${WORKTREE_DIR}"
  exit 0
fi

# Non-zero exit — check if worktree has changes
WORKTREE_DIRTY=false
if (cd "${WORKTREE_DIR}" && [[ -n "$(git status --porcelain 2>/dev/null)" ]]); then
  WORKTREE_DIRTY=true
fi

if [[ "${WORKTREE_DIRTY}" == "true" ]]; then
  echo "ralph-worktree: loop exited (code ${LOOP_EXIT}) with uncommitted changes"
  echo "  worktree kept at: ${WORKTREE_DIR}"
  echo "  branch: ${BRANCH}"
  echo ""
  echo "  To resume: bash ~/.degacore/scripts/ralph-worktree.sh ${TASK_SLUG}"
  echo "  To discard: git worktree remove --force ${WORKTREE_DIR}"
else
  echo "ralph-worktree: loop exited (code ${LOOP_EXIT}) with no changes — cleaning up"
  git worktree remove "${WORKTREE_DIR}" 2>/dev/null || true
  # Only delete branch if it has no commits beyond the base
  MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null |
    sed 's@^refs/remotes/origin/@@' || echo "main")
  if git show-ref --verify --quiet "refs/heads/${BRANCH}" 2>/dev/null; then
    AHEAD=$(git rev-list --count "${MAIN_BRANCH}..${BRANCH}" 2>/dev/null || echo "0")
    if [[ "${AHEAD}" -eq 0 ]]; then
      git branch -d "${BRANCH}" 2>/dev/null || true
      echo "  branch ${BRANCH} deleted (no commits ahead of ${MAIN_BRANCH})"
    else
      echo "  branch ${BRANCH} kept (${AHEAD} commits ahead of ${MAIN_BRANCH})"
    fi
  fi
fi

exit "${LOOP_EXIT}"
