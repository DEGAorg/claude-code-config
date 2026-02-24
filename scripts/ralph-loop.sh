#!/usr/bin/env bash
# Ralph Loop orchestrator.
# Spawns worker and reviewer agents in sequence until the reviewer outputs SHIP
# and the repo health check passes, or max_iterations is reached.
#
# Usage: bash scripts/ralph-loop.sh <task-slug>
# Example: bash scripts/ralph-loop.sh ralph-loop
#
# The task-slug must match a directory in docs/exec-plans/active/.

set -euo pipefail

TASK_SLUG="${1:-}"
if [[ -z "${TASK_SLUG}" ]]; then
  echo "error: usage: bash scripts/ralph-loop.sh <task-slug>" >&2
  echo "  task-slug must match a directory in docs/exec-plans/active/" >&2
  exit 1
fi

TASK_DIR="docs/exec-plans/active/${TASK_SLUG}"
if [[ ! -f "${TASK_DIR}/plan.md" ]]; then
  echo "error: no plan found at ${TASK_DIR}/plan.md" >&2
  exit 1
fi

# Read config from ralph.yaml
MAX_ITERATIONS=$(grep 'max_iterations:' ralph.yaml | awk '{print $2}' | tr -d ' ')
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
WORKER_PROMPT="scripts/ralph-worker-prompt.md"
REVIEWER_PROMPT="scripts/ralph-reviewer-prompt.md"

if [[ ! -f "${WORKER_PROMPT}" || ! -f "${REVIEWER_PROMPT}" ]]; then
  echo "error: prompt templates not found — run from repo root" >&2
  exit 1
fi

echo "ralph-loop: task '${TASK_SLUG}' — max ${MAX_ITERATIONS} iterations"
echo "  plan: ${TASK_DIR}/plan.md"
echo ""

for i in $(seq 1 "${MAX_ITERATIONS}"); do
  echo "=== Iteration ${i}/${MAX_ITERATIONS} ==="

  # --- Worker phase ---
  echo "→ worker: starting..."
  WORKER_CONTEXT=$(sed "s|{TASK_DIR}|${TASK_DIR}|g" "${WORKER_PROMPT}")
  env -u CLAUDECODE claude -p --dangerously-skip-permissions "${WORKER_CONTEXT}"
  echo "→ worker: done"

  # --- Reviewer phase ---
  echo "→ reviewer: evaluating..."
  REVIEWER_CONTEXT=$(sed "s|{TASK_DIR}|${TASK_DIR}|g" "${REVIEWER_PROMPT}")
  env -u CLAUDECODE claude -p --dangerously-skip-permissions "${REVIEWER_CONTEXT}"
  echo "→ reviewer: done"

  # --- Read reviewer decision ---
  RESULT_FILE="${TASK_DIR}/review-result.txt"
  if [[ ! -f "${RESULT_FILE}" ]]; then
    echo "✗ reviewer did not write review-result.txt — treating as REVISE"
    echo ""
    continue
  fi

  RESULT=$(head -1 "${RESULT_FILE}" | tr -d '[:space:]')

  if [[ "${RESULT}" == "SHIP" ]]; then
    echo "→ reviewer: SHIP"
    echo "→ running repo health check..."
    if bash scripts/ralph-check.sh; then
      echo "→ archiving exec-plan to completed/..."
      mv "${TASK_DIR}" "docs/exec-plans/completed/${TASK_SLUG}"
      echo "→ committing..."
      git add -A
      git commit -m "$(
        cat <<EOF
complete ${TASK_SLUG} (ralph loop, iteration ${i})

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
      )"
      echo ""
      echo "ralph-loop: DONE — shipped after ${i} iteration(s)."
      exit 0
    else
      echo "→ health check failed — repo not clean, continuing"
      rm -f "${RESULT_FILE}"
    fi
  elif [[ "${RESULT}" == "BLOCKED" ]]; then
    echo "→ reviewer: BLOCKED — human action required"
    FEEDBACK_FILE="${TASK_DIR}/review-feedback.txt"
    if [[ -f "${FEEDBACK_FILE}" ]]; then
      echo "--- blocked ---"
      cat "${FEEDBACK_FILE}"
      echo "---------------"
    fi
    echo ""
    echo "ralph-loop: STOPPED — waiting for human. Fix the blocker, then re-run:"
    echo "  bash scripts/ralph-loop.sh ${TASK_SLUG}"
    exit 2
  else
    echo "→ reviewer: REVISE"
    FEEDBACK_FILE="${TASK_DIR}/review-feedback.txt"
    if [[ -f "${FEEDBACK_FILE}" ]]; then
      echo "--- feedback ---"
      cat "${FEEDBACK_FILE}"
      echo "----------------"
    fi
  fi

  echo ""
done

echo ""
echo "ralph-loop: max iterations (${MAX_ITERATIONS}) reached without SHIP."
RESULT_FILE="${TASK_DIR}/review-result.txt"
if [[ -f "${RESULT_FILE}" ]]; then
  echo "  last result: $(cat "${RESULT_FILE}")"
fi
exit 1
