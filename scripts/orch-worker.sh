#!/usr/bin/env bash
# Per-item worker wrapper for the orchestrator.
# Builds a focused prompt scoped to ONE item, runs claude -p,
# then writes a done-file for the orchestrator to read.
#
# Usage: scripts/orch-worker.sh <slug> --item N
#   slug: exec-plan directory name (e.g., 20260307-mcp-server)
#   N:    1-indexed item id from state.json
#
# The worker does NOT update state.json directly — it writes a
# done-file at .orchestrator/done/<slug>/item-N.txt so the
# orchestrator can read it without concurrent-write conflicts.
#
# Requires: jq, claude CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Parse args ---

SLUG=""
ITEM_ID=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--item)
		ITEM_ID="${2:-}"
		shift 2
		;;
	-*)
		echo "error: unknown option: $1" >&2
		echo "usage: orch-worker.sh <slug> --item N" >&2
		exit 1
		;;
	*)
		SLUG="$1"
		shift
		;;
	esac
done

if [[ -z "${SLUG}" || -z "${ITEM_ID}" ]]; then
	echo "error: usage: orch-worker.sh <slug> --item N" >&2
	exit 1
fi

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
ORCH_STATE_FILE="${ORCH_STATE_DIR}/state.json"
PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
DONE_DIR="${ORCH_STATE_DIR}/done/${SLUG}"

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
	echo "error: state file not found: ${ORCH_STATE_FILE}" >&2
	exit 1
fi

if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
	echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
	exit 1
fi

# --- Read item from state ---

ITEM=$(jq -e ".items[] | select(.id == ${ITEM_ID})" "${ORCH_STATE_FILE}" 2>/dev/null)

if [[ -z "${ITEM}" ]]; then
	echo "error: item ${ITEM_ID} not found in ${ORCH_STATE_FILE}" >&2
	exit 1
fi

ITEM_DESC=$(printf '%s' "${ITEM}" | jq -r '.description')
ITEM_DEPS=$(printf '%s' "${ITEM}" | jq -r '.deps[]' 2>/dev/null || true)

echo "orch-worker: item ${ITEM_ID} — ${ITEM_DESC}"

# --- Gather dependency summaries ---

DEP_CONTEXT=""
for dep_id in ${ITEM_DEPS}; do
	done_file="${DONE_DIR}/item-${dep_id}.txt"
	if [[ -f "${done_file}" ]]; then
		dep_desc=$(jq -r ".items[] | select(.id == ${dep_id}) | .description" \
			"${ORCH_STATE_FILE}" 2>/dev/null || true)
		DEP_CONTEXT="${DEP_CONTEXT}
### Item ${dep_id}: ${dep_desc}

$(cat "${done_file}")
"
	fi
done

# --- Build focused worker prompt ---

WORKER_PROMPT="# Orchestrator Worker — Item ${ITEM_ID}

You are a worker agent in an orchestrator pipeline. You work on exactly ONE item.

## Your task

**Item ${ITEM_ID}:** ${ITEM_DESC}

## Plan

Read \`${PLAN_DIR}/plan.md\` for full context — the Approach and Requirements
sections describe the overall design. You only implement item ${ITEM_ID}.

## What to do

1. Read the plan for context on architecture and approach
2. Implement exactly what item ${ITEM_ID} describes: ${ITEM_DESC}
3. When done, mark item ${ITEM_ID} as \`[x]\` in \`${PLAN_DIR}/plan.md\`
4. Write a summary of what you did (see below)

## Summary output

After completing the work, write \`${PLAN_DIR}/work-summary.txt\`:

\`\`\`
ITEM: ${ITEM_ID}
DESCRIPTION: ${ITEM_DESC}

DONE:
- <what you implemented, with file paths>

DECISIONS:
- <any design decisions or tradeoffs>

BLOCKERS:
- <anything blocking, or \"none\">
\`\`\`

Also write a done-file at \`${DONE_DIR}/item-${ITEM_ID}.txt\` with a 3-5 sentence
summary of what changed. This file is read by workers handling dependent items
so they understand what you built.

## Rules

- Work on exactly item ${ITEM_ID} — nothing else
- Do not commit — the orchestrator commits after final review
- Mark the checkbox \`[x]\` in plan.md before stopping
- Write both work-summary.txt and the done-file before stopping
- If blocked, describe the blocker in work-summary.txt and stop"

# Append dependency context if any
if [[ -n "${DEP_CONTEXT}" ]]; then
	WORKER_PROMPT="${WORKER_PROMPT}

## Dependency summaries

These items completed before yours. Use their summaries to understand
what exists and avoid duplicating work.
${DEP_CONTEXT}"
fi

# --- Ensure done directory exists ---

mkdir -p "${DONE_DIR}"

# --- Run worker agent ---

echo "orch-worker: spawning claude for item ${ITEM_ID}..."

RALPH_ROLE=worker RALPH_TASK_DIR="${PLAN_DIR}" RALPH_LOOP=1 \
	env -u CLAUDECODE claude -p \
	--dangerously-skip-permissions \
	"${WORKER_PROMPT}" || {
	EXIT_CODE=$?
	echo "orch-worker: claude exited with code ${EXIT_CODE}" >&2
}

echo "orch-worker: claude finished for item ${ITEM_ID}"

# --- Verify done-file was written ---

if [[ -f "${DONE_DIR}/item-${ITEM_ID}.txt" ]]; then
	echo "orch-worker: done-file written at ${DONE_DIR}/item-${ITEM_ID}.txt"
else
	echo "orch-worker: warning: worker did not write done-file" >&2
	echo "  Writing fallback from work-summary.txt..." >&2

	# Fallback: create done-file from work-summary if it exists
	if [[ -f "${PLAN_DIR}/work-summary.txt" ]]; then
		cp "${PLAN_DIR}/work-summary.txt" "${DONE_DIR}/item-${ITEM_ID}.txt"
	else
		printf 'Item %s completed but no summary was written.\n' "${ITEM_ID}" \
			>"${DONE_DIR}/item-${ITEM_ID}.txt"
	fi
fi

echo "orch-worker: item ${ITEM_ID} complete"
