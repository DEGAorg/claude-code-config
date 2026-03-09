#!/usr/bin/env bash
# Thin orchestrator launcher — delegates execution to Claude Agent Teams.
#
# Reads state.json for incomplete items (or initializes from plan.md),
# builds an orchestrator prompt, and launches claude with Agent Teams
# enabled. Claude's orchestrator agent creates a team of workers
# that execute items in dependency order.
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

# --- Build orchestrator prompt ---

AGENT_DEF="${REPO_ROOT}/agents/orch-lead.md"
if [[ ! -f "${AGENT_DEF}" ]]; then
	echo "error: agent definition not found: ${AGENT_DEF}" >&2
	exit 1
fi

ORCH_PROMPT="$(cat "${AGENT_DEF}")

## Session context

Plan path: \`${PLAN_DIR}/plan.md\`
State file: \`${ORCH_STATE_FILE}\`
Done-files directory: \`${DONE_DIR}/\`
Scripts directory: \`${SCRIPT_DIR}\`
Max parallel workers: ${MAX_WORKERS}
Progress: ${DONE_COUNT}/${TOTAL_COUNT} items complete.

## Remaining items
${ITEMS_DESC}

## What to do now

1. Create team members for all items in wave 1 (deps satisfied).
2. Wait for them to complete.
3. Start wave 2 items whose deps are now done.
4. Repeat until all items are complete.
5. When all items are done, update state and report final status."

# Append completed item context if resuming
if [[ -n "${COMPLETED_CONTEXT}" ]]; then
	ORCH_PROMPT="${ORCH_PROMPT}

## Completed item summaries

These items are already done. Workers for dependent items should
read these to understand what exists.
${COMPLETED_CONTEXT}"
fi

# --- Launch claude with Agent Teams ---

echo ""
echo "orch-run: launching claude with Agent Teams for '${SLUG}'"
echo "  items: ${REMAINING_COUNT} remaining, ${DONE_COUNT} done"
echo "  max workers: ${MAX_WORKERS}"
echo ""

CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
	env -u CLAUDECODE claude -p \
	--dangerously-skip-permissions \
	"${ORCH_PROMPT}" || {
	EXIT_CODE=$?
	echo "orch-run: claude exited with code ${EXIT_CODE}" >&2
	exit "${EXIT_CODE}"
}

echo ""
echo "orch-run: claude finished for plan '${SLUG}'"

# --- Post-run: sync state ---

orch_sync_done_files "${SLUG}"
FINAL_DONE=$(orch_count_by_status "done")
echo "orch-run: final state — ${FINAL_DONE}/${TOTAL_COUNT} items done"
