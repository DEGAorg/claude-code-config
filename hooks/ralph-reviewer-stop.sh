#!/usr/bin/env bash
set -euo pipefail

# Stop hook: block reviewer exit if review-result.txt was not written.
# Only active when RALPH_ROLE=reviewer (set by ralph-loop.sh).

[[ "${RALPH_ROLE:-}" == "reviewer" ]] || exit 0

TASK_DIR="${RALPH_TASK_DIR:-}"
[[ -n "${TASK_DIR}" ]] || exit 0

RESULT_FILE="${TASK_DIR}/review-result.txt"
if [[ ! -f "${RESULT_FILE}" ]]; then
	cat >&2 <<MSG
STOP BLOCKED: You must write ${RESULT_FILE} before exiting.

The first line must be exactly one of: SHIP, REVISE, or BLOCKED.
This file is required — the Ralph Loop cannot proceed without your decision.

Write the file now using the Write tool, then you may exit.
MSG
	exit 2
fi

# Validate content — first line must be SHIP, REVISE, or BLOCKED
FIRST_LINE=$(head -1 "${RESULT_FILE}" | tr -d '[:space:]')
if [[ "${FIRST_LINE}" != "SHIP" && "${FIRST_LINE}" != "REVISE" && "${FIRST_LINE}" != "BLOCKED" ]]; then
	cat >&2 <<MSG
STOP BLOCKED: ${RESULT_FILE} has invalid content.

First line is: "${FIRST_LINE}"
Expected exactly one of: SHIP, REVISE, or BLOCKED.

Fix the file, then you may exit.
MSG
	exit 2
fi
