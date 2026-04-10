#!/usr/bin/env bash
set -euo pipefail

# Stop hook: block reviewer exit if required review file was not written.
# Only active when RALPH_ROLE=reviewer (set by ralph-loop.sh).
#
# Two modes:
#   Per-item: RALPH_REVIEW_ITEM is set → enforce reviews/item-N-review.txt
#   Final:    RALPH_REVIEW_ITEM unset  → enforce review-result.txt

[[ "${RALPH_ROLE:-}" == "reviewer" ]] || exit 0

TASK_DIR="${RALPH_TASK_DIR:-}"
[[ -n "${TASK_DIR}" ]] || exit 0

# Per-item reviewer: check for reviews/item-N-review.txt
if [[ -n "${RALPH_REVIEW_ITEM:-}" ]]; then
  REVIEW_FILE="${TASK_DIR}/reviews/item-${RALPH_REVIEW_ITEM}-review.txt"
  if [[ ! -f "${REVIEW_FILE}" ]]; then
    cat >&2 <<MSG
STOP BLOCKED: You must write ${REVIEW_FILE} before exiting.

This per-item review file is required — the Ralph Loop cannot proceed
without your review of item ${RALPH_REVIEW_ITEM}.

Write the file now using the Write tool, then you may exit.
MSG
    exit 2
  fi
  exit 0
fi

# Final reviewer: check for review-result.txt
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
