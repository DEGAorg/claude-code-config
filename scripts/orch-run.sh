#!/usr/bin/env bash
# Orchestrator launcher — spawns workers in tmux panes by dependency wave.
#
# Reads state.json for incomplete items (or initializes from plan.md),
# then launches claude workers in tmux panes grouped by dependency waves.
#
# Usage: scripts/orch-run.sh <slug> [--max-workers N]
#
# Example: scripts/orch-run.sh 20260309-orch-smoke-test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

# --- Parse args ---

SLUG=""
MAX_WORKERS=4

while [[ $# -gt 0 ]]; do
	case "$1" in
	--max-workers)
		MAX_WORKERS="${2:-4}"
		shift 2
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-run.sh <slug> [--max-workers N]" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" ]]; then
	echo "error: usage: orch-run.sh <slug> [--max-workers N]" >&2
	exit 1
fi

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_STATE_DIR}/state.json"

# --- Initialize or resume state ---

init_state() {
	PARSED=$("${SCRIPT_DIR}/orch-parse-items.sh" "${SLUG}")
	ITEM_COUNT=$(printf '%s' "${PARSED}" | jq '.items | length')

	if [[ "${ITEM_COUNT}" -eq 0 ]]; then
		echo "error: no items found in plan" >&2
		exit 1
	fi

	orch_ensure_done_dir "${SLUG}"
	NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	ITEMS_JSON=$(printf '%s' "${PARSED}" | jq '[
	  .items[] | {
	    id: .id,
	    description: .description,
	    deps: .deps,
	    status: (if .checked then "done" else
	      (if (.deps | length) == 0 then "ready" else "queued" end)
	    end)
	  }
	]')

	# Promote queued items whose deps are all done
	ITEMS_JSON=$(printf '%s' "${ITEMS_JSON}" | jq '[
	  . as $all |
	  .[] | . as $item |
	  if $item.status == "queued" then
	    if ([$all[] | select(.id == ($item.deps[])) | .status] | all(. == "done")) then
	      .status = "ready"
	    else .
	    end
	  else .
	  end
	]')

	STATE_JSON=$(jq -n \
		--argjson version 1 \
		--arg plan "${SLUG}" \
		--argjson maxWorkers "${MAX_WORKERS}" \
		--argjson items "${ITEMS_JSON}" \
		--arg startedAt "${NOW}" \
		--arg updatedAt "${NOW}" \
		'{
	    version: $version,
	    plan: $plan,
	    maxParallelWorkers: $maxWorkers,
	    items: $items,
	    startedAt: $startedAt,
	    updatedAt: $updatedAt
	  }')

	orch_write_state "${STATE_JSON}"
	echo "orch-run: initialized ${ITEM_COUNT} items for '${SLUG}'"
}

if [[ -f "${ORCH_STATE_FILE}" ]]; then
	EXISTING_PLAN=$(jq -r '.plan' "${ORCH_STATE_FILE}")
	if [[ "${EXISTING_PLAN}" == "${SLUG}" ]]; then
		echo "orch-run: resuming plan '${SLUG}' from existing state"
	else
		echo "orch-run: state.json is for '${EXISTING_PLAN}', re-initializing for '${SLUG}'"
		init_state
	fi
else
	echo "orch-run: initializing state for plan '${SLUG}'"
	init_state
fi

# --- Read incomplete items from state ---

REMAINING_JSON=$(jq '[.items[] | select(.status != "done")]' "${ORCH_STATE_FILE}")
REMAINING_COUNT=$(printf '%s' "${REMAINING_JSON}" | jq 'length')
TOTAL_COUNT=$(jq '.items | length' "${ORCH_STATE_FILE}")
DONE_COUNT=$(jq '[.items[] | select(.status == "done")] | length' "${ORCH_STATE_FILE}")

if [[ "${REMAINING_COUNT}" -eq 0 ]]; then
	echo "orch-run: all ${TOTAL_COUNT} items already complete"
	exit 0
fi

echo "orch-run: ${DONE_COUNT}/${TOTAL_COUNT} done, ${REMAINING_COUNT} remaining"

# --- Gather done-file summaries for completed items ---

DONE_DIR="${ORCH_STATE_DIR}/done/${SLUG}"
COMPLETED_CONTEXT=""

DONE_IDS=$(jq -r '.items[] | select(.status == "done") | .id' "${ORCH_STATE_FILE}")
for done_id in ${DONE_IDS}; do
	done_file="${DONE_DIR}/item-${done_id}.txt"
	if [[ -f "${done_file}" ]]; then
		done_desc=$(jq -r ".items[] | select(.id == ${done_id}) | .description" \
			"${ORCH_STATE_FILE}")
		COMPLETED_CONTEXT="${COMPLETED_CONTEXT}
### Item ${done_id}: ${done_desc}
$(cat "${done_file}")
"
	fi
done

# --- Build remaining items description ---

ITEMS_DESC=""
while IFS= read -r item_json; do
	item_id=$(printf '%s' "${item_json}" | jq -r '.id')
	item_desc=$(printf '%s' "${item_json}" | jq -r '.description')
	item_deps=$(printf '%s' "${item_json}" | jq -r '.deps | if length > 0 then map(tostring) | join(", ") else "none" end')
	ITEMS_DESC="${ITEMS_DESC}
- **Item ${item_id}**: ${item_desc} (deps: ${item_deps})"
done < <(printf '%s' "${REMAINING_JSON}" | jq -c '.[]')

# --- TODO: tmux wave-based execution engine ---
# The execution engine (tmux session, pane spawning, wave polling,
# done-file detection, state sync) will be implemented in the
# orchestrator rebuild plan (20260310-orch-tmux-rebuild).

echo ""
echo "orch-run: execution engine not yet implemented (tmux rewrite pending)"
echo "  plan: ${SLUG}"
echo "  items: ${REMAINING_COUNT} remaining, ${DONE_COUNT} done"
echo "  max workers: ${MAX_WORKERS}"
echo ""
exit 1
