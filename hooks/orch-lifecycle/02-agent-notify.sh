#!/usr/bin/env bash
set -euo pipefail

# Lifecycle hook: write agent-bump notifications on terminal events.
#
# Called by orch-engine.sh at milestones with (event, slug, ...extra args).
# On ship, verify (failed only), and revise (engine-bailout only), reads
# state.json and writes .orchestrator/notifications/<slug>.json describing
# the outcome. The companion Stop hook (hooks/stop/01-orch-notify.sh) reads
# these notifications and surfaces them to the agent.
#
# Schema:
#   { slug, status, prUrl?, prNumber?, issueNumber, summary, createdAt, seen }
#
# Skips silently for non-terminal events or when state.json is absent.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

EVENT="${1:?usage: 02-agent-notify.sh <event> <slug> [options]}"
SLUG="${2:?usage: 02-agent-notify.sh <event> <slug> [options]}"
shift 2

ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"
STATE_FILE="${ORCH_STATE_DIR}/plans/${SLUG}/state.json"
NOTIF_DIR="${ORCH_STATE_DIR}/notifications"
NOTIF_FILE="${NOTIF_DIR}/${SLUG}.json"

if [[ ! -f "${STATE_FILE}" ]]; then
  echo "02-agent-notify: no state.json for ${SLUG} — skipping" >&2
  exit 0
fi

# --- Parse extra args passed by engine ---

ITEMS=""
PASSED=""
FAILED=""
ELAPSED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --items)
    ITEMS="${2:-}"
    shift 2
    ;;
  --max-workers)
    shift 2
    ;;
  --passed)
    PASSED="${2:-}"
    shift 2
    ;;
  --failed)
    FAILED="${2:-}"
    shift 2
    ;;
  --elapsed)
    ELAPSED="${2:-}"
    shift 2
    ;;
  *)
    shift
    ;;
  esac
done

ISSUE_NUMBER=$(jq -r '.issueNumber // empty' "${STATE_FILE}")

# Determine notification fields per event. STATUS empty means "skip".
STATUS=""
SUMMARY=""
PR_URL=""
PR_NUMBER=""

case "${EVENT}" in
ship)
  STATUS="completed"
  PR_URL=$(jq -r '.finalReview.prUrl // empty' "${STATE_FILE}")
  PR_NUMBER=$(jq -r '.finalReview.prNumber // empty' "${STATE_FILE}")
  SUMMARY="Plan ${SLUG} shipped"
  if [[ -n "${ITEMS}" && -n "${PASSED}" ]]; then
    SUMMARY="${SUMMARY} (${PASSED}/${ITEMS} items"
    if [[ -n "${ELAPSED}" ]]; then
      SUMMARY="${SUMMARY}, ${ELAPSED}"
    fi
    SUMMARY="${SUMMARY})"
  fi
  if [[ -n "${PR_URL}" ]]; then
    SUMMARY="${SUMMARY} — PR ${PR_URL}"
  fi
  ;;

verify)
  VERIFY_STATUS=$(jq -r '.verification.status // empty' "${STATE_FILE}")
  if [[ "${VERIFY_STATUS}" != "failed" ]]; then
    exit 0
  fi
  STATUS="failed"
  UNCHECKED=$(jq -r '.verification.uncheckedCount // 0' "${STATE_FILE}")
  SUMMARY="Plan ${SLUG} verification failed (${UNCHECKED} unchecked criteria)"
  ;;

revise)
  # Only write when the engine has bailed: state.json.status == "failed".
  # In normal mid-loop revise, the engine continues iterating and we stay
  # silent. The bailout case means the engine gave up after exhausting its
  # iteration budget.
  PLAN_STATUS=$(jq -r '.status // empty' "${STATE_FILE}")
  if [[ "${PLAN_STATUS}" != "failed" ]]; then
    exit 0
  fi
  STATUS="in_progress"
  SUMMARY="Plan ${SLUG} stopped after exhausting review iterations"
  if [[ -n "${FAILED}" && -n "${ITEMS}" ]]; then
    SUMMARY="${SUMMARY} (${FAILED}/${ITEMS} items still failing)"
  fi
  ;;

*)
  exit 0
  ;;
esac

if [[ -z "${STATUS}" ]]; then
  exit 0
fi

mkdir -p "${NOTIF_DIR}"

CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Build JSON. Optional fields are omitted when empty.
JQ_ARGS=(
  --arg slug "${SLUG}"
  --arg status "${STATUS}"
  --arg summary "${SUMMARY}"
  --arg createdAt "${CREATED_AT}"
)
# shellcheck disable=SC2016 # jq filter — $vars are jq refs, not shell expansion
JQ_FILTER='{slug: $slug, status: $status, summary: $summary, createdAt: $createdAt, seen: false}'

if [[ -n "${ISSUE_NUMBER}" ]]; then
  JQ_ARGS+=(--argjson issueNumber "${ISSUE_NUMBER}")
  JQ_FILTER="${JQ_FILTER} + {issueNumber: \$issueNumber}"
fi

if [[ -n "${PR_URL}" ]]; then
  JQ_ARGS+=(--arg prUrl "${PR_URL}")
  JQ_FILTER="${JQ_FILTER} + {prUrl: \$prUrl}"
fi

if [[ -n "${PR_NUMBER}" ]]; then
  JQ_ARGS+=(--argjson prNumber "${PR_NUMBER}")
  JQ_FILTER="${JQ_FILTER} + {prNumber: \$prNumber}"
fi

TMP_FILE="${NOTIF_FILE}.tmp.$$"
jq -n "${JQ_ARGS[@]}" "${JQ_FILTER}" >"${TMP_FILE}"
mv "${TMP_FILE}" "${NOTIF_FILE}"

echo "02-agent-notify: wrote ${NOTIF_FILE} (event=${EVENT} status=${STATUS})" >&2
