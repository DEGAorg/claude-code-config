#!/usr/bin/env bash
# List exec plans with status summary.
#
# Usage:
#   scripts/orch-list.sh [--active|--completed|--all]
#     --active     Show only active plans (default)
#     --completed  Show only completed plans
#     --all        Show both active and completed
#
# Output: formatted table matching PlanSummary from orch-types.ts
# Requires: jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLANS_DIR="${REPO_ROOT}/docs/exec-plans"
STATE_DIR="${REPO_ROOT}/.orchestrator"

filter="active"
case "${1:-}" in
--active) filter="active" ;;
--completed) filter="completed" ;;
--all) filter="all" ;;
"") ;;
*)
	echo "error: unknown flag '${1}'" >&2
	echo "usage: orch-list.sh [--active|--completed|--all]" >&2
	exit 1
	;;
esac

# Collect plan dirs to scan
dirs=()
if [[ "${filter}" == "active" || "${filter}" == "all" ]]; then
	if [[ -d "${PLANS_DIR}/active" ]]; then
		for d in "${PLANS_DIR}/active"/*/; do
			[[ -d "${d}" ]] && dirs+=("${d}")
		done
	fi
fi
if [[ "${filter}" == "completed" || "${filter}" == "all" ]]; then
	if [[ -d "${PLANS_DIR}/completed" ]]; then
		for d in "${PLANS_DIR}/completed"/*/; do
			[[ -d "${d}" ]] && dirs+=("${d}")
		done
	fi
fi

if [[ ${#dirs[@]} -eq 0 ]]; then
	echo "No plans found (filter: ${filter})."
	exit 0
fi

# --- Parse a plan.md and count progress items ---

count_items() {
	local plan_file="${1}/plan.md"
	local total=0
	local done_count=0

	if [[ ! -f "${plan_file}" ]]; then
		echo "0 0"
		return
	fi

	local in_progress=false
	local in_fence=false
	while IFS= read -r line; do
		# Track fenced code blocks
		if [[ "${line}" =~ ^\`\`\` ]]; then
			if [[ "${in_fence}" == "true" ]]; then
				in_fence=false
			else
				in_fence=true
			fi
			continue
		fi
		[[ "${in_fence}" == "true" ]] && continue

		# Detect progress log section
		if [[ "${line}" =~ ^##[[:space:]]+Progress ]]; then
			in_progress=true
			continue
		fi
		# Stop at next section
		if [[ "${in_progress}" == "true" && "${line}" =~ ^## ]]; then
			break
		fi

		if [[ "${in_progress}" == "true" ]]; then
			if [[ "${line}" =~ ^-[[:space:]]+\[x\] ]]; then
				((total++)) || true
				((done_count++)) || true
			elif [[ "${line}" =~ ^-[[:space:]]+\[[[:space:]]\] ]]; then
				((total++)) || true
			fi
		fi
	done <"${plan_file}"

	echo "${total} ${done_count}"
}

# --- Read plan status from the Status: line ---

read_plan_status() {
	local plan_file="${1}/plan.md"
	if [[ ! -f "${plan_file}" ]]; then
		echo "unknown"
		return
	fi
	local status_line
	status_line=$(grep -m1 '^\*\*Status:\*\*' "${plan_file}" 2>/dev/null || true)
	if [[ -z "${status_line}" ]]; then
		echo "unknown"
		return
	fi
	# Extract text after **Status:**
	local status="${status_line#\*\*Status:\*\* }"
	echo "${status}"
}

# --- Check orchestrator state for active workers ---

active_workers() {
	local slug="${1}"
	local state_file="${STATE_DIR}/state.json"
	if [[ ! -f "${state_file}" ]]; then
		echo "0"
		return
	fi
	local state_plan
	state_plan=$(jq -r '.plan' "${state_file}")
	if [[ "${state_plan}" != "${slug}" ]]; then
		echo "0"
		return
	fi
	jq '[.items[] | select(.status == "running")] | length' "${state_file}"
}

# --- Determine category (active/completed) from path ---

plan_category() {
	local dir="${1}"
	if [[ "${dir}" == *"/active/"* ]]; then
		echo "active"
	elif [[ "${dir}" == *"/completed/"* ]]; then
		echo "completed"
	else
		echo "other"
	fi
}

# --- Output ---

echo "EXEC PLANS (${filter})"
echo ""
printf "  %-36s %-12s %-18s %-8s %s\n" \
	"SLUG" "CATEGORY" "STATUS" "ITEMS" "WORKERS"
printf "  %-36s %-12s %-18s %-8s %s\n" \
	"------------------------------------" "------------" "------------------" "--------" "-------"

for dir in "${dirs[@]}"; do
	slug=$(basename "${dir}")
	category=$(plan_category "${dir}")
	status=$(read_plan_status "${dir}")
	read -r total done_count <<<"$(count_items "${dir}")"
	workers=$(active_workers "${slug}")

	items_display="${done_count}/${total}"
	workers_display="${workers}"
	if [[ "${workers}" == "0" ]]; then
		workers_display="—"
	fi

	printf "  %-36s %-12s %-18s %-8s %s\n" \
		"${slug}" "${category}" "${status}" "${items_display}" "${workers_display}"
done

echo ""
