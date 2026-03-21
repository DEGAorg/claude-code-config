#!/usr/bin/env bash
set -euo pipefail

# Post formatted milestone comments and update labels on a GitHub Issue.
#
# Usage: scripts/gh-plan-sync.sh <event> <slug> [options]
#
# Events:
#   start   — plan execution started (label → plan:active, post start comment)
#   review  — per-item review result (post item review comment)
#   ship    — plan completed successfully (label → plan:completed, close issue)
#   revise  — plan failed after max iterations (label → plan:failed, post failure comment)
#
# Options:
#   --issue <number>          GitHub Issue number (required)
#   --repo <owner/repo>       GitHub repo (default: auto-detect from git remote)
#   --items <total>           Total item count (for start/ship/revise)
#   --max-workers <n>         Max workers (for start comment)
#   --item-id <id>            Item ID (for review event)
#   --item-desc <desc>        Item description (for review event)
#   --item-result <SHIP|REVISE>  Review result (for review event)
#   --iterations <n>          Iteration count for item (for review event)
#   --feedback <text>         Reviewer feedback summary (for review REVISE)
#   --passed <n>              Items passed (for ship/revise)
#   --failed <n>              Items failed (for revise)
#   --failed-details <text>   Failed item details (for revise)
#   --rework-count <n>        Items that required rework (for ship)
#   --total-reviews <n>       Total review iterations (for ship)
#   --elapsed <duration>      Elapsed time string (for ship/revise)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=ensure-gh.sh
source "${SCRIPT_DIR}/ensure-gh.sh"
# shellcheck source=read-github-config.sh
source "${SCRIPT_DIR}/read-github-config.sh"

# --- Parse args ---

EVENT=""
SLUG=""
ISSUE=""
REPO=""
ITEMS=""
MAX_WORKERS=""
ITEM_ID=""
ITEM_DESC=""
ITEM_RESULT=""
ITERATIONS=""
FEEDBACK=""
PASSED=""
FAILED=""
FAILED_DETAILS=""
REWORK_COUNT=""
TOTAL_REVIEWS=""
ELAPSED=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--issue)
		ISSUE="${2:?--issue requires a value}"
		shift 2
		;;
	--repo)
		REPO="${2:?--repo requires a value}"
		shift 2
		;;
	--items)
		ITEMS="${2:?--items requires a value}"
		shift 2
		;;
	--max-workers)
		MAX_WORKERS="${2:?--max-workers requires a value}"
		shift 2
		;;
	--item-id)
		ITEM_ID="${2:?--item-id requires a value}"
		shift 2
		;;
	--item-desc)
		ITEM_DESC="${2:?--item-desc requires a value}"
		shift 2
		;;
	--item-result)
		ITEM_RESULT="${2:?--item-result requires a value}"
		shift 2
		;;
	--iterations)
		ITERATIONS="${2:?--iterations requires a value}"
		shift 2
		;;
	--feedback)
		FEEDBACK="${2:?--feedback requires a value}"
		shift 2
		;;
	--passed)
		PASSED="${2:?--passed requires a value}"
		shift 2
		;;
	--failed)
		FAILED="${2:?--failed requires a value}"
		shift 2
		;;
	--failed-details)
		FAILED_DETAILS="${2:?--failed-details requires a value}"
		shift 2
		;;
	--rework-count)
		REWORK_COUNT="${2:?--rework-count requires a value}"
		shift 2
		;;
	--total-reviews)
		TOTAL_REVIEWS="${2:?--total-reviews requires a value}"
		shift 2
		;;
	--elapsed)
		ELAPSED="${2:?--elapsed requires a value}"
		shift 2
		;;
	-*)
		echo "error: unknown option: $1" >&2
		exit 1
		;;
	*)
		if [[ -z "${EVENT}" ]]; then
			EVENT="$1"
		elif [[ -z "${SLUG}" ]]; then
			SLUG="$1"
		else
			echo "error: unexpected argument: $1" >&2
			exit 1
		fi
		shift
		;;
	esac
done

# --- Validate ---

if [[ -z "${EVENT}" ]]; then
	echo "error: event type required (start, review, ship, revise)" >&2
	exit 1
fi

if [[ -z "${SLUG}" ]]; then
	echo "error: slug required" >&2
	exit 1
fi

# Auto-discover issue number from plan-meta.json if --issue not provided
if [[ -z "${ISSUE}" ]]; then
	REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
	ORCH_DIR="${REPO_ROOT}/.orchestrator"

	# Search .orchestrator/plans/<slug>/plan-meta.json (main repo)
	META_FILE="${ORCH_DIR}/plans/${SLUG}/plan-meta.json"
	if [[ -f "${META_FILE}" ]]; then
		ISSUE=$(jq -r '.issue_number // empty' "${META_FILE}")
	fi

	# Fallback: worktree copy of plan-meta.json
	if [[ -z "${ISSUE}" ]]; then
		WT_META="${ORCH_DIR}/worktrees/${SLUG}/.orchestrator/plans/${SLUG}/plan-meta.json"
		if [[ -f "${WT_META}" ]]; then
			ISSUE=$(jq -r '.issue_number // empty' "${WT_META}")
		fi
	fi

	if [[ -z "${ISSUE}" ]]; then
		echo "error: --issue <number> required (no plan-meta.json found for slug '${SLUG}')" >&2
		exit 1
	fi
fi

