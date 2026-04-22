#!/usr/bin/env bash
# skills/orch-invoke/launch.sh — validate a resolved plan (issue + slug)
# and launch it via `scripts/orch-run.sh --background`. Emits the
# structured JSON contract documented in skills/orch-invoke/SKILL.md.
#
# Usage:
#   skills/orch-invoke/launch.sh --issue <N> [--slug <slug>] [--timeout <sec>]
#   skills/orch-invoke/launch.sh <N>
#
# Success output (stdout, single-line JSON):
#   {"ok":true,"slug":"...","issue":N,"pid":P,"events_path":"...","state_path":"..."}
#
# Failure output (stdout, single-line JSON):
#   {"ok":false,"error":"<code>","detail":"...", ...}
# where <code> is one of: plan_not_found, missing_deps, already_running,
# already_completed, launch_timeout, unknown.
#
# Environment overrides (test hooks):
#   ORCH_ROOT            Repo root (default: git toplevel of this script)
#   ORCH_RUN_CMD         Executable used in place of `scripts/orch-run.sh`
#   ORCH_INVOKE_SKIP_GH  Non-empty → skip the `gh` plan:completed label check
#   ORCH_INVOKE_TIMEOUT  plan_start wait, seconds (default: 30)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="${ORCH_ROOT:-$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || pwd)}"
TIMEOUT="${ORCH_INVOKE_TIMEOUT:-30}"

ISSUE=""
SLUG=""

emit_fail() {
  # emit_fail <code> <detail>
  jq -cn --arg e "$1" --arg d "$2" '{ok: false, error: $e, detail: $d}'
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  echo "launch.sh: jq is required" >&2
  exit 2
fi

while (($# > 0)); do
  case "$1" in
  --issue)
    ISSUE="${2:-}"
    shift 2
    ;;
  --slug)
    SLUG="${2:-}"
    shift 2
    ;;
  --timeout)
    TIMEOUT="${2:-}"
    shift 2
    ;;
  -h | --help)
    sed -n '2,22p' "$0" >&2
    exit 2
    ;;
  --)
    shift
    break
    ;;
  -*)
    echo "launch.sh: unknown flag: $1" >&2
    exit 2
    ;;
  *)
    if [[ -z "${ISSUE}" ]]; then
      ISSUE="$1"
      shift
    else
      echo "launch.sh: unexpected positional argument: $1" >&2
      exit 2
    fi
    ;;
  esac
done

if [[ -z "${ISSUE}" ]]; then
  emit_fail "unknown" "no issue provided; pass --issue N or a positional issue number"
fi

if ! [[ "${ISSUE}" =~ ^[0-9]+$ ]]; then
  emit_fail "unknown" "issue must be a positive integer (got: ${ISSUE})"
fi

# --- Resolve slug if not explicitly supplied ----------------------------

