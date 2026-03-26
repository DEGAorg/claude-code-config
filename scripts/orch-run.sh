#!/usr/bin/env bash
# Orchestrator launcher — validates inputs, initializes state, creates tmux
# session, starts the engine as a tmux window, opens the display, prints a
# one-line result, and exits. The calling terminal is free immediately.
#
# The poll loop, worker spawning, review, and cleanup all run inside
# orch-engine.sh in a tmux window named "engine".
#
# Usage: scripts/orch-run.sh <slug> [--issue N] [--max-workers N] [--max-iterations N] [--background]
#
# Options:
#   --issue N            Fetch plan from GitHub Issue #N instead of local plan.md
#   --max-workers N      Max concurrent workers (default: 4)
#   --max-iterations N   Max review/rework iterations per item (default: 3)
#   --background         Headless mode — tmux only, no display windows
#
# Example: scripts/orch-run.sh 20260309-orch-smoke-test
# Example: scripts/orch-run.sh 20260309-orch-smoke-test --issue 42
# Example: scripts/orch-run.sh 20260309-orch-smoke-test --background

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=read-github-config.sh
source "${SCRIPT_DIR}/read-github-config.sh"

# --- Check dependencies ---

check_deps() {
	local missing=()
	for cmd in jq tmux node; do
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
		echo "usage: orch-run.sh <slug> [--issue N] [--max-workers N] [--max-iterations N] [--background]" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-run.sh <slug> [--issue N] [--max-workers N] [--max-iterations N] [--background]" >&2
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
	    tmuxPane: null,
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

# --- Create tmux session with dashboard ---

if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
	TERMINAL_UI_CLI="${SCRIPT_DIR}/terminal-ui/dist/cli.js"
	DASH_CMD="while true; do node '${TERMINAL_UI_CLI}' --orch '${ORCH_STATE_FILE}' 2>/dev/null; echo '[dashboard restarting in 3s...]'; sleep 3; done"
	tmux new-session -d -s "${TMUX_SESSION}" -n "dashboard" "${DASH_CMD}"

	# Inject env vars into the tmux session so all windows (engine, workers,
	# reviewers, verifiers) inherit them regardless of how tmux was started.
	tmux set-environment -t "${TMUX_SESSION}" GH_SYNC "${GH_SYNC}"
	tmux set-environment -t "${TMUX_SESSION}" REPO_ROOT "${REPO_ROOT}"
	tmux set-environment -t "${TMUX_SESSION}" SLUG "${SLUG}"
	tmux set-environment -t "${TMUX_SESSION}" ORCH_STATE_DIR "${ORCH_STATE_DIR}"
fi

# --- Start engine as a tmux window ---

ENGINE_ARGS="${SLUG} --max-workers ${MAX_WORKERS} --max-iterations ${MAX_ITERATIONS}"
if [[ "${BACKGROUND}" == true ]]; then
	ENGINE_ARGS="${ENGINE_ARGS} --background"
fi

LOG_FILE=$(orch_plan_log_file "${SLUG}")
orch_ensure_plan_dirs "${SLUG}"

tmux new-window -d -t "${TMUX_SESSION}" -n "engine" \
	"cd '${REPO_ROOT}' && GH_SYNC='${GH_SYNC}' bash '${SCRIPT_DIR}/orch-engine.sh' ${ENGINE_ARGS} 2>&1 | tee '${LOG_FILE}'; echo '--- engine exited ---'; sleep 30"

# --- Open display windows (foreground mode) ---

if [[ "${BACKGROUND}" == false ]]; then
	bash "${SCRIPT_DIR}/orch-display.sh" "${TMUX_SESSION}" || true
fi

# --- Print one-line result and exit ---

echo "orch: launched ${SLUG} — attach with: tmux attach -t ${TMUX_SESSION}"