case "${EVENT}" in
start | review | ship | revise) ;;
*)
	echo "error: unknown event type: ${EVENT}" >&2
	echo "  Valid events: start, review, ship, revise" >&2
	exit 1
	;;
esac

# --- Ensure gh is available and authenticated ---

ensure_gh

if ! gh auth status &>/dev/null; then
	echo "error: gh is not authenticated. Run: gh auth login" >&2
	echo "Then re-run this command." >&2
	exit 1
fi

# --- Resolve repo ---

REPO="$(gh_resolve_repo "${REPO}")"

# --- Label helpers ---

PLAN_LABELS=("plan:draft" "plan:active" "plan:review" "plan:completed" "plan:failed")

remove_plan_labels() {
	local current_labels
	current_labels="$(gh issue view "${ISSUE}" --repo "${REPO}" \
		--json labels -q '[.labels[].name] | join(",")')"
	for label in "${PLAN_LABELS[@]}"; do
		if [[ ",${current_labels}," == *",${label},"* ]]; then
			gh issue edit "${ISSUE}" --repo "${REPO}" \
				--remove-label "${label}" >/dev/null 2>&1 || true
		fi
	done
}

set_label() {
	local target_label="$1"
	# Skip label management if labels disabled in config
	if [[ "$(gh_config_value labels)" == "false" ]]; then
		return 0
	fi
	remove_plan_labels
	gh issue edit "${ISSUE}" --repo "${REPO}" \
		--add-label "${target_label}" >/dev/null
}

# --- Comment helpers ---

post_comment() {
	local body="$1"
	# Skip comments if disabled in config
	if [[ "$(gh_config_value comments)" == "false" ]]; then
		return 0
	fi
	gh issue comment "${ISSUE}" --repo "${REPO}" --body "${body}"
}

# --- Event handlers ---

handle_start() {
	set_label "plan:active"

	local body="**Plan started** for \`${SLUG}\`."
	if [[ -n "${ITEMS}" ]]; then
		body="${body}"$'\n'"${ITEMS} items"
		if [[ -n "${MAX_WORKERS}" ]]; then
			body="${body}, ${MAX_WORKERS} max workers."
		else
			body="${body}."
		fi
	fi

	post_comment "${body}"
	echo "Posted start comment on issue #${ISSUE}." >&2
}

handle_review() {
	set_label "plan:review"

	if [[ -z "${ITEM_ID}" || -z "${ITEM_RESULT}" ]]; then
		echo "error: review event requires --item-id and --item-result" >&2
		exit 1
	fi

	local desc_part=""
	if [[ -n "${ITEM_DESC}" ]]; then
		desc_part=" \"${ITEM_DESC}\""
	fi

	local iter_part=""
	if [[ -n "${ITERATIONS}" ]]; then
		iter_part=" after ${ITERATIONS} iteration(s)"
	fi

	local body="**Item ${ITEM_ID}**${desc_part} — **${ITEM_RESULT}**${iter_part}."

	if [[ "${ITEM_RESULT}" == "REVISE" && -n "${FEEDBACK}" ]]; then
		body="${body}"$'\n'"Feedback: ${FEEDBACK}"
	fi

	post_comment "${body}"
	echo "Posted review comment for item ${ITEM_ID} on issue #${ISSUE}." >&2
}

handle_ship() {
	set_label "plan:completed"

	local body="**Plan SHIP.** "
	if [[ -n "${PASSED}" && -n "${ITEMS}" ]]; then
		body="${body}${PASSED}/${ITEMS} items passed."
	fi
	if [[ -n "${REWORK_COUNT}" && "${REWORK_COUNT}" -gt 0 ]]; then
		body="${body} ${REWORK_COUNT} item(s) required rework"
		if [[ -n "${TOTAL_REVIEWS}" ]]; then
			body="${body} (${TOTAL_REVIEWS} total review iterations)"
		fi
		body="${body}."
	fi
	if [[ -n "${ELAPSED}" ]]; then
		body="${body} Elapsed: ${ELAPSED}."
	fi

	post_comment "${body}"

	# Close the issue on SHIP unless close_on_ship is disabled
	if [[ "$(gh_config_value close_on_ship)" != "false" ]]; then
		gh issue close "${ISSUE}" --repo "${REPO}" >/dev/null
		echo "Posted SHIP comment and closed issue #${ISSUE}." >&2
	else
		echo "Posted SHIP comment on issue #${ISSUE}." >&2
	fi
}

handle_revise() {
	set_label "plan:failed"

	local body="**Plan REVISE.** "
	if [[ -n "${PASSED}" && -n "${ITEMS}" ]]; then
		body="${body}${PASSED}/${ITEMS} items passed."
	fi
	if [[ -n "${FAILED}" && "${FAILED}" -gt 0 ]]; then
		body="${body} ${FAILED} failed after max iterations."
	fi
	if [[ -n "${FAILED_DETAILS}" ]]; then
		body="${body} Failed: ${FAILED_DETAILS}."
	fi
	if [[ -n "${ELAPSED}" ]]; then
		body="${body} Elapsed: ${ELAPSED}."
	fi

	post_comment "${body}"
	echo "Posted REVISE comment on issue #${ISSUE}." >&2
}

# --- Dispatch ---

case "${EVENT}" in
start) handle_start ;;
review) handle_review ;;
ship) handle_ship ;;
revise) handle_revise ;;
esac