find_slug_for_issue() {
  local issue="$1" candidate state num plan
  if [[ -d "${ROOT}/.orchestrator/plans" ]]; then
    while IFS= read -r candidate; do
      state="${candidate}/state.json"
      if [[ -f "${state}" ]]; then
        num="$(jq -r '.issueNumber // empty' <"${state}" 2>/dev/null || true)"
        if [[ "${num}" == "${issue}" ]]; then
          basename "${candidate}"
          return 0
        fi
      fi
    done < <(find "${ROOT}/.orchestrator/plans" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  fi
  if [[ -d "${ROOT}/docs/exec-plans/active" ]]; then
    while IFS= read -r candidate; do
      plan="${candidate}/plan.md"
      if [[ -f "${plan}" ]] && grep -Eq "#${issue}([^0-9]|\$)" "${plan}"; then
        basename "${candidate}"
        return 0
      fi
    done < <(find "${ROOT}/docs/exec-plans/active" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  fi
  return 1
}

if [[ -z "${SLUG}" ]]; then
  if ! SLUG="$(find_slug_for_issue "${ISSUE}")"; then
    emit_fail "plan_not_found" "no plan directory matching issue #${ISSUE} under .orchestrator/plans or docs/exec-plans/active"
  fi
fi

# --- Locate plan.md -----------------------------------------------------

PLAN_MD=""
for candidate in \
  "${ROOT}/docs/exec-plans/active/${SLUG}/plan.md" \
  "${ROOT}/.orchestrator/plans/${SLUG}/plan.md"; do
  if [[ -f "${candidate}" ]]; then
    PLAN_MD="${candidate}"
    break
  fi
done

if [[ -z "${PLAN_MD}" ]]; then
  emit_fail "plan_not_found" "plan.md not found for slug ${SLUG}"
fi

# --- Validate deps annotations -----------------------------------------

progress_items() {
  awk '
    /^## Progress log/ { in_log = 1; next }
    in_log && /^## / { in_log = 0 }
    in_log && /^- \[[ xX]\]/ { print }
  ' "$1"
}

ITEM_INDEX=0
while IFS= read -r line; do
  if ((ITEM_INDEX > 0)) && [[ "${line}" != *"(deps:"* ]]; then
    emit_fail "missing_deps" "Progress log item $((ITEM_INDEX + 1)) has no (deps: N) annotation in ${PLAN_MD}"
  fi
  ITEM_INDEX=$((ITEM_INDEX + 1))
done < <(progress_items "${PLAN_MD}")

if ((ITEM_INDEX == 0)); then
  emit_fail "missing_deps" "no Progress log items found in ${PLAN_MD}"
fi

# --- Paths reported back to the caller ---------------------------------

EVENTS_REL=".orchestrator/plans/${SLUG}/events.jsonl"
STATE_REL=".orchestrator/plans/${SLUG}/state.json"
EVENTS_PATH="${ROOT}/${EVENTS_REL}"
PID_FILE="${ROOT}/.orchestrator/plans/${SLUG}/pids/engine-${SLUG}.pid"

# --- Detect already-running via master.json ----------------------------

MASTER="${ROOT}/.orchestrator/master.json"
if [[ -f "${MASTER}" ]]; then
  RUNNING_JSON="$(jq -c --arg slug "${SLUG}" '
    .plans[]?
    | select(.slug == $slug
             and ((.status // "") | IN("completed","failed","cancelled") | not))
  ' "${MASTER}" 2>/dev/null || true)"
  if [[ -n "${RUNNING_JSON}" ]]; then
    EXISTING_PID="$(jq -r '.pid // empty' <<<"${RUNNING_JSON}" 2>/dev/null || true)"
    EXISTING_EVENTS="$(jq -r '.eventsPath // empty' <<<"${RUNNING_JSON}" 2>/dev/null || true)"
    EXISTING_STATE="$(jq -r '.statePath // empty' <<<"${RUNNING_JSON}" 2>/dev/null || true)"
    jq -cn \
      --arg code "already_running" \
      --arg detail "plan ${SLUG} is already running" \
      --arg pid "${EXISTING_PID}" \
      --arg events "${EXISTING_EVENTS:-${EVENTS_REL}}" \
      --arg state "${EXISTING_STATE:-${STATE_REL}}" \
      '{
         ok: false,
         error: $code,
         detail: $detail,
         pid: (if $pid == "" then null else ($pid | tonumber? // null) end),
         events_path: $events,
         state_path: $state
       }'
    exit 1
  fi
fi

# --- Optional: plan:completed label check ------------------------------

if [[ -z "${ORCH_INVOKE_SKIP_GH:-}" ]] && command -v gh >/dev/null 2>&1; then
  LABELS_JSON="$(gh issue view "${ISSUE}" --json labels 2>/dev/null || true)"
  if [[ -n "${LABELS_JSON}" ]]; then
    if jq -e '.labels[]? | select(.name == "plan:completed")' <<<"${LABELS_JSON}" >/dev/null 2>&1; then
      emit_fail "already_completed" "issue #${ISSUE} is labelled plan:completed"
    fi
  fi
fi

# --- Launch ------------------------------------------------------------

mkdir -p "$(dirname "${EVENTS_PATH}")"

if [[ -f "${EVENTS_PATH}" ]]; then
  BASELINE_LINES="$(wc -l <"${EVENTS_PATH}" | tr -d '[:space:]')"
else
  BASELINE_LINES=0
fi

if [[ -n "${ORCH_RUN_CMD:-}" ]]; then
  ORCH_RUN=("${ORCH_RUN_CMD}")
else
  ORCH_RUN=(bash "${ROOT}/scripts/orch-run.sh")
fi

if ! "${ORCH_RUN[@]}" "${SLUG}" --issue "${ISSUE}" --background >&2; then
  emit_fail "unknown" "scripts/orch-run.sh exited non-zero for ${SLUG}"
fi

# --- Wait for plan_start event ----------------------------------------

plan_start_seen() {
  [[ -f "${EVENTS_PATH}" ]] || return 1
  local cur
  cur="$(wc -l <"${EVENTS_PATH}" | tr -d '[:space:]')"
  ((cur > BASELINE_LINES)) || return 1
  tail -n +$((BASELINE_LINES + 1)) "${EVENTS_PATH}" |
    grep -q '"evt":"plan_start"'
}

DEADLINE=$((SECONDS + TIMEOUT))
while ((SECONDS < DEADLINE)); do
  if plan_start_seen; then
    break
  fi
  sleep 1
done

PID=""
if [[ -f "${PID_FILE}" ]]; then
  PID="$(tr -d '[:space:]' <"${PID_FILE}")"
fi

if ! plan_start_seen; then
  jq -cn \
    --arg code "launch_timeout" \
    --arg detail "plan_start event did not appear within ${TIMEOUT}s" \
    --arg pid "${PID}" \
    --arg events "${EVENTS_REL}" \
    --arg state "${STATE_REL}" \
    '{
       ok: false,
       error: $code,
       detail: $detail,
       pid: (if $pid == "" then null else ($pid | tonumber? // null) end),
       events_path: $events,
       state_path: $state
     }'
  exit 1
fi

jq -cn \
  --arg slug "${SLUG}" \
  --argjson issue "${ISSUE}" \
  --arg pid "${PID}" \
  --arg events "${EVENTS_REL}" \
  --arg state "${STATE_REL}" \
  '{
     ok: true,
     slug: $slug,
     issue: $issue,
     pid: (if $pid == "" then null else ($pid | tonumber? // null) end),
     events_path: $events,
     state_path: $state
   }'
