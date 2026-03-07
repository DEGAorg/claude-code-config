#!/usr/bin/env bash
# Show orchestrator status — items, workers, progress.
# Syncs state from per-item files and detects dead workers.
#
# Usage:
#   scripts/orch-status.sh [<slug>]
#     slug: exec-plan directory name. If omitted, uses plan from state.json.
#
# Output: formatted table of items with status, iteration, worker info.
# Requires: jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_STATE_DIR}/state.json"

SLUG="${1:-}"

# --- Validate state ---

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
	echo "error: no state file at ${ORCH_STATE_FILE}" >&2
	echo "hint: run orch-start.sh first" >&2
	exit 1
fi

STATE_PLAN=$(orch_get_plan)

if [[ -n "${SLUG}" && "${STATE_PLAN}" != "${SLUG}" ]]; then
	echo "error: state file is for plan '${STATE_PLAN}', not '${SLUG}'" >&2
	exit 1
fi

SLUG="${STATE_PLAN}"

# --- Display ---

display_status() {
	local state
	state=$(cat "${ORCH_STATE_FILE}")

	local mode
	mode=$(printf '%s' "${state}" | jq -r '.mode')
	local max_workers
	max_workers=$(printf '%s' "${state}" | jq -r '.maxParallelWorkers')
	local updated_at
	updated_at=$(printf '%s' "${state}" | jq -r '.updatedAt // "unknown"')

	local total cnt_done running ready queued stopped
	total=$(printf '%s' "${state}" | jq '.items | length')
	cnt_done=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "done")] | length')
	running=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "running")] | length')
	ready=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "ready")] | length')
	queued=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "queued")] | length')
	stopped=$(printf '%s' "${state}" | jq '[.items[] | select(.status == "stopped")] | length')

	local final_status
	final_status=$(printf '%s' "${state}" | jq -r '.finalReview.status // "pending"')
	local final_result
	final_result=$(printf '%s' "${state}" | jq -r '.finalReview.result // "—"')

	echo "ORCHESTRATOR: ${SLUG}"
	echo "  mode: ${mode}  max-workers: ${max_workers}  updated: ${updated_at}"
	echo "  items: ${total}  done: ${cnt_done}  running: ${running}  ready: ${ready}  queued: ${queued}  stopped: ${stopped}"
	echo "  final review: ${final_status} (${final_result})"
	echo ""

	# Table header
	printf "  %-4s %-50s %-10s %-6s %-12s\n" "#" "ITEM" "STATUS" "ITER" "WORKER"
	printf "  %-4s %-50s %-10s %-6s %-12s\n" "---" "--------------------------------------------------" "----------" "------" "------------"

	# Table rows
	printf '%s' "${state}" | jq -r '.items[] |
    [
      (.id | tostring),
      (if (.description | length) > 48 then (.description[:48] + "..") else .description end),
      .status,
      ((.iteration | tostring) + "/" + (.maxIterations | tostring)),
      (if .tmuxPane then .tmuxPane
       elif .worktree then "worktree"
       else "—" end)
    ] | @tsv' | while IFS=$'\t' read -r id desc status iter worker; do
		printf "  %-4s %-50s %-10s %-6s %-12s\n" "${id}" "${desc}" "${status}" "${iter}" "${worker}"
	done

	echo ""

	# Show deps for queued items
	local queued_with_deps
	queued_with_deps=$(printf '%s' "${state}" | jq -r '
    .items[] | select(.status == "queued" and (.deps | length) > 0) |
    "  item \(.id) blocked on: \(.deps | map(tostring) | join(", "))"')

	if [[ -n "${queued_with_deps}" ]]; then
		echo "Blocked items:"
		echo "${queued_with_deps}"
		echo ""
	fi
}

# --- Main ---

orch_sync_item_state "${SLUG}"
orch_prune_dead_workers "${SLUG}"
display_status
