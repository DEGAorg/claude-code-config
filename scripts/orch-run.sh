#!/usr/bin/env bash
# Orchestrator launcher — validates inputs, initializes state, spawns the
# engine as a detached process via the Harness capability contract, and
# (in foreground mode) attaches the Ink TUI to tail progress. The engine
# runs independently of the calling terminal; closing the TUI does not
# stop it.
#
# The poll loop, worker spawning, review, and cleanup all run inside
# scripts/orch-engine.sh — spawned here via `harness::spawn_process`
# (role=engine, id=<slug>). State lives under `.orchestrator/plans/<slug>/`
# and the Ink TUI reads it through the `StateSource` interface.
#
# Usage: scripts/orch-run.sh <slug> [--issue N] [--max-workers N] [--max-iterations N] [--background]
#        scripts/orch-run.sh --gc [--dry-run]
#
# Options:
#   --issue N            Fetch plan from GitHub Issue #N instead of local plan.md
#   --max-workers N      Max concurrent workers (default: 4)
#   --max-iterations N   Max review/rework iterations per item (default: 3)
#   --background         Headless mode — spawn engine and exit without opening the TUI
#   --gc [--dry-run]     Run garbage collection on stale plans
#
# Example: scripts/orch-run.sh 20260309-orch-smoke-test
# Example: scripts/orch-run.sh 20260309-orch-smoke-test --issue 42
# Example: scripts/orch-run.sh 20260309-orch-smoke-test --background

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"
# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=read-github-config.sh
source "${SCRIPT_DIR}/read-github-config.sh"
# shellcheck source=harness/dispatcher.sh
source "${SCRIPT_DIR}/harness/dispatcher.sh"

# --- Check dependencies ---

check_deps() {
  local missing=()
  for cmd in jq node; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: missing required tools: ${missing[*]}" >&2
    echo "  install them and ensure they are on your PATH" >&2
    exit 1
  fi
}

check_deps

# --- Parse args ---

SLUG=""
ISSUE_NUMBER=""
MAX_WORKERS=4
MAX_ITERATIONS=3
BACKGROUND=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --gc)
    shift
    exec bash "${SCRIPT_DIR}/orch-gc.sh" "$@"
    ;;
  --issue)
    ISSUE_NUMBER="${2:-}"
    if [[ -z "${ISSUE_NUMBER}" ]]; then
      echo "error: --issue requires an issue number" >&2
      exit 1
    fi
    shift 2
    ;;
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
    echo "usage: orch-run.sh <slug> [--issue N] [--max-workers N] [--max-iterations N] [--background] | --gc [--dry-run]" >&2
    exit 1
    ;;
  *)
    SLUG="$1"
    shift
    ;;
  esac
done

if [[ -z "${SLUG}" ]]; then
  echo "error: usage: orch-run.sh <slug> [--issue N] [--max-workers N] [--max-iterations N] [--background] | --gc [--dry-run]" >&2
  exit 1
fi

# --- GH sync mode ---
# When github.sync is true, plans live in .orchestrator/ instead of
# docs/exec-plans/. This keeps PRs free of plan artifacts.
GH_SYNC=false
if gh_config_bool sync; then
  GH_SYNC=true
fi
export GH_SYNC

if [[ "${GH_SYNC}" == true ]]; then
  PLAN_DIR="${REPO_ROOT}/.orchestrator/plans/${SLUG}"
else
  PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
fi

# --- Fetch plan from GitHub Issue if --issue is set ---

