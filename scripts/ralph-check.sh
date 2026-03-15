#!/usr/bin/env bash
# Ralph Loop health check — project-agnostic.
# Reads success_criteria from dega-core.yaml (falls back to ralph.yaml).
# Run from project root: bash ~/.claude/scripts/ralph-check.sh
# Exit 0 if all criteria pass, exit 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source orch-state.sh for config resolution helpers
# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

PASS=0
FAIL=0
LOG=".ralph-runs.log"
CONFIG_FILE=$(orch_resolve_config)

check() {
	local id="$1"
	local description="$2"
	local cmd="$3"
	if eval "$cmd" &>/dev/null; then
		echo "✓ ${id}: ${description}"
		PASS=$((PASS + 1))
	else
		echo "✗ ${id}: ${description}"
		echo "  → fix: run the failing command and resolve issues"
		FAIL=$((FAIL + 1))
	fi
}

# --- Project success criteria from config file ---

if [[ -n "${CONFIG_FILE}" ]]; then
	# Parse success_criteria entries: extract id, description, check
	# YAML structure is flat single-line values, safe to parse with awk.
	current_id=""
	current_desc=""
	current_check=""

	while IFS= read -r line; do
		# Strip leading whitespace for matching
		trimmed="${line#"${line%%[![:space:]]*}"}"

		if [[ "${trimmed}" =~ ^-\ id:\ (.+) ]]; then
			# If we have a complete previous entry, run it
			if [[ -n "${current_id}" && -n "${current_check}" ]]; then
				check "${current_id}" "${current_desc}" "${current_check}"
			fi
			current_id="${BASH_REMATCH[1]}"
			current_desc=""
			current_check=""
		elif [[ "${trimmed}" =~ ^description:\ (.+) ]]; then
			current_desc="${BASH_REMATCH[1]}"
		elif [[ "${trimmed}" =~ ^check:\ (.+) ]]; then
			current_check="${BASH_REMATCH[1]}"
			# Strip surrounding quotes if present
			current_check="${current_check#\"}"
			current_check="${current_check%\"}"
		fi
	done <"${CONFIG_FILE}"

	# Run the last entry
	if [[ -n "${current_id}" && -n "${current_check}" ]]; then
		check "${current_id}" "${current_desc}" "${current_check}"
	fi
else
	echo "— no dega-core.yaml (or ralph.yaml) found; skipping project checks"
fi

# --- Generic loop-state checks ---

STATE_FILE=$(find docs/exec-plans/active -name '.ralph-state.json' 2>/dev/null | head -1)
if [[ -n "${STATE_FILE}" ]]; then
	CLAIMED=$(jq -r 'if .current_task.claimed_complete == false then "false" else "true" end' "${STATE_FILE}")
	CHANGES=0
	if git rev-parse HEAD >/dev/null 2>&1; then
		CHANGES=$(git diff HEAD --name-only 2>/dev/null | wc -l | tr -d ' ')
	fi
	if [[ "${CHANGES}" -gt 0 && "${CLAIMED}" == "false" ]]; then
		echo "✗ task-claimed: files changed but current task not marked complete"
		echo "  → fix: run: bash ${SCRIPT_DIR}/task-complete.sh ${STATE_FILE}"
		FAIL=$((FAIL + 1))
	else
		echo "✓ task-claimed: no uncommitted work without task signal"
		PASS=$((PASS + 1))
	fi

	# Block Stop if handoff entry not written for current task
	CURRENT_TASK=$(jq -r '.current_task.text // ""' "${STATE_FILE}")
	if [[ -n "${CURRENT_TASK}" && "${CHANGES}" -gt 0 ]]; then
		HANDOFF_FILE="$(dirname "${STATE_FILE}")/context-handoff.txt"
		if ! grep -qF "item: ${CURRENT_TASK}" "${HANDOFF_FILE}" 2>/dev/null; then
			echo "✗ handoff-entry: no handoff entry for current task"
			echo "  → fix: append an entry to context-handoff.txt"
			echo "  format: --- item: ${CURRENT_TASK} ---"
			FAIL=$((FAIL + 1))
		else
			echo "✓ handoff-entry: context-handoff.txt has entry for current task"
			PASS=$((PASS + 1))
		fi
	fi
fi

# --- Summary ---

TOTAL=$((PASS + FAIL))
echo ""
if [ "$FAIL" -eq 0 ]; then
	RESULT="PASS ${PASS}/${TOTAL}"
	echo "RESULT: ${PASS}/${TOTAL} criteria passing. All done."
else
	RESULT="FAIL ${PASS}/${TOTAL}"
	echo "RESULT: ${PASS}/${TOTAL} criteria passing. Keep working."
fi

# Append run record to log
echo "$(date '+%Y-%m-%d %H:%M:%S') | ${RESULT}" >>"${LOG}"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
