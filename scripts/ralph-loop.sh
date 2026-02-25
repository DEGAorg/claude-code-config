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
STATE_FILE="${TASK_DIR}/.ralph-state.json"

# Read config from ralph.yaml
MAX_ITERATIONS=$(grep 'max_iterations:' ralph.yaml | awk '{print $2}' | tr -d ' ')
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
WARN_AT=$(grep 'warn_at_iteration:' ralph.yaml | awk '{print $2}' | tr -d ' ')
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

  # --- Budget warning (fires once when approaching limit) ---
  if [[ -n "${WARN_AT}" && ${i} -ge ${WARN_AT} ]]; then
    WARNED=$(jq -r '.budget.warned // false' "${STATE_FILE}" 2>/dev/null || echo "false")
    if [[ "${WARNED}" == "false" ]]; then
      echo "⚠ ralph-loop: iteration ${i} of ${MAX_ITERATIONS} — approaching budget limit"
      echo "  Press Ctrl-C to stop. State is saved in ${STATE_FILE}"
      jq '.budget.warned = true' "${STATE_FILE}" >/tmp/ralph_w.tmp &&
        mv /tmp/ralph_w.tmp "${STATE_FILE}"
    fi
  fi

  # Read cross-iteration values before overwriting state
  PREV_STAG=0
  PREV_DIFF_HASH=""
  PREV_WARNED=false
  if [[ -f "${STATE_FILE}" ]]; then
    PREV_STAG=$(jq -r '.stagnation_count // 0' "${STATE_FILE}")
    PREV_DIFF_HASH=$(jq -r '.last_diff_hash // ""' "${STATE_FILE}")
    PREV_WARNED=$(jq -r '.budget.warned // false' "${STATE_FILE}")
  fi

  # --- State init for this iteration ---
  jq -n \
    --arg slug "${TASK_SLUG}" \
    --argjson iter "${i}" \
    --argjson stag "${PREV_STAG}" \
    --arg diff_hash "${PREV_DIFF_HASH}" \
    --argjson warned "${PREV_WARNED}" \
    --argjson max "${MAX_ITERATIONS}" \
    --argjson warn_at "${WARN_AT:-2}" \
    '{
      "slug": $slug,
      "iteration": $iter,
      "status": "in_progress",
      "current_task": {"text": "", "claimed_complete": false},
      "last_result": null,
      "iterations": [],
      "stagnation_count": $stag,
      "last_diff_hash": $diff_hash,
      "budget": {
        "iterations_used": $iter,
        "iterations_max": $max,
        "warn_at_iteration": $warn_at,
        "warned": $warned
      }
    }' >"${STATE_FILE}"

  # --- Iteration archive (copy previous output before worker starts) ---
  if [[ $i -gt 1 ]]; then
    ITER_DIR="${TASK_DIR}/iterations/$(printf '%03d' $((i - 1)))"
    mkdir -p "${ITER_DIR}"
    for f in work-summary.txt review-result.txt review-feedback.txt; do
      [[ -f "${TASK_DIR}/$f" ]] && cp "${TASK_DIR}/$f" "${ITER_DIR}/$f"
    done
  fi

  # --- Worker phase (per-item loop) ---
  SESSION_ID=""
  ITEM_NUM=0
  echo "→ worker: starting per-item loop..."
  while bash scripts/plan-advance.sh "${TASK_DIR}/plan.md" "${STATE_FILE}"; do
    ITEM_NUM=$((ITEM_NUM + 1))
    CURRENT_TASK=$(jq -r '.current_task.text' "${STATE_FILE}")
    echo "→ worker item ${ITEM_NUM}: ${CURRENT_TASK}"
    WORKER_CONTEXT=$(sed \
      -e "s|{TASK_DIR}|${TASK_DIR}|g" \
      -e "s|{STATE_FILE}|${STATE_FILE}|g" \
      "${WORKER_PROMPT}")
    if [[ -z "${SESSION_ID}" ]]; then
      RAW=$(env -u CLAUDECODE claude -p --dangerously-skip-permissions \
        --output-format json "${WORKER_CONTEXT}")
      SESSION_ID=$(printf '%s' "${RAW}" | jq -r '.session_id // empty' 2>/dev/null || true)
      if [[ -z "${SESSION_ID}" ]]; then
        echo "  warning: session_id not captured — per-item context resume disabled"
      fi
    else
      env -u CLAUDECODE claude -p --dangerously-skip-permissions \
        --resume "${SESSION_ID}" "${WORKER_CONTEXT}"
    fi
  done
  # All items processed — mark last task claimed so health check passes
  jq '.current_task.claimed_complete = true' "${STATE_FILE}" >/tmp/ralph_c.tmp &&
    mv /tmp/ralph_c.tmp "${STATE_FILE}"
  echo "→ worker: done"

  # --- Stagnation detection ---
  CURRENT_HASH=$(git diff HEAD | shasum -a 256 | cut -d' ' -f1)
  PREV_HASH=$(jq -r '.last_diff_hash // ""' "${STATE_FILE}")
  if [[ "${CURRENT_HASH}" == "${PREV_HASH}" && -n "${PREV_HASH}" ]]; then
    STAG=$(($(jq -r '.stagnation_count // 0' "${STATE_FILE}") + 1))
    jq ".stagnation_count = ${STAG} | .current_task.claimed_complete = true" \
      "${STATE_FILE}" >/tmp/ralph_s.tmp && mv /tmp/ralph_s.tmp "${STATE_FILE}"
    if [[ ${STAG} -ge 2 ]]; then
      echo "ralph-loop: STAGNATED — no file changes in 2 consecutive iterations"
      echo "  Human review required. Re-run after diagnosing the blocker."
      exit 2
    fi
  else
    jq ".stagnation_count = 0 | .last_diff_hash = \"${CURRENT_HASH}\" | .current_task.claimed_complete = true" \
      "${STATE_FILE}" >/tmp/ralph_s.tmp && mv /tmp/ralph_s.tmp "${STATE_FILE}"
  fi

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

  # Update state with reviewer result
  jq --arg result "${RESULT}" '.last_result = $result' \
    "${STATE_FILE}" >"${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "${STATE_FILE}"

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
