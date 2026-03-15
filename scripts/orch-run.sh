#!/usr/bin/env bash
# Orchestrator launcher — validates inputs, initializes state, creates tmux
# session, starts the engine as a tmux window, opens the display, prints a
# one-line result, and exits. The calling terminal is free immediately.
#
# The poll loop, worker spawning, review, and cleanup all run inside
# orch-engine.sh in a tmux window named "engine".
#
# Usage: scripts/orch-run.sh <slug> [--max-workers N] [--background]
#
# Options:
#   --max-workers N   Max concurrent workers (default: 4)
#   --background      Headless mode — tmux only, no display windows
#
# Example: scripts/orch-run.sh 20260309-orch-smoke-test
# Example: scripts/orch-run.sh 20260309-orch-smoke-test --background

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

# --- Parse args ---

SLUG=""
MAX_WORKERS=4
BACKGROUND=false

while [[ $# -gt 0 ]]; do
	case "$1" in
	--max-workers)
		MAX_WORKERS="${2:-4}"
		shift 2
		;;
	--background)
		BACKGROUND=true
		shift
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-run.sh <slug> [--max-workers N] [--background]" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-run.sh <slug> [--max-workers N] [--background]" >&2
	exit 1
fi

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

# --- Already-running detection ---

TMUX_SESSION="orch-${SLUG}"

if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
	# Check if the engine window is alive
	if tmux list-windows -t "${TMUX_SESSION}" -F '#{window_name}' 2>/dev/null |
		grep -qx 'engine'; then
		# Engine is running — print status from state.json and exit
		STATE_FILE=$(orch_plan_state_file "${SLUG}")
		if [[ -f "${STATE_FILE}" ]]; then
			_done=$(jq '[.items[] | select(.status == "done")] | length' "${STATE_FILE}")
			_running=$(jq '[.items[] | select(.status == "running")] | length' "${STATE_FILE}")
			_total=$(jq '.items | length' "${STATE_FILE}")
			echo "orch: '${SLUG}' is already running (${_done}/${_total} done, ${_running} active)"
		else
			echo "orch: '${SLUG}' is already running"
		fi
		echo "  attach: tmux attach-session -t '${TMUX_SESSION}'"
		exit 0
	fi
fi

# Per-plan state paths (from orch-state.sh helpers)
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")

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

	MAX_ITER="${MAX_ITERATIONS:-3}"
	ITEMS_JSON=$(printf '%s' "${PARSED}" | jq --argjson maxIter "${MAX_ITER}" '[
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
	    iteration: 0,
	    maxIterations: $maxIter,
	    lastResult: null,
	    reviewStatus: "pending"
	  }
	]')

	STATE_JSON=$(jq -n \
		--argjson version 1 \
		--arg plan "${SLUG}" \
		--argjson maxWorkers "${MAX_WORKERS}" \
		--argjson items "${ITEMS_JSON}" \
		--arg mode "foreground" \
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

# --- Check if already complete ---

REMAINING_COUNT=$(jq '[.items[] | select(.status != "done")] | length' \
	"${ORCH_STATE_FILE}")
TOTAL_COUNT=$(jq '.items | length' "${ORCH_STATE_FILE}")

if [[ "${REMAINING_COUNT}" -eq 0 ]]; then
	echo "orch: all ${TOTAL_COUNT} items already complete for '${SLUG}'"
	orch_master_deregister "${SLUG}" "completed"
	orch_cleanup_worktree "${SLUG}"
	exit 0
fi

# --- Create worktree for file isolation ---

orch_create_worktree "${SLUG}"

# --- Register in master state ---

orch_master_register "${SLUG}"
orch_master_update_progress "${SLUG}"

# --- Create tmux session with dashboard ---

if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
	TERMINAL_UI_CLI="${SCRIPT_DIR}/terminal-ui/dist/cli.js"
	DASH_CMD="while true; do node '${TERMINAL_UI_CLI}' --orch '${ORCH_STATE_FILE}' 2>/dev/null; echo '[dashboard restarting in 3s...]'; sleep 3; done"
	tmux new-session -d -s "${TMUX_SESSION}" -n "dashboard" "${DASH_CMD}"
fi

# --- Start engine as a tmux window ---

ENGINE_ARGS="${SLUG} --max-workers ${MAX_WORKERS}"
if [[ "${BACKGROUND}" == true ]]; then
	ENGINE_ARGS="${ENGINE_ARGS} --background"
fi

LOG_FILE=$(orch_plan_log_file "${SLUG}")
orch_ensure_plan_dirs "${SLUG}"

tmux new-window -d -t "${TMUX_SESSION}" -n "engine" \
	"cd '${REPO_ROOT}' && bash '${SCRIPT_DIR}/orch-engine.sh' ${ENGINE_ARGS} 2>&1 | tee '${LOG_FILE}'; echo '--- engine exited ---'; sleep 30"

# --- Open display windows (foreground mode) ---

if [[ "${BACKGROUND}" == false ]]; then
	bash "${SCRIPT_DIR}/orch-display.sh" "${TMUX_SESSION}" || true
fi

# --- Print one-line result and exit ---

echo "orch: launched ${SLUG} — attach with: tmux attach -t ${TMUX_SESSION}"
