#!/usr/bin/env bash
# Pop the next unreviewed handoff item and write it to .ralph-state.json.
# Usage: scripts/review-advance.sh <task-dir>
# Exits 0 if an unreviewed item was found; exits 1 if all items reviewed.

set -euo pipefail

TASK_DIR="${1:-}"

if [[ -z "${TASK_DIR}" ]]; then
  echo "error: usage: scripts/review-advance.sh <task-dir>" >&2
  exit 1
fi

HANDOFF_FILE="${TASK_DIR}/context-handoff.txt"
STATE_FILE="${TASK_DIR}/.ralph-state.json"
REVIEW_DIR="${TASK_DIR}/reviews"

if [[ ! -f "${HANDOFF_FILE}" ]]; then
  echo "error: handoff file not found: ${HANDOFF_FILE}" >&2
  exit 1
fi

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "error: state file not found: ${STATE_FILE}" >&2
  exit 1
fi

mkdir -p "${REVIEW_DIR}"

# Parse context-handoff.txt into numbered items.
# Format: entries delimited by "--- item: <text> ---" with handoff body between.
ITEM_NUM=0
CURRENT_TEXT=""
CURRENT_HANDOFF=""
IN_ITEM=false

while IFS= read -r line; do
  if [[ "${line}" =~ ^---[[:space:]]*item:[[:space:]]*(.*)[[:space:]]*---$ ]]; then
    # New item header — process the previous one if any
    if [[ "${IN_ITEM}" == "true" && -n "${CURRENT_TEXT}" ]]; then
      ITEM_NUM=$((ITEM_NUM + 1))
      if [[ ! -f "${REVIEW_DIR}/item-${ITEM_NUM}-review.txt" ]]; then
        # Found unreviewed item — write to state and exit 0
        HANDOFF_TRIMMED=$(printf '%s' "${CURRENT_HANDOFF}" |
          sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        TMP=$(mktemp)
        jq --arg text "${CURRENT_TEXT}" \
          --argjson num "${ITEM_NUM}" \
          --arg handoff "${HANDOFF_TRIMMED}" \
          '.current_review = {
						"num": $num,
						"text": $text,
						"handoff": $handoff
					}' "${STATE_FILE}" >"${TMP}"
        mv "${TMP}" "${STATE_FILE}"
        exit 0
      fi
    fi
    CURRENT_TEXT="${BASH_REMATCH[1]}"
    CURRENT_TEXT="${CURRENT_TEXT%"${CURRENT_TEXT##*[![:space:]]}"}"
    CURRENT_HANDOFF=""
    IN_ITEM=true
  elif [[ "${line}" == "---" && "${IN_ITEM}" == "true" ]]; then
    # End-of-block marker — ignore (item ends at next header)
    :
  elif [[ "${IN_ITEM}" == "true" ]]; then
    CURRENT_HANDOFF="${CURRENT_HANDOFF}${line}
"
  fi
done <"${HANDOFF_FILE}"

# Process the last item
if [[ "${IN_ITEM}" == "true" && -n "${CURRENT_TEXT}" ]]; then
  ITEM_NUM=$((ITEM_NUM + 1))
  if [[ ! -f "${REVIEW_DIR}/item-${ITEM_NUM}-review.txt" ]]; then
    HANDOFF_TRIMMED=$(printf '%s' "${CURRENT_HANDOFF}" |
      sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    TMP=$(mktemp)
    jq --arg text "${CURRENT_TEXT}" \
      --argjson num "${ITEM_NUM}" \
      --arg handoff "${HANDOFF_TRIMMED}" \
      '.current_review = {
				"num": $num,
				"text": $text,
				"handoff": $handoff
			}' "${STATE_FILE}" >"${TMP}"
    mv "${TMP}" "${STATE_FILE}"
    exit 0
  fi
fi

# All items have review files — done
exit 1
