#!/usr/bin/env bash
# Orchestrator engine — poll loop, worker spawning, review, and cleanup.
#
# Runs inside a tmux window (started by orch-run.sh). Drives workers to
# completion, invokes review, handles SHIP/REVISE outcomes, and cleans up.
#
# Usage: scripts/orch-engine.sh <slug> [--max-workers N] [--max-iterations N] [--background]
#
# This script is not invoked directly by users. orch-run.sh launches it
# inside a tmux window named "engine" in the orch-<slug> session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh disable=SC1091
source "${SCRIPT_DIR}/orch-state.sh"

# shellcheck source=agent-shim.sh disable=SC1091
source "${SCRIPT_DIR}/agent-shim.sh"

# shellcheck source=providers/provider.sh disable=SC1091
source "${SCRIPT_DIR}/providers/provider.sh"

# --- Parse args ---

SLUG=""
MAX_WORKERS=4
MAX_ITERATIONS=3
BACKGROUND=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --max-workers)
    MAX_WORKERS="${2:-4}"
    shift 2
    ;;
  --max-iterations)
    MAX_ITERATIONS="${2:-3}"
    shift 2
    ;;
  --background)
    BACKGROUND=true
    shift
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    exit 1
    ;;
  *)
    SLUG="$1"
    shift
    ;;
  esac
done

if [[ -z "${SLUG}" ]]; then
  echo "error: usage: orch-engine.sh <slug> [--max-workers N] [--max-iterations N] [--background]" >&2
  exit 1
fi

# GH_SYNC flag — exported by orch-run.sh when github.sync is true
GH_SYNC="${GH_SYNC:-false}"

