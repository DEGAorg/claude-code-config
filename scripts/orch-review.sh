#!/usr/bin/env bash
# Final per-item review — runs after all items settle (done or failed).
# Spawns reviewer agents in parallel via the Harness capability contract
# (detached background processes + PID files under plans/<slug>/pids/).
# Respects max-workers concurrency. Failed work items are skipped.
# All reviewed items must PASS for SHIP; any failures trigger REVISE.
#
# Usage: scripts/orch-review.sh <slug>
#
# Requires: jq, agent CLI (claude/gemini/codex), orch-state.sh, harness.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"
# shellcheck source=harness/dispatcher.sh
source "${SCRIPT_DIR}/harness/dispatcher.sh"

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
  echo "error: usage: orch-review.sh <slug>" >&2
  exit 1
fi

PROMPT_TEMPLATE="${SCRIPT_DIR}/ralph-item-reviewer-prompt.md"

# GH_SYNC flag — exported by orch-run.sh when github.sync is true
GH_SYNC="${GH_SYNC:-false}"

# Per-plan paths from orch-state.sh helpers
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
DONE_DIR=$(orch_plan_done_dir "${SLUG}")
REVIEW_DIR=$(orch_plan_review_dir "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
PID_DIR="$(orch_plan_dir "${SLUG}")/pids"
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

# Use worktree plan path; in GH mode resolve from .orchestrator/
if [[ "${GH_SYNC}" == true ]]; then
  PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"
elif [[ -d "${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}" ]]; then
  PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"
else
  PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
fi

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
  echo "error: state file not found: ${ORCH_STATE_FILE}" >&2
  exit 1
fi

if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
  echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
  exit 1
fi

if [[ ! -f "${PROMPT_TEMPLATE}" ]]; then
  echo "error: reviewer prompt template not found: ${PROMPT_TEMPLATE}" >&2
  exit 1
fi

mkdir -p "${PID_DIR}" "${LOG_DIR}"

# --- Structural check: all items settled (done or failed) ---

TOTAL=$(jq '.items | length' "${ORCH_STATE_FILE}")
CNT_DONE=$(jq '[.items[] | select(.status == "done")] | length' \
  "${ORCH_STATE_FILE}")
CNT_FAILED=$(jq '[.items[] | select(.status == "failed")] | length' \
  "${ORCH_STATE_FILE}")
CNT_IN_PROGRESS=$(jq \
  '[.items[] | select(.status != "done" and .status != "failed")] | length' \
  "${ORCH_STATE_FILE}")

if [[ "${CNT_IN_PROGRESS}" -gt 0 ]]; then
  echo "error: ${CNT_IN_PROGRESS} items still in progress — review requires all items settled" >&2
  jq -r '.items[] | select(.status != "done" and .status != "failed") |
    "  item \(.id): \(.description) (\(.status))"' "${ORCH_STATE_FILE}" >&2
  exit 1
fi

if [[ "${CNT_DONE}" -eq 0 ]]; then
  echo "error: no items completed — nothing to review (${CNT_FAILED} failed)" >&2
  exit 1
fi

if [[ "${CNT_FAILED}" -gt 0 ]]; then
  echo "orch-review: ${CNT_DONE}/${TOTAL} items done, ${CNT_FAILED} failed — reviewing done items only"
  jq -r '.items[] | select(.status == "failed") |
    "  skipping item \(.id): \(.description) (failed)"' "${ORCH_STATE_FILE}"
else
  echo "orch-review: all ${TOTAL} items done — starting per-item review"
fi

# --- Read concurrency and poll settings from state ---

MAX_WORKERS=$(jq '.maxParallelWorkers // 4' "${ORCH_STATE_FILE}")
POLL_INTERVAL=$(orch_read_config "review_poll_interval_seconds")
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# --- Mark failed work items as review-skipped ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq --arg now "${NOW}" \
  '(.items[] | select(.status == "failed")).reviewStatus = "skipped" |
	 .finalReview.status = "running" |
	 .updatedAt = $now' "${ORCH_STATE_FILE}")
orch_write_state "${SLUG}" "${UPDATED}"

# --- Prepare review directory ---

mkdir -p "${REVIEW_DIR}"

# --- Helper: spawn a reviewer via the harness ---

spawn_reviewer() {
  local item_id="$1"
  local item_desc="$2"

  # Read done-file as handoff context
  local done_file="${DONE_DIR}/item-${item_id}.txt"
  local item_handoff
  if [[ -f "${done_file}" ]]; then
    item_handoff=$(cat "${done_file}")
  else
    item_handoff="(no done-file found — worker may not have written a summary)"
  fi

  # Build prompt from template
  local review_prompt
  review_prompt=$(cat "${PROMPT_TEMPLATE}")
  review_prompt="${review_prompt//\{ITEM_TEXT\}/${item_desc}}"
  review_prompt="${review_prompt//\{ITEM_HANDOFF\}/${item_handoff}}"
  review_prompt="${review_prompt//\{REVIEW_DIR\}/${REVIEW_DIR}}"
  review_prompt="${review_prompt//\{ITEM_NUM\}/${item_id}}"

  # Write prompt to a temp file (agent CLIs read from disk)
  local prompt_file
  prompt_file=$(mktemp "${ORCH_STATE_DIR}/reviewer-prompt-${item_id}-XXXXXX")
  mv "${prompt_file}" "${prompt_file}.md"
  prompt_file="${prompt_file}.md"
  printf '%s\n' "${review_prompt}" >"${prompt_file}"

  # Remove stale review file
  rm -f "${REVIEW_DIR}/item-${item_id}-review.txt"

  # Determine working directory
  local review_cwd="${REPO_ROOT}"
  if [[ -d "${WORKTREE_DIR}" ]]; then
    review_cwd="${WORKTREE_DIR}"
  fi

  # Build agent command using shim helper (handles Codex exec pattern)
  local cmd_template agent_cmd_str
  cmd_template="$(dega_agent_build_headless_cmd "DEGA_PROMPT_MARKER")"
  agent_cmd_str="${cmd_template/DEGA_PROMPT_MARKER/\"\$(cat '${prompt_file}')\"}"

  # Skip env -u when session var is empty (e.g., Codex has no session var)
  local session_var
  session_var="$(dega_agent_session_var)"
  local env_prefix=""
  if [[ -n "${session_var}" ]]; then
    env_prefix="env -u '${session_var}'"
  fi

  local log_file="${LOG_DIR}/reviewer-${item_id}.log"
  local started_at_file="${PID_DIR}/reviewer-${item_id}.lstart"

  # Compose the reviewer command. The harness cds into cwd before running.
  local cmd
  cmd="GH_SYNC='${GH_SYNC}' RALPH_ROLE=reviewer RALPH_TASK_DIR='${PLAN_DIR}' RALPH_LOOP=1 ${env_prefix} ${agent_cmd_str}; echo '--- reviewer ${item_id} exited ---'"

  # Clear any stale PID file from a prior iteration before spawning
  rm -f "${PID_DIR}/reviewer-${item_id}.pid" "${started_at_file}"

  local pid
  if ! pid=$(harness::spawn_process \
    role=reviewer \
    id="${item_id}" \
    cwd="${review_cwd}" \
    cmd="${cmd}" \
    logfile="${log_file}" \
    pid_dir="${PID_DIR}" \
    started_at_file="${started_at_file}"); then
    echo "orch-review: ERROR — failed to spawn reviewer for item ${item_id}" >&2
    return 1
  fi

  local started_at=""
  if [[ -f "${started_at_file}" ]]; then
    started_at=$(cat "${started_at_file}")
  fi

  # Record reviewer handle + log path + start time so the poll loop can
  # check liveness via harness::query_status and surface the log to the TUI.
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local updated
  updated=$(jq \
    --argjson id "${item_id}" \
    --arg now "${now}" \
    --arg pid "${pid}" \
    --arg log "${log_file}" \
    --arg started_at "${started_at}" \
    '(.items[] | select(.id == $id)) |= (
			.reviewStatus = "reviewing" |
			.reviewerPid = $pid |
			.reviewerLogPath = $log |
			.reviewerStartedAt = $started_at
		) |
		.updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${updated}"

  echo "orch-review: spawned reviewer for item ${item_id} (pid ${pid}): ${item_desc}"
}

# --- Helper: terminate reviewers for items that have settled (pass/fail) ---

kill_done_reviewers() {
  local settled
  settled=$(jq -r \
    '.items[] |
       select(.reviewStatus == "passed" or .reviewStatus == "failed") |
       select(.reviewerPid // "" != "") |
       "\(.id) \(.reviewerPid)"' \
    "${ORCH_STATE_FILE}")

  if [[ -z "${settled}" ]]; then
    return 0
  fi

  local item_id pid line
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    item_id="${line% *}"
    pid="${line#* }"
    harness::terminate handle="${pid}" grace=2 || true
    rm -f "${PID_DIR}/reviewer-${item_id}.pid" \
      "${PID_DIR}/reviewer-${item_id}.lstart"

    # Clear the handle fields now that the reviewer is gone
    local now updated
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    updated=$(jq \
      --argjson id "${item_id}" \
      --arg now "${now}" \
      '(.items[] | select(.id == $id)) |= (
				.reviewerPid = null |
				.reviewerStartedAt = null
			) |
			.updatedAt = $now' "${ORCH_STATE_FILE}")
    orch_write_state "${SLUG}" "${updated}"
    echo "orch-review: terminated reviewer for item ${item_id} (pid ${pid})"
  done <<<"${settled}"
}

# --- Helper: detect stale reviewers (process dead, no review file) ---

detect_stale_reviewers() {
  local reviewing
  reviewing=$(jq -r \
    '.items[] | select(.reviewStatus == "reviewing") |
       "\(.id)\t\(.reviewerPid // "")\t\(.reviewerStartedAt // "")"' \
    "${ORCH_STATE_FILE}")

  if [[ -z "${reviewing}" ]]; then
    return 0
  fi

  local state
  state=$(cat "${ORCH_STATE_FILE}")
  local changed=false
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local item_id pid started_at status rc
  while IFS=$'\t' read -r item_id pid started_at; do
    [[ -z "${item_id}" ]] && continue

    # No PID recorded yet — spawn still in flight, skip this cycle.
    if [[ -z "${pid}" ]]; then
      continue
    fi

    # A completed review-file trumps process state; let the next
    # orch_sync_review_files call promote the item.
    if [[ -f "${REVIEW_DIR}/item-${item_id}-review.txt" ]]; then
      continue
    fi

    rc=0
    if [[ -n "${started_at}" ]]; then
      status=$(harness::query_status handle="${pid}" started_at="${started_at}") || rc=$?
    else
      status=$(harness::query_status handle="${pid}") || rc=$?
    fi

    if [[ "${rc}" -eq 0 && "${status}" == "alive" ]]; then
      continue
    fi

    # Reviewer exited without writing a review — mark failed
    state=$(printf '%s' "${state}" | jq \
      --argjson id "${item_id}" \
      --arg now "${now}" \
      '(.items[] | select(.id == $id)) |= (
				.reviewStatus = "failed" |
				.reviewerPid = null |
				.reviewerStartedAt = null
			) |
			.updatedAt = $now')
    echo "orch-review: reviewer for item ${item_id} (pid ${pid}) exited without writing review — marking failed"
    changed=true
  done <<<"${reviewing}"

  if [[ "${changed}" == "true" ]]; then
    orch_write_state "${SLUG}" "${state}"
  fi
}

# --- Poll loop: spawn reviewers and wait for completion ---

echo "orch-review: starting parallel review"
echo "  max concurrent reviewers: ${MAX_WORKERS}"
echo "  poll interval: ${POLL_INTERVAL}s"
echo ""

while true; do
  # Sync review files into state, clean up finished processes, detect stale
  orch_sync_review_files "${SLUG}"
  kill_done_reviewers
  detect_stale_reviewers

  # Count current review state
  cnt_reviewing=$(jq '[.items[] | select(.reviewStatus == "reviewing")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_pending=$(jq '[.items[] | select(.reviewStatus == "pending")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_passed=$(jq '[.items[] | select(.reviewStatus == "passed")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_failed=$(jq '[.items[] | select(.reviewStatus == "failed")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_skipped=$(jq '[.items[] | select(.reviewStatus == "skipped")] | length' \
    "${ORCH_STATE_FILE}")

  echo "orch-review: [poll] reviewing=${cnt_reviewing} pending=${cnt_pending} passed=${cnt_passed} failed=${cnt_failed} skipped=${cnt_skipped}"

  # All reviews complete when nothing is reviewing or pending
  if [[ "${cnt_reviewing}" -eq 0 ]] && [[ "${cnt_pending}" -eq 0 ]]; then
    echo ""
    echo "orch-review: reviews complete — ${cnt_passed} passed, ${cnt_failed} failed, ${cnt_skipped} skipped"
    break
  fi

  # Spawn reviewers for pending items up to max concurrency
  available_slots=$((MAX_WORKERS - cnt_reviewing))
  if ((available_slots > 0 && cnt_pending > 0)); then
    pending_ids=$(jq -r '.items[] | select(.reviewStatus == "pending") | .id' \
      "${ORCH_STATE_FILE}")
    spawned=0
    for pid_item in ${pending_ids}; do
      if ((spawned >= available_slots)); then break; fi
      pdesc=$(jq -r ".items[] | select(.id == ${pid_item}) | .description" \
        "${ORCH_STATE_FILE}")
      spawn_reviewer "${pid_item}" "${pdesc}"
      spawned=$((spawned + 1))
    done
  fi

  sleep "${POLL_INTERVAL}"
done

# --- Aggregate decision ---

# Review-failed: items that were reviewed and failed review
REVIEW_FAILED_IDS=$(jq -r '.items[] | select(.reviewStatus == "failed") | .id' \
  "${ORCH_STATE_FILE}")
REVIEW_FAILED=()
for fid in ${REVIEW_FAILED_IDS}; do
  REVIEW_FAILED+=("${fid}")
done

# Work-failed: items that failed execution and were skipped by review
WORK_FAILED_IDS=$(jq -r '.items[] | select(.reviewStatus == "skipped") | .id' \
  "${ORCH_STATE_FILE}")
WORK_FAILED=()
for fid in ${WORK_FAILED_IDS}; do
  WORK_FAILED+=("${fid}")
done

# SHIP/REVISE decision based on review failures only —
# work-failed items are logged but don't block SHIP
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ ${#REVIEW_FAILED[@]} -eq 0 ]]; then
  echo ""
  if [[ ${#WORK_FAILED[@]} -gt 0 ]]; then
    echo "orch-review: SHIP — all reviewed items passed (${#WORK_FAILED[@]} work-failed items skipped)"
  else
    echo "orch-review: SHIP — all ${TOTAL} items passed"
  fi

  UPDATED=$(jq --arg now "${NOW}" \
    '.finalReview.status = "done" |
     .finalReview.result = "SHIP" |
     .finalReview.reworkItems = [] |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${UPDATED}"
else
  echo ""
  echo "orch-review: REVISE — ${#REVIEW_FAILED[@]} item(s) failed review"
  if [[ ${#WORK_FAILED[@]} -gt 0 ]]; then
    echo "orch-review: (${#WORK_FAILED[@]} work-failed items also skipped)"
  fi

  # Build JSON array of rework item IDs (review failures only)
  REWORK_JSON=$(printf '%s\n' "${REVIEW_FAILED[@]}" | jq -R 'tonumber' | jq -s '.')

  UPDATED=$(jq --arg now "${NOW}" --argjson rework "${REWORK_JSON}" \
    '.finalReview.status = "done" |
     .finalReview.result = "REVISE" |
     .finalReview.reworkItems = $rework |
     .updatedAt = $now |
     reduce ($rework[] | tostring | tonumber) as $id (.;
       (.items[] | select(.id == $id)) |=
         (.status = "ready" | .iteration = (.iteration + 1) | .reviewStatus = "pending")
     )' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${UPDATED}"

  # Write consolidated feedback for the loop
  FEEDBACK_FILE="${PLAN_DIR}/review-feedback.txt"
  {
    printf 'REWORK_ITEMS: %s\n' "$(printf '%s\n' "${REVIEW_FAILED[@]}" | paste -sd ', ' -)"
    for fid in "${REVIEW_FAILED[@]}"; do
      review="${REVIEW_DIR}/item-${fid}-review.txt"
      if [[ -f "${review}" ]]; then
        printf '\n--- item %s (review failed) ---\n' "${fid}"
        tail -n +2 "${review}"
      fi
    done
  } >"${FEEDBACK_FILE}"

  echo "orch-review: rework items: $(printf '%s\n' "${REVIEW_FAILED[@]}" | paste -sd ', ' -)"
  echo "  Feedback written to ${FEEDBACK_FILE}"
fi