FROM_ISSUE=false
if [[ -n "${ISSUE_NUMBER}" ]]; then
  # Validate issue number format
  if ! [[ "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
    echo "error: issue number must be a positive integer, got: ${ISSUE_NUMBER}" >&2
    exit 1
  fi

  # Validate gh auth before launch (fail fast — auth is interactive)
  # shellcheck source=ensure-gh.sh
  source "${SCRIPT_DIR}/ensure-gh.sh"
  ensure_gh
  if ! gh auth status &>/dev/null; then
    echo "error: gh is not authenticated. Run: gh auth login" >&2
    echo "Then re-run this command." >&2
    exit 2
  fi

  echo "orch: fetching plan from issue #${ISSUE_NUMBER}..."
  "${SCRIPT_DIR}/gh-plan-fetch.sh" "${ISSUE_NUMBER}" "${SLUG}" >&2

  # Verify fetched plan exists in .orchestrator/
  FETCHED_PLAN=".orchestrator/plans/${SLUG}/plan.md"
  if [[ ! -f "${FETCHED_PLAN}" ]]; then
    echo "error: gh-plan-fetch.sh did not produce ${FETCHED_PLAN}" >&2
    exit 1
  fi

  if [[ "${GH_SYNC}" == true ]]; then
    # GH mode: PLAN_DIR already points to .orchestrator/, no copy needed
    echo "orch: GH mode — plan stays in .orchestrator/plans/${SLUG}/"
  else
    # Local mode: copy fetched plan into docs/exec-plans/active/
    mkdir -p "${PLAN_DIR}"
    cp "${FETCHED_PLAN}" "${PLAN_DIR}/plan.md"
  fi
  FROM_ISSUE=true
fi

if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
  echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
  echo "  hint: pass --issue N to fetch from a GitHub Issue" >&2
  exit 1
fi

# --- Uncommitted plan guard (skip for issue-sourced plans and GH mode) ---
if [[ "${FROM_ISSUE}" == false ]] && [[ "${GH_SYNC}" == false ]]; then
  plan_dirty=$(git -C "${REPO_ROOT}" status --porcelain "docs/exec-plans/active/${SLUG}/" 2>/dev/null || true)
  if [[ -n "${plan_dirty}" ]]; then
    echo "error: plan has uncommitted changes — commit before running orch" >&2
    echo "  dirty files:" >&2
    while IFS= read -r line; do
      echo "    ${line}" >&2
    done <<<"${plan_dirty}"
    exit 1
  fi
fi

# --- Auto-create GitHub Issue if sync enabled and no meta exists ---

PLAN_META_DIR="${ORCH_STATE_DIR}/plans/${SLUG}"
PLAN_META_FILE="${PLAN_META_DIR}/plan-meta.json"

if [[ -z "${ISSUE_NUMBER}" ]] && gh_config_bool sync; then
  if [[ ! -f "${PLAN_META_FILE}" ]]; then
    # Extract plan title from the first "# Plan: ..." heading
    plan_title=$(grep -m1 '^# Plan:' "${PLAN_DIR}/plan.md" 2>/dev/null |
      sed 's/^# Plan:[[:space:]]*//' || true)
    if [[ -z "${plan_title}" ]]; then
      plan_title="${SLUG}"
    fi

    # Ensure gh is available and authenticated
    if "${SCRIPT_DIR}/ensure-gh.sh" --quiet; then
      echo "orch: creating GitHub Issue for plan '${SLUG}'..."
      if issue_num=$("${SCRIPT_DIR}/plan-create.sh" \
        --title "${plan_title}" \
        --body-file "${PLAN_DIR}/plan.md"); then
        ISSUE_NUMBER="${issue_num}"
        mkdir -p "${PLAN_META_DIR}"
        jq -n \
          --argjson issue "${ISSUE_NUMBER}" \
          --arg repo "$(gh_resolve_repo "")" \
          --arg slug "${SLUG}" \
          --arg createdAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
          '{
						issue_number: $issue,
						repo: $repo,
						slug: $slug,
						created_at: $createdAt
					}' >"${PLAN_META_FILE}"
        echo "orch: created issue #${ISSUE_NUMBER}, wrote ${PLAN_META_FILE}"
      else
        echo "orch: WARNING — failed to create GitHub Issue, continuing without sync" >&2
      fi
    else
      echo "orch: WARNING — gh not authenticated, skipping auto-issue creation" >&2
    fi
  else
    # plan-meta.json exists — read the issue number from it
    existing_issue=$(jq -r '.issue_number // empty' "${PLAN_META_FILE}")
    if [[ -n "${existing_issue}" ]]; then
      ISSUE_NUMBER="${existing_issue}"
      echo "orch: found existing issue #${ISSUE_NUMBER} in plan-meta.json"
    fi
  fi
fi

# --- Per-plan state paths ---

ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
PID_DIR="${ORCH_STATE_DIR}/plans/${SLUG}/pids"
LOG_FILE=$(orch_plan_log_file "${SLUG}")
EVENTS_FILE="$(orch_plan_dir "${SLUG}")/events.jsonl"

# Emit plan_end summarizing the current state.json. Used both on the
# already-complete early-exit path and on the background-mode launch
# exit. The engine emits an authoritative plan_end of its own when it
# finishes — per events-schema.md consumers treat the last line as
# authoritative.
emit_plan_end() {
  local status="$1"
  local total done_count failed_count duration_ms=""
  if [[ -f "${ORCH_STATE_FILE}" ]]; then
    total=$(jq '.items | length' "${ORCH_STATE_FILE}")
    done_count=$(jq '[.items[] | select(.status == "done")] | length' "${ORCH_STATE_FILE}")
    failed_count=$(jq '[.items[] | select(.status == "failed")] | length' "${ORCH_STATE_FILE}")
  else
    total=0
    done_count=0
    failed_count=0
  fi
  if [[ -n "${PLAN_START_EPOCH_MS:-}" ]]; then
    local now_ms=$(($(date +%s) * 1000))
    duration_ms=$((now_ms - PLAN_START_EPOCH_MS))
  fi
  local -a kv=(
    slug="${SLUG}"
    status="${status}"
    total_items:="${total}"
    done_items:="${done_count}"
    failed_items:="${failed_count}"
  )
  if [[ -n "${duration_ms}" ]]; then
    kv+=(duration_ms:="${duration_ms}")
  fi
  harness::emit_event "${EVENTS_FILE}" plan_end "${kv[@]}"
}

# --- Already-running detection (via harness) ---
#
# An engine is running iff `harness::list_active` reports a live process
# with role=engine in the plan's PID dir.

engine_is_alive() {
  [[ -d "${PID_DIR}" ]] || return 1
  local role _id pid
  while read -r role _id pid; do
    if [[ "${role}" == "engine" && -n "${pid}" ]]; then
      return 0
    fi
  done < <(harness::list_active pid_dir="${PID_DIR}" 2>/dev/null || true)
  return 1
}

if engine_is_alive; then
  if [[ -f "${ORCH_STATE_FILE}" ]]; then
    _done=$(jq '[.items[] | select(.status == "done")] | length' "${ORCH_STATE_FILE}")
    _running=$(jq '[.items[] | select(.status == "running")] | length' "${ORCH_STATE_FILE}")
    _total=$(jq '.items | length' "${ORCH_STATE_FILE}")
    echo "orch: '${SLUG}' is already running (${_done}/${_total} done, ${_running} active)"
  else
    echo "orch: '${SLUG}' is already running"
  fi
  echo "  state:  ${ORCH_STATE_FILE}"
  echo "  log:    ${LOG_FILE}"
  exit 0
fi

# --- Initialize or resume state ---

init_state() {
  PARSED=$("${SCRIPT_DIR}/orch-parse-items.sh" "${SLUG}")
  ITEM_COUNT=$(printf '%s' "${PARSED}" | jq '.items | length')

  if [[ "${ITEM_COUNT}" -eq 0 ]]; then
    echo "error: no items found in plan" >&2
    exit 1
  fi

  orch_ensure_plan_dirs "${SLUG}"
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  MAX_ITER="${MAX_ITERATIONS}"
  ITEMS_JSON=$(printf '%s' "${PARSED}" | jq --argjson maxIter "${MAX_ITER}" '[
	  .items[] | {
	    id: .id,
	    description: .description,
	    deps: .deps,
	    status: (if .checked then "done" else
	      (if (.deps | length) == 0 then "ready" else "queued" end)
	    end),
	    workerPid: null,
	    logPath: null,
	    worktree: null,
	    iteration: 0,
	    maxIterations: $maxIter,
	    lastResult: null,
	    reviewStatus: "pending"
	  }
	]')

  # Build issue number as JSON value (number or null)
  local issue_json="null"
  if [[ -n "${ISSUE_NUMBER}" ]]; then
    issue_json="${ISSUE_NUMBER}"
  fi

  STATE_JSON=$(jq -n \
    --argjson version 1 \
    --arg plan "${SLUG}" \
    --argjson issueNumber "${issue_json}" \
    --argjson maxWorkers "${MAX_WORKERS}" \
    --argjson items "${ITEMS_JSON}" \
    --arg mode "foreground" \
    --arg startedAt "${NOW}" \
    --arg updatedAt "${NOW}" \
    '{
	    version: $version,
	    plan: $plan,
	    issueNumber: $issueNumber,
	    maxParallelWorkers: $maxWorkers,
	    mode: $mode,
	    items: $items,
	    finalReview: { status: "pending", result: null, reworkItems: [] },
	    startedAt: $startedAt,
	    updatedAt: $updatedAt
	  }')

  orch_write_state "${SLUG}" "${STATE_JSON}"
  orch_promote_ready_items "${SLUG}"
}

if [[ -f "${ORCH_STATE_FILE}" ]]; then
  EXISTING_PLAN=$(jq -r '.plan' "${ORCH_STATE_FILE}")
  if [[ "${EXISTING_PLAN}" != "${SLUG}" ]]; then
    init_state
  fi
else
  init_state
fi

# --- Emit plan_start event ---

PLAN_START_EPOCH_MS=$(($(date +%s) * 1000))
_total_items=$(jq '.items | length' "${ORCH_STATE_FILE}")
_mode="foreground"
if [[ "${BACKGROUND}" == true ]]; then
  _mode="background"
fi
_plan_start_kv=(
  slug="${SLUG}"
  total_items:="${_total_items}"
  max_parallel_workers:="${MAX_WORKERS}"
  mode="${_mode}"
)
if [[ -n "${ISSUE_NUMBER}" ]]; then
  _plan_start_kv+=(issue:="${ISSUE_NUMBER}")
fi
harness::emit_event "${EVENTS_FILE}" plan_start "${_plan_start_kv[@]}"
unset _total_items _mode _plan_start_kv

# --- Check if already complete ---

REMAINING_COUNT=$(jq '[.items[] | select(.status != "done")] | length' \
  "${ORCH_STATE_FILE}")
TOTAL_COUNT=$(jq '.items | length' "${ORCH_STATE_FILE}")

if [[ "${REMAINING_COUNT}" -eq 0 ]]; then
  echo "orch: all ${TOTAL_COUNT} items already complete for '${SLUG}'"
  emit_plan_end "completed"
  orch_master_deregister "${SLUG}" "completed"
  orch_cleanup_worktree "${SLUG}"
  exit 0
fi

# --- Create worktree for file isolation ---

orch_create_worktree "${SLUG}" "${ISSUE_NUMBER}"

# --- Copy plan directory into worktree ---

WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"
if [[ "${GH_SYNC}" == true ]]; then
  WORKTREE_PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"
else
  WORKTREE_PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"
fi
mkdir -p "${WORKTREE_PLAN_DIR}"
cp -r "${PLAN_DIR}/"* "${WORKTREE_PLAN_DIR}/"
echo "orch: copied plan into worktree at ${WORKTREE_PLAN_DIR}"

# Copy plan-meta.json into worktree so lifecycle hooks can find it
if [[ -f "${PLAN_META_FILE}" ]]; then
  WORKTREE_META_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"
  mkdir -p "${WORKTREE_META_DIR}"
  cp "${PLAN_META_FILE}" "${WORKTREE_META_DIR}/plan-meta.json"
  echo "orch: copied plan-meta.json into worktree"
fi

# --- Register in master state ---

orch_master_register "${SLUG}"
orch_master_update_progress "${SLUG}"

# --- Spawn the engine via the harness ---

orch_ensure_plan_dirs "${SLUG}"
mkdir -p "${PID_DIR}"

# Clear any stale engine PID sidecar from a previous run so the fresh
# handle is the only one recorded.
rm -f "${PID_DIR}/engine-${SLUG}.pid" "${PID_DIR}/engine-${SLUG}.started_at"

ENGINE_ARGS="${SLUG} --max-workers ${MAX_WORKERS} --max-iterations ${MAX_ITERATIONS}"
if [[ "${BACKGROUND}" == true ]]; then
  ENGINE_ARGS="${ENGINE_ARGS} --background"
fi

ENGINE_CMD="GH_SYNC='${GH_SYNC}' bash '${SCRIPT_DIR}/orch-engine.sh' ${ENGINE_ARGS}"

ENGINE_PID=$(harness::spawn_process \
  role=engine \
  id="${SLUG}" \
  cwd="${REPO_ROOT}" \
  cmd="${ENGINE_CMD}" \
  logfile="${LOG_FILE}" \
  pid_dir="${PID_DIR}" \
  started_at_file="${PID_DIR}/engine-${SLUG}.started_at")

echo "orch: engine spawned (pid ${ENGINE_PID}) — log: ${LOG_FILE}"

# --- Foreground mode: attach the Ink TUI ---
#
# The engine is detached from this shell regardless of BACKGROUND. When
# foreground, we block on the Ink TUI so the user sees live progress;
# closing the TUI (Ctrl-C / q) leaves the engine running. Run `tail -F`
# on the log file, or re-invoke orch-run.sh, to reattach.

launch_tui() {
  local cli_js="${SCRIPT_DIR}/terminal-ui/dist/cli.js"
  local cli_tsx="${SCRIPT_DIR}/terminal-ui/src/cli.tsx"
  if [[ -f "${cli_js}" ]]; then
    exec node "${cli_js}" --orch "${ORCH_STATE_FILE}"
  elif command -v pnpm >/dev/null 2>&1 && [[ -f "${cli_tsx}" ]]; then
    cd "${SCRIPT_DIR}/terminal-ui"
    exec pnpm exec tsx src/cli.tsx --orch "${ORCH_STATE_FILE}"
  else
    echo "orch: TUI not available (build with: pnpm -C scripts/terminal-ui build)"
    echo "orch: tailing engine log — Ctrl-C to detach (engine keeps running)"
    exec tail -n +1 -F "${LOG_FILE}"
  fi
}

if [[ "${BACKGROUND}" == false ]]; then
  launch_tui
fi

# --- Print one-line result and exit (background mode) ---
#
# Emit a plan_end event here so background-mode consumers know the
# orch-run wrapper has returned. The engine emits an authoritative
# plan_end of its own on real completion; per events-schema.md the
# last plan_end line in the stream is authoritative.

emit_plan_end "cancelled"

echo "orch: launched ${SLUG} — tail log: tail -F '${LOG_FILE}'"
echo "orch:                  state:   ${ORCH_STATE_FILE}"