# Per-plan state paths
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
DONE_DIR=$(orch_plan_done_dir "${SLUG}")
REVIEW_DIR=$(orch_plan_review_dir "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"
HEARTBEAT_FILE="${ORCH_STATE_DIR}/plans/${SLUG}/heartbeat"

# Write current epoch to heartbeat file — called at poll start, after
# worker spawn, after review, after each SHIP/FAIL step, and before exit.
write_heartbeat() {
  date +%s >"${HEARTBEAT_FILE}"
}

# Plan dir points to the worktree copy so workers never touch main repo
if [[ "${GH_SYNC}" == true ]]; then
  PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"
else
  PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"
fi
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
  echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
  exit 1
fi

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
  echo "error: state.json not found — orch-run.sh must initialize first" >&2
  exit 1
fi

# --- Read current state ---

TOTAL_COUNT=$(jq '.items | length' "${ORCH_STATE_FILE}")

# --- Read poll interval from config ---

POLL_INTERVAL=$(orch_read_config "poll_interval_seconds")
POLL_INTERVAL="${POLL_INTERVAL:-30}"

# --- Lifecycle hooks ---
# Runs all executable scripts in hooks/orch-lifecycle/ with (event, slug, ...extra args).
# Hooks are sorted alphabetically so numeric prefixes control ordering (01-*, 02-*, ...).
# Failures are logged but never block the orchestrator.

LIFECYCLE_HOOKS_DIR="${SCRIPT_DIR}/../hooks/orch-lifecycle"

run_lifecycle_hooks() {
  local event="$1"
  shift
  if [[ ! -d "${LIFECYCLE_HOOKS_DIR}" ]]; then
    return 0
  fi
  local hook
  while IFS= read -r -d '' hook; do
    if [[ -x "${hook}" ]]; then
      echo "orch-engine: lifecycle hook: $(basename "${hook}") ${event} ${SLUG}"
      "${hook}" "${event}" "${SLUG}" "$@" 2>&1 || {
        echo "orch-engine: WARN — lifecycle hook failed: $(basename "${hook}") (exit $?)" >&2
      }
    fi
  done < <(find "${LIFECYCLE_HOOKS_DIR}" -maxdepth 1 -type f -print0 | sort -z)
}

# --- Worker prompt template ---

WORKER_PROMPT_TEMPLATE="${SCRIPT_DIR}/../agents/orch-worker.md"
if [[ ! -f "${WORKER_PROMPT_TEMPLATE}" ]]; then
  echo "error: worker prompt not found: ${WORKER_PROMPT_TEMPLATE}" >&2
  exit 1
fi
WORKER_PROMPT_BASE=$(cat "${WORKER_PROMPT_TEMPLATE}")

# --- Tmux session name ---

TMUX_SESSION="orch-${SLUG}"

# --- Helper: build worker prompt for an item ---

build_worker_prompt() {
  local item_id="$1"
  local item_desc="$2"
  local plan_path="${PLAN_DIR}/plan.md"
  local done_dir="${DONE_DIR}"

  # Gather dependency summaries (cap at 5)
  local dep_context=""
  local dep_ids
  dep_ids=$(jq -r ".items[] | select(.id == ${item_id}) | .deps[]" \
    "${ORCH_STATE_FILE}" 2>/dev/null || true)
  local dep_count=0
  for dep_id in ${dep_ids}; do
    if ((dep_count >= 5)); then break; fi
    local dep_file="${done_dir}/item-${dep_id}.txt"
    if [[ -f "${dep_file}" ]]; then
      local dep_desc
      dep_desc=$(jq -r ".items[] | select(.id == ${dep_id}) | .description" \
        "${ORCH_STATE_FILE}")
      dep_context="${dep_context}
### Item ${dep_id}: ${dep_desc}
$(cat "${dep_file}")
"
      dep_count=$((dep_count + 1))
    fi
  done

  # Check for per-item review feedback (rework iterations)
  local review_file="${REVIEW_DIR}/item-${item_id}-review.txt"
  local review_context=""
  if [[ -f "${review_file}" ]]; then
    review_context="
## Review feedback

The reviewer flagged issues with your previous work on this item.
Address every point below before writing your done-file.

$(cat "${review_file}")
"
  fi

  # Pre-hydrate context: file paths, requirements, criteria, check command
  local approach_section
  approach_section=$(awk '
		/^```/ { fence = !fence; next }
		fence { next }
		/^## Approach/ { capturing = 1; next }
		capturing && /^## / { capturing = 0; next }
		capturing { print }
	' "${plan_path}")

  local file_paths
  file_paths=$(printf '%s\n%s\n' "${item_desc}" "${approach_section}" |
    orch_extract_file_paths)

  local plan_sections
  plan_sections=$(orch_extract_plan_sections "${plan_path}")

  local task_context=""
  if [[ -n "${file_paths}" ]]; then
    task_context="### Relevant file paths

${file_paths}
"
  fi
  if [[ -n "${plan_sections}" ]]; then
    task_context="${task_context}
${plan_sections}"
  fi

  # Cap pre-hydrated context at 200 lines
  if [[ -n "${task_context}" ]]; then
    task_context=$(printf '%s\n' "${task_context}" | head -200)
  fi

  cat <<-PROMPT
		${WORKER_PROMPT_BASE}

		---

		## Your Assignment

		- **Item ID**: ${item_id}
		- **Item description**: ${item_desc}
		- **Plan path**: ${plan_path}
		- **Done-files directory**: ${done_dir}
		- **Worktree**: ${WORKTREE_DIR}

		## Task Context (pre-gathered by orchestrator)
		${task_context:-"(no pre-hydrated context available)"}

		## Completed dependency summaries
		${dep_context:-"(no dependencies)"}
		${review_context}
	PROMPT
}

# --- Helper: spawn a worker in a tmux pane ---

spawn_worker() {
  local item_id="$1"
  local item_desc="$2"
  local pane_name="worker-${item_id}"

  # Mark item as running
  orch_update_item_status "${SLUG}" "${item_id}" "running"

  # Build prompt
  local prompt
  prompt=$(build_worker_prompt "${item_id}" "${item_desc}")

  # Write prompt to temp file (tmux send-keys has length limits)
  local prompt_file
  prompt_file=$(mktemp "${ORCH_STATE_DIR}/prompt-${item_id}-XXXXXX")
  mv "${prompt_file}" "${prompt_file}.md"
  prompt_file="${prompt_file}.md"
  printf '%s\n' "${prompt}" >"${prompt_file}"

  # Build agent command using shim helper (handles Codex exec pattern)
  local cmd_template agent_cmd_str
  cmd_template="$(dega_agent_build_headless_cmd "DEGA_PROMPT_MARKER")"
  # shellcheck disable=SC2016  # literal $(cat '...') is intended for tmux shell
  agent_cmd_str="${cmd_template/DEGA_PROMPT_MARKER/\"\$(cat '${prompt_file}')\"}"

  # Skip env -u when session var is empty (e.g., Codex has no session var)
  local session_var
  session_var="$(dega_agent_session_var)"
  local env_prefix=""
  if [[ -n "${session_var}" ]]; then
    env_prefix="env -u '${session_var}'"
  fi

  # Kill stale window from previous iteration if it exists
  tmux kill-window -t "${TMUX_SESSION}:${pane_name}" 2>/dev/null || true

  # Spawn in background (-d) so dashboard keeps focus
  tmux new-window -d -t "${TMUX_SESSION}" -n "${pane_name}" \
    "cd '${WORKTREE_DIR}' && \
		 RALPH_ROLE=worker RALPH_TASK_DIR='${PLAN_DIR}' \
		 ${env_prefix} ${agent_cmd_str} ; \
		 echo '--- worker ${item_id} exited ---'; \
		 sleep 2"

  # Stream worker output to log file for the dashboard
  tmux pipe-pane -t "${TMUX_SESSION}:${pane_name}" \
    -o "cat >> '${LOG_DIR}/worker-${item_id}.log'"

  echo "orch-engine: spawned ${pane_name} for item ${item_id}: ${item_desc}"
}

# --- Wave execution loop ---

echo ""
echo "orch-engine: GH_SYNC=${GH_SYNC}"
echo "orch-engine: starting wave execution"
echo "  plan: ${SLUG}"
echo "  total items: ${TOTAL_COUNT}"
echo "  max workers: ${MAX_WORKERS}"
echo "  worktree: ${WORKTREE_DIR}"
echo "  poll interval: ${POLL_INTERVAL}s"
echo ""

# Fire start lifecycle hooks (only on first execution, not rework re-execs)
ITERATION_SUM=$(jq '[.items[].iteration // 0] | add // 0' "${ORCH_STATE_FILE}")
if [[ "${ITERATION_SUM}" -eq 0 ]]; then
  run_lifecycle_hooks "start" \
    --items "${TOTAL_COUNT}" \
    --max-workers "${MAX_WORKERS}"
fi

while true; do
  write_heartbeat

  # Sync done-files, detect stale workers, promote
  # Worker windows stay alive until SHIP/REVISE so capture-pane output is visible
  orch_sync_done_files "${SLUG}"
  orch_detect_stale_workers "${SLUG}"
  orch_promote_ready_items "${SLUG}"

  # Update master state with current progress
  orch_master_update_progress "${SLUG}"

  # Count current state
  local_failed=$(orch_count_by_status "${SLUG}" "failed")
  local_done=$(orch_count_by_status "${SLUG}" "done")
  local_running=$(orch_count_by_status "${SLUG}" "running")
  local_ready=$(orch_count_by_status "${SLUG}" "ready")
  local_queued=$(orch_count_by_status "${SLUG}" "queued")

  echo "orch-engine: [poll] done=${local_done} running=${local_running} ready=${local_ready} queued=${local_queued} failed=${local_failed}"

  # Check if wave is finished (nothing left to run)
  if [[ "${local_running}" -eq 0 ]] && [[ "${local_ready}" -eq 0 ]] && [[ "${local_queued}" -eq 0 ]]; then
    echo ""
    if [[ "${local_failed}" -gt 0 ]]; then
      echo "orch-engine: wave finished — ${local_done}/${TOTAL_COUNT} items done, ${local_failed} failed"
      # List which items failed
      failed_ids=$(jq -r '.items[] | select(.status == "failed") | "\(.id): \(.description)"' \
        "${ORCH_STATE_FILE}")
      while IFS= read -r line; do
        echo "orch-engine:   FAILED — item ${line}"
      done <<<"${failed_ids}"
    else
      echo "orch-engine: all ${TOTAL_COUNT} items complete"
    fi
    break
  fi

  # Spawn workers for ready items up to max concurrency
  available_slots=$((MAX_WORKERS - local_running))
  if ((available_slots > 0 && local_ready > 0)); then
    ready_ids=$(jq -r '.items[] | select(.status == "ready") | .id' \
      "${ORCH_STATE_FILE}")
    spawned=0
    for rid in ${ready_ids}; do
      if ((spawned >= available_slots)); then break; fi

      # Check max-iterations guard before spawning
      cur_iter=$(jq ".items[] | select(.id == ${rid}) | .iteration // 0" \
        "${ORCH_STATE_FILE}")
      max_iter=$(jq ".items[] | select(.id == ${rid}) | .maxIterations // 3" \
        "${ORCH_STATE_FILE}")
      if ((cur_iter >= max_iter)); then
        echo "orch-engine: item ${rid} exhausted ${max_iter} iterations — marking failed"
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        updated=$(jq \
          --argjson id "${rid}" \
          --arg now "${now}" \
          '(.items[] | select(.id == $id)) |=
					  (.status = "failed" | .lastResult = "review-max-retries") |
					 .updatedAt = $now' "${ORCH_STATE_FILE}")
        orch_write_state "${SLUG}" "${updated}"
        continue
      fi

      rdesc=$(jq -r ".items[] | select(.id == ${rid}) | .description" \
        "${ORCH_STATE_FILE}")
      spawn_worker "${rid}" "${rdesc}"
      spawned=$((spawned + 1))
    done
    write_heartbeat
  fi

  # Sleep before next poll
  sleep "${POLL_INTERVAL}"
done

# --- Post-completion: run per-item review ---

echo "orch-engine: running per-item review via orch-review.sh"
"${SCRIPT_DIR}/orch-review.sh" "${SLUG}"
write_heartbeat

# Fire review lifecycle hooks
run_lifecycle_hooks "review"

# Read review result from state
REVIEW_RESULT=$(jq -r '.finalReview.result // "UNKNOWN"' "${ORCH_STATE_FILE}")

if [[ "${REVIEW_RESULT}" == "SHIP" ]]; then
  echo ""
  echo "orch-engine: review passed — checking completion criteria"

  # --- Completion criteria gate ---
  CC_UNCHECKED=$(orch_count_unchecked_criteria "${PLAN_DIR}/plan.md")

  if [[ "${CC_UNCHECKED}" -gt 0 ]]; then
    echo "orch-engine: ${CC_UNCHECKED} unchecked completion criteria — spawning verifier"

    # Update state with verification status — dashboard shows VERIFYING
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    updated=$(jq \
      --arg now "${now}" \
      --argjson count "${CC_UNCHECKED}" \
      '.status = "verifying" |
			.verification = {
				status: "running",
				uncheckedCount: $count,
				iteration: ((.verification.iteration // 0) + 1)
			} |
			.updatedAt = $now' "${ORCH_STATE_FILE}")
    orch_write_state "${SLUG}" "${updated}"

    # Phase-level watchdog — bounds the whole verify phase. If exceeded,
    # the verifier process is killed with SIGTERM (rc=124) and the run
    # fails cleanly with a log line naming the blocking criterion.
    ORCH_VERIFY_PHASE_TIMEOUT="${ORCH_VERIFY_PHASE_TIMEOUT:-300}"

    set +e
    GH_SYNC="${GH_SYNC}" timeout "${ORCH_VERIFY_PHASE_TIMEOUT}" \
      "${SCRIPT_DIR}/orch-verify.sh" "${SLUG}"
    verify_rc=$?
    set -e

    if [[ "${verify_rc}" -eq 0 ]]; then
      # Verifier succeeded — re-check criteria
      CC_AFTER=$(orch_count_unchecked_criteria "${PLAN_DIR}/plan.md")
      if [[ "${CC_AFTER}" -gt 0 ]]; then
        echo "orch-engine: verifier finished but ${CC_AFTER} criteria still unchecked — REVISE"
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        updated=$(jq \
          --arg now "${now}" \
          --argjson count "${CC_AFTER}" \
          '.verification.status = "failed" |
					 .verification.uncheckedCount = $count |
					 .updatedAt = $now' "${ORCH_STATE_FILE}")
        orch_write_state "${SLUG}" "${updated}"
        REVIEW_RESULT="REVISE"
      else
        echo "orch-engine: all completion criteria verified"
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        updated=$(jq \
          --arg now "${now}" \
          '.verification.status = "passed" |
					 .verification.uncheckedCount = 0 |
					 .updatedAt = $now' "${ORCH_STATE_FILE}")
        orch_write_state "${SLUG}" "${updated}"
      fi
    elif [[ "${verify_rc}" -eq 124 ]]; then
      # Phase timeout — extract the last criterion we saw running from
      # verify.log so the operator knows what's hanging.
      blocking=""
      if [[ -f "${LOG_DIR}/verify.log" ]]; then
        blocking=$(grep -E '] RUN: ' "${LOG_DIR}/verify.log" | tail -n 1 | sed -E 's/^\[[^]]+\] RUN: //' || true)
      fi
      echo "orch-engine: verify phase exceeded ${ORCH_VERIFY_PHASE_TIMEOUT}s — failing with phase_timeout" >&2
      if [[ -n "${blocking}" ]]; then
        echo "orch-engine: blocking criterion: ${blocking}" >&2
      else
        echo "orch-engine: blocking criterion: (unknown — no RUN entry in verify.log)" >&2
      fi
      now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      updated=$(jq \
        --arg now "${now}" \
        --arg reason "phase_timeout" \
        --arg blocking "${blocking}" \
        --argjson timeout "${ORCH_VERIFY_PHASE_TIMEOUT}" \
        '.verification.status = "failed" |
				 .verification.reason = $reason |
				 .verification.blockingCriterion = $blocking |
				 .verification.phaseTimeoutSeconds = $timeout |
				 .updatedAt = $now' "${ORCH_STATE_FILE}")
      orch_write_state "${SLUG}" "${updated}"
      REVIEW_RESULT="REVISE"
    else
      echo "orch-engine: verifier failed (rc=${verify_rc}) — REVISE"
      now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      updated=$(jq \
        --arg now "${now}" \
        '.verification.status = "failed" |
				 .updatedAt = $now' "${ORCH_STATE_FILE}")
      orch_write_state "${SLUG}" "${updated}"
      REVIEW_RESULT="REVISE"
    fi
  else
    echo "orch-engine: all completion criteria already checked"
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    updated=$(jq \
      --arg now "${now}" \
      '.verification = {
				status: "passed",
				uncheckedCount: 0,
				iteration: 0
			} |
			.updatedAt = $now' "${ORCH_STATE_FILE}")
    orch_write_state "${SLUG}" "${updated}"
  fi

  # Fire verify lifecycle hooks — state.json now has verification result
  run_lifecycle_hooks "verify"
fi

# --- Actual SHIP / REVISE handling ---

# Safety net: if the engine crashes during the SHIP flow (e.g., unguarded
# command fails with set -e), mark state as "ship-crashed" so it doesn't
# stay stuck at "verifying" forever.
ship_crash_handler() {
  echo "orch-engine: FATAL — engine crashed during SHIP flow (line $1)" >&2
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg now "${now}" \
    '.status = "ship-crashed" | .updatedAt = $now' \
    "${ORCH_STATE_FILE}" >"${ORCH_STATE_FILE}.tmp" &&
    mv "${ORCH_STATE_FILE}.tmp" "${ORCH_STATE_FILE}"
  write_heartbeat
}
trap 'ship_crash_handler ${LINENO}' ERR

if [[ "${REVIEW_RESULT}" == "SHIP" ]]; then
  echo ""

  # Summarize failed items (if any) for operator visibility
  FAILED_COUNT=$(orch_count_by_status "${SLUG}" "failed")
  DONE_COUNT=$(orch_count_by_status "${SLUG}" "done")

  if [[ "${FAILED_COUNT}" -gt 0 ]]; then
    echo "orch-engine: SHIP — ${DONE_COUNT}/${TOTAL_COUNT} items passed review (${FAILED_COUNT} failed)"
    echo "orch-engine: failed items:"
    jq -r '.items[] | select(.status == "failed") | "  - item \(.id): \(.description) (reason: \(.lastResult // "unknown"))"' \
      "${ORCH_STATE_FILE}"
  else
    echo "orch-engine: SHIP — all ${TOTAL_COUNT} items passed review and completion criteria verified"
  fi

  SHIP_ERRORS=0

  # Play completion sound if available
  if [[ -x "${SCRIPT_DIR}/../hooks/play-sound.sh" ]]; then
    DEGA_SOUND=success bash "${SCRIPT_DIR}/../hooks/play-sound.sh" || true
  fi

  # Kill worker/reviewer windows now that we're done
  orch_kill_done_workers "${SLUG}"

  # --- Step 1: Sync worktree plan.md back to main repo ---
  if [[ "${GH_SYNC}" == true ]]; then
    echo "orch-engine: [SHIP 1/9] skipped — GH mode (no local plan sync)"
  else
    MAIN_PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
    WT_PLAN="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}/plan.md"
    if [[ -f "${WT_PLAN}" ]]; then
      if cp "${WT_PLAN}" "${MAIN_PLAN_DIR}/plan.md"; then
        echo "orch-engine: [SHIP 1/9] synced plan.md from worktree"
      else
        echo "orch-engine: ERROR — failed to sync plan.md from worktree" >&2
        SHIP_ERRORS=$((SHIP_ERRORS + 1))
      fi
    else
      echo "orch-engine: WARN — worktree plan.md not found: ${WT_PLAN}"
    fi
  fi

  write_heartbeat

  # --- Step 2: Commit worktree changes (stay on worktree branch) ---
  # Workers commit to orch/<slug> branch. We push that branch directly
  # for the PR instead of merging into the working branch. This gives
  # each plan its own PR even when multiple plans run concurrently.
  if orch_commit_worktree "${SLUG}"; then
    echo "orch-engine: [SHIP 2/9] worktree changes committed"
  else
    echo "orch-engine: WARN — worktree commit returned non-zero (may have no changes)"
  fi

  write_heartbeat

  # --- Step 3: Deregister from master state ---
  orch_master_deregister "${SLUG}" "completed"
  echo "orch-engine: [SHIP 3/9] deregistered from master state"

  write_heartbeat

  # --- Step 4: Move plan from active/ to completed/ ---
  COMPLETED_DIR="${REPO_ROOT}/docs/exec-plans/completed/${SLUG}"
  if [[ "${GH_SYNC}" == true ]]; then
    echo "orch-engine: [SHIP 4/9] skipped — GH mode (no local plan move)"
  else
    ACTIVE_PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
    if [[ -d "${ACTIVE_PLAN_DIR}" ]]; then
      mkdir -p "${REPO_ROOT}/docs/exec-plans/completed"
      if mv "${ACTIVE_PLAN_DIR}" "${COMPLETED_DIR}"; then
        echo "orch-engine: [SHIP 4/9] moved plan to completed/"
      else
        echo "orch-engine: ERROR — failed to move plan to completed/" >&2
        SHIP_ERRORS=$((SHIP_ERRORS + 1))
      fi
    else
      echo "orch-engine: WARN — active plan dir not found: ${ACTIVE_PLAN_DIR}"
    fi

    # Save final state.json into completed plan directory
    if [[ -d "${COMPLETED_DIR}" ]]; then
      cp "${ORCH_STATE_FILE}" "${COMPLETED_DIR}/state.json"
    fi
  fi

  write_heartbeat

  # --- Step 5: Commit the plan move ---
  if [[ "${GH_SYNC}" == true ]]; then
    echo "orch-engine: [SHIP 5/9] skipped — GH mode (no plan move to commit)"
  else
    # Stage the deletion of active/ (already moved by step 4) and new completed/ dir.
    # Guard each path — step 4 may have partially failed or paths may not exist.
    git -C "${REPO_ROOT}" rm -r --cached --ignore-unmatch \
      "docs/exec-plans/active/${SLUG}" 2>/dev/null || true
    if [[ -d "${REPO_ROOT}/docs/exec-plans/completed/${SLUG}" ]]; then
      git -C "${REPO_ROOT}" add "docs/exec-plans/completed/${SLUG}"
    fi
    if git -C "${REPO_ROOT}" diff --cached --quiet; then
      echo "orch-engine: WARN — nothing to commit (plan move produced no diff)"
    else
      if git -C "${REPO_ROOT}" commit --no-verify -m "orch: move ${SLUG} to completed"; then
        echo "orch-engine: [SHIP 5/9] committed plan move"
      else
        echo "orch-engine: ERROR — git commit failed for plan move" >&2
        SHIP_ERRORS=$((SHIP_ERRORS + 1))
      fi
    fi
  fi

  write_heartbeat

  # --- Step 6: Append to plan registry ---
  ITER_COUNT=$(jq '[.items[].iteration // 0] | max' "${ORCH_STATE_FILE}")
  if [[ "${GH_SYNC}" == true ]]; then
    echo "orch-engine: [SHIP 6/9] skipped — GH mode (issues are the registry)"
  else
    if orch_registry_append "${SLUG}" "completed" "${ITER_COUNT}" "orch"; then
      # Commit registry update
      git -C "${REPO_ROOT}" add "docs/exec-plans/REGISTRY.md"
      if ! git -C "${REPO_ROOT}" diff --cached --quiet; then
        if ! git -C "${REPO_ROOT}" commit --no-verify -m "orch: update plan registry for ${SLUG}"; then
          echo "orch-engine: ERROR — git commit failed for registry update" >&2
          SHIP_ERRORS=$((SHIP_ERRORS + 1))
        fi
      fi
      echo "orch-engine: [SHIP 6/9] appended to plan registry"
    else
      echo "orch-engine: WARN — registry append failed (non-fatal)"
    fi
  fi

  write_heartbeat

  # --- Step 7: Append to changelog ---
  if [[ "${GH_SYNC}" == true ]]; then
    PLAN_TITLE=$(sed -n 's/^# Plan: *//p' "${PLAN_DIR}/plan.md" 2>/dev/null || true)
  else
    PLAN_TITLE=$(sed -n 's/^# Plan: *//p' "${COMPLETED_DIR}/plan.md" 2>/dev/null || true)
  fi
  if [[ -n "${PLAN_TITLE}" ]]; then
    if orch_changelog_append "${SLUG}" "${PLAN_TITLE}" ""; then
      git -C "${REPO_ROOT}" add "CHANGELOG.md"
      if ! git -C "${REPO_ROOT}" diff --cached --quiet; then
        if ! git -C "${REPO_ROOT}" commit --no-verify -m "orch: update changelog for ${SLUG}"; then
          echo "orch-engine: ERROR — git commit failed for changelog update" >&2
          SHIP_ERRORS=$((SHIP_ERRORS + 1))
        fi
      fi
      echo "orch-engine: [SHIP 7/9] appended to changelog"
    else
      echo "orch-engine: WARN — changelog append failed (non-fatal)"
    fi
  else
    echo "orch-engine: WARN — could not extract plan title for changelog"
  fi

  write_heartbeat

  # --- Compute elapsed time (needed by PR body and final summary) ---
  STARTED_AT=$(jq -r '.startedAt // empty' "${ORCH_STATE_FILE}")
  if [[ -n "${STARTED_AT}" ]]; then
    START_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "${STARTED_AT}" +%s 2>/dev/null ||
      date -d "${STARTED_AT}" +%s 2>/dev/null || echo "")
    if [[ -n "${START_EPOCH}" ]]; then
      NOW_EPOCH=$(date +%s)
      ELAPSED_SECS=$((NOW_EPOCH - START_EPOCH))
      ELAPSED_MIN=$((ELAPSED_SECS / 60))
      ELAPSED_SEC=$((ELAPSED_SECS % 60))
      ELAPSED_STR="${ELAPSED_MIN}m ${ELAPSED_SEC}s"
    else
      ELAPSED_STR="unknown"
    fi
  else
    ELAPSED_STR="unknown"
  fi

  write_heartbeat

  # --- Step 8: Push worktree branch and create PR ---
  # Each plan pushes its own orch/ branch so multiple concurrent
  # plans produce separate PRs instead of sharing the working branch.
  # Read actual branch name from the worktree (includes issue number if set).
  ORCH_BRANCH=$(git -C "${ORCH_STATE_DIR}/worktrees/${SLUG}" \
    rev-parse --abbrev-ref HEAD 2>/dev/null || echo "orch/${SLUG}")
  PR_TARGET=$(grep 'pr_target:' "${REPO_ROOT}/dega-core.yaml" 2>/dev/null |
    awk '{print $2}' | tr -d ' ' || true)
  PR_TARGET="${PR_TARGET:-main}"

  WORKTREE_DIR_PUSH="${ORCH_STATE_DIR}/worktrees/${SLUG}"
  if [[ -d "${WORKTREE_DIR_PUSH}" ]]; then
    # Push the worktree branch directly
    if git -C "${WORKTREE_DIR_PUSH}" push -u origin "${ORCH_BRANCH}" 2>&1; then
      echo "orch-engine: [SHIP 8/9] pushed branch ${ORCH_BRANCH}"

      # Build PR body
      PR_BODY="## SHIP Summary"$'\n\n'
      PR_BODY+="- **Plan:** \`${SLUG}\`"$'\n'
      PR_BODY+="- **Items:** ${DONE_COUNT}/${TOTAL_COUNT} passed"$'\n'
      if [[ "${FAILED_COUNT}" -gt 0 ]]; then
        PR_BODY+="- **Failed:** ${FAILED_COUNT}"$'\n'
      fi
      PR_BODY+="- **Iterations:** ${ITER_COUNT}"$'\n'
      PR_BODY+="- **Elapsed:** ${ELAPSED_STR}"$'\n'

      # Add Closes #N if issue is linked
      ISSUE_NUMBER=$(jq -r '.issueNumber // empty' "${ORCH_STATE_FILE}")
      if [[ -n "${ISSUE_NUMBER}" ]]; then
        PR_BODY+=$'\n'"Closes #${ISSUE_NUMBER}"$'\n'
      fi

      PR_TITLE="plan: ${SLUG}"

      if PR_URL=$(provider_pr_create \
        --title "${PR_TITLE}" \
        --body "${PR_BODY}" \
        --base "${PR_TARGET}" \
        --head "${ORCH_BRANCH}" 2>&1); then
        echo "orch-engine: PR created: ${PR_URL}"

        # Post PR link as comment on the linked issue
        if [[ -n "${ISSUE_NUMBER}" ]]; then
          provider_issue_comment \
            --issue "${ISSUE_NUMBER}" \
            --body "PR created: ${PR_URL}" 2>&1 || {
            echo "orch-engine: WARN — failed to post PR link on issue #${ISSUE_NUMBER}" >&2
          }
        fi
      else
        echo "orch-engine: WARN — PR creation failed (non-fatal): ${PR_URL}" >&2
      fi
    else
      echo "orch-engine: WARN — git push failed, skipping PR creation" >&2
    fi
  else
    echo "orch-engine: [SHIP 8/9] skipped PR — no worktree (changes on working branch)"
  fi

  write_heartbeat

  # --- Step 9: Clean up worktree ---
  if orch_cleanup_worktree "${SLUG}"; then
    echo "orch-engine: [SHIP 9/9] worktree cleaned up"
  else
    echo "orch-engine: WARN — worktree cleanup failed (non-fatal)"
  fi

  # --- Write completed status ---
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  updated=$(jq \
    --arg now "${now}" \
    '.status = "completed" | .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${updated}"

  # --- Post-SHIP validation ---
  echo ""
  VALIDATION_OK=true
  if [[ "${GH_SYNC}" == true ]]; then
    echo "orch-engine: post-validation skipped — GH mode (no local plan artifacts)"
  else
    if [[ -d "${REPO_ROOT}/docs/exec-plans/active/${SLUG}" ]]; then
      echo "orch-engine: VALIDATION FAIL — plan still in active/" >&2
      VALIDATION_OK=false
    fi
    if [[ ! -d "${COMPLETED_DIR}" ]]; then
      echo "orch-engine: VALIDATION FAIL — plan not in completed/" >&2
      VALIDATION_OK=false
    fi
    if [[ ! -f "${COMPLETED_DIR}/plan.md" ]]; then
      echo "orch-engine: VALIDATION FAIL — plan.md missing from completed/" >&2
      VALIDATION_OK=false
    fi
    if git -C "${REPO_ROOT}" status --porcelain \
      "docs/exec-plans/active/${SLUG}" \
      "docs/exec-plans/completed/${SLUG}" 2>/dev/null | grep -q .; then
      echo "orch-engine: VALIDATION FAIL — uncommitted plan changes" >&2
      VALIDATION_OK=false
    fi
  fi

  echo ""
  echo "========================================"
  echo "  SHIP COMPLETE"
  echo "========================================"
  echo "  Plan:     ${SLUG}"
  echo "  Items:    ${DONE_COUNT}/${TOTAL_COUNT} passed"
  if [[ "${FAILED_COUNT}" -gt 0 ]]; then
    echo "  Failed:   ${FAILED_COUNT}"
  fi
  echo "  Errors:   ${SHIP_ERRORS}"
  echo "  Elapsed:  ${ELAPSED_STR}"
  if [[ "${VALIDATION_OK}" == true ]] && [[ "${SHIP_ERRORS}" -eq 0 ]]; then
    echo "  Status:   all 9 steps passed, validation OK"
  else
    echo "  Status:   completed with issues (${SHIP_ERRORS} error(s), validation=${VALIDATION_OK})" >&2
    echo "  Details:  .orchestrator/plans/${SLUG}/logs/engine.log" >&2
  fi
  echo "========================================"
  echo ""
  echo "orch-engine: log saved to .orchestrator/plans/${SLUG}/logs/engine.log"

  # Fire ship lifecycle hooks with summary data
  run_lifecycle_hooks "ship" \
    --items "${TOTAL_COUNT}" \
    --passed "${DONE_COUNT}" \
    --failed "${FAILED_COUNT}" \
    --elapsed "${ELAPSED_STR}"

  # Engine exits — dashboard stays open showing DONE screen
  write_heartbeat
  exit 0
elif [[ "${REVIEW_RESULT}" == "REVISE" ]]; then
  echo ""
  echo "orch-engine: REVISE — some items need rework"
  echo "  Re-running wave execution for rework items..."
  echo ""

  # Fire revise lifecycle hooks
  REVISE_FAILED=$(orch_count_by_status "${SLUG}" "failed")
  REVISE_DONE=$(orch_count_by_status "${SLUG}" "done")
  run_lifecycle_hooks "revise" \
    --items "${TOTAL_COUNT}" \
    --passed "${REVISE_DONE}" \
    --failed "${REVISE_FAILED}"

  # Kill worker windows before re-exec
  orch_kill_done_workers "${SLUG}"

  # Update master progress before re-exec
  orch_master_update_progress "${SLUG}"

  write_heartbeat

  # Re-exec engine for rework pass (review already reset items to "ready")
  BACKGROUND_FLAG=""
  if [[ "${BACKGROUND}" == true ]]; then
    BACKGROUND_FLAG="--background"
  fi
  # shellcheck disable=SC2086
  exec "${SCRIPT_DIR}/orch-engine.sh" "${SLUG}" --max-workers "${MAX_WORKERS}" --max-iterations "${MAX_ITERATIONS}" ${BACKGROUND_FLAG}
else
  echo "orch-engine: unexpected review result: ${REVIEW_RESULT}" >&2
  orch_master_deregister "${SLUG}" "failed"
  # Keep worktree on failure — preserves committed progress for resume
  # Write failed status so the dashboard renders a final screen
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  updated=$(jq \
    --arg now "${now}" \
    '.status = "failed" | .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${updated}"

  # Engine exits — dashboard stays open showing FAILED screen
  write_heartbeat
  exit 1
fi
