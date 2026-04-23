#!/usr/bin/env bash
# Completion criteria verifier — runs each unchecked criterion directly in
# shell and marks [x] in plan.md on pass.
#
# Called by orch-engine.sh after review returns SHIP but unchecked
# completion criteria remain. Each criterion must contain a backtick-quoted
# shell command (per rules/exec-plans.md); bullets without a command are
# logged as "manual — cannot auto-verify" and left unchecked.
#
# Usage: scripts/orch-verify.sh <slug>
#
# Environment:
#   ORCH_VERIFY_CRITERION_TIMEOUT  per-criterion timeout in seconds (default 60)
#
# Exit codes:
#   0 — all criteria verified (PASS)
#   1 — some criteria remain unchecked or failed (FAIL)
#
# Requires: jq, timeout, orch-state.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh disable=SC1091
source "${SCRIPT_DIR}/orch-state.sh"

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
  echo "error: usage: orch-verify.sh <slug>" >&2
  exit 1
fi

# GH_SYNC flag — exported by orch-run.sh when github.sync is true
GH_SYNC="${GH_SYNC:-false}"

# Per-criterion timeout (default 60s)
CRITERION_TIMEOUT="${ORCH_VERIFY_CRITERION_TIMEOUT:-60}"

# Per-plan paths from orch-state.sh helpers
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

# Use worktree plan path; in GH mode resolve from .orchestrator/
if [[ "${GH_SYNC}" == true ]]; then
  PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"
elif [[ -d "${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}" ]]; then
  PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"
else
  PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
fi

PLAN_FILE="${PLAN_DIR}/plan.md"
VERIFY_LOG="${LOG_DIR}/verify.log"

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
  echo "error: state file not found: ${ORCH_STATE_FILE}" >&2
  exit 1
fi

if [[ ! -f "${PLAN_FILE}" ]]; then
  echo "error: plan not found: ${PLAN_FILE}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

# Working directory for criterion execution — prefer worktree
VERIFY_CWD="${REPO_ROOT}"
if [[ -d "${WORKTREE_DIR}" ]]; then
  VERIFY_CWD="${WORKTREE_DIR}"
fi

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '[%s] %s\n' "${ts}" "$*" | tee -a "${VERIFY_LOG}"
}

# --- Extract unchecked completion criteria ---
# awk tracks fenced code blocks (skipped) and the ## Completion criteria
# section, emitting only unchecked bullets within that section.

extract_unchecked() {
  awk '
    /^```/ { fence = !fence; next }
    fence { next }
    /^## Completion criteria/ { capturing = 1; next }
    capturing && /^## / { capturing = 0; next }
    capturing && /^- \[ \]/ { print }
  ' "${PLAN_FILE}"
}

mapfile -t UNCHECKED_LINES < <(extract_unchecked)

if [[ ${#UNCHECKED_LINES[@]} -eq 0 ]]; then
  log "orch-verify: all completion criteria already checked — PASS"
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  UPDATED=$(jq \
    --arg now "${NOW}" \
    '.verification.status = "passed" |
     .verification.uncheckedCount = 0 |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${UPDATED}"
  exit 0
fi

UNCHECKED_COUNT=${#UNCHECKED_LINES[@]}
log "orch-verify: ${UNCHECKED_COUNT} unchecked completion criteria found"

# --- Update verification state → running ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq \
  --arg now "${NOW}" \
  --argjson count "${UNCHECKED_COUNT}" \
  '.verification.status = "running" |
   .verification.uncheckedCount = $count |
   .verification.iteration = ((.verification.iteration // 0) + 1) |
   .updatedAt = $now' "${ORCH_STATE_FILE}")
orch_write_state "${SLUG}" "${UPDATED}"

# --- Extract first backtick-quoted command from a bullet line ---
# Returns empty string if no backticked segment found.

extract_command() {
  local line="$1"
  # Extract first backtick-quoted segment. Uses awk for portability
  # across bash versions (macOS ships bash 3.2).
  printf '%s' "${line}" | awk '
    match($0, /`[^`]+`/) {
      s = substr($0, RSTART + 1, RLENGTH - 2)
      print s
      exit
    }
  '
}

# --- Mutate plan.md: rewrite a specific `- [ ]` line to `- [x]` ---
# Uses exact literal match on the full line to avoid mis-replacing
# similar bullets elsewhere.

mark_checked() {
  local line="$1"
  local checked="${line/- \[ \]/- [x]}"
  local tmp
  tmp=$(mktemp)
  # awk exact-line match: replace first occurrence only
  awk -v find="${line}" -v repl="${checked}" '
    !done && $0 == find { print repl; done = 1; next }
    { print }
  ' "${PLAN_FILE}" >"${tmp}"
  mv "${tmp}" "${PLAN_FILE}"
}

# --- Execute each criterion ---

passed=0
failed=0
manual=0

for line in "${UNCHECKED_LINES[@]}"; do
  cmd=$(extract_command "${line}")

  if [[ -z "${cmd}" ]]; then
    log "MANUAL: no backticked command — ${line}"
    manual=$((manual + 1))
    continue
  fi

  log "RUN: ${cmd}"

  set +e
  output=$(cd "${VERIFY_CWD}" && timeout "${CRITERION_TIMEOUT}" bash -c "${cmd}" 2>&1)
  rc=$?
  set -e

  # Trim to last 20 lines for log brevity
  tail_output=$(printf '%s\n' "${output}" | tail -n 20)

  if [[ ${rc} -eq 0 ]]; then
    log "PASS (rc=0): ${cmd}"
    mark_checked "${line}"
    passed=$((passed + 1))
  elif [[ ${rc} -eq 124 ]]; then
    log "FAIL (timeout after ${CRITERION_TIMEOUT}s): ${cmd}"
    printf '%s\n' "${tail_output}" >>"${VERIFY_LOG}"
    failed=$((failed + 1))
  else
    log "FAIL (rc=${rc}): ${cmd}"
    printf '%s\n' "${tail_output}" >>"${VERIFY_LOG}"
    failed=$((failed + 1))
  fi
done

# --- Re-count remaining unchecked after mutations ---

REMAINING=$(extract_unchecked | wc -l | tr -d ' ')

log "orch-verify: summary — passed=${passed} failed=${failed} manual=${manual} remaining=${REMAINING}"

# --- Update state and return ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ ${REMAINING} -eq 0 ]]; then
  log "orch-verify: PASS — all completion criteria verified"
  UPDATED=$(jq \
    --arg now "${NOW}" \
    '.verification.status = "passed" |
     .verification.uncheckedCount = 0 |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${UPDATED}"
  exit 0
else
  log "orch-verify: FAIL — ${REMAINING} criteria remain unchecked"
  UPDATED=$(jq \
    --arg now "${NOW}" \
    --argjson remaining "${REMAINING}" \
    '.verification.status = "failed" |
     .verification.uncheckedCount = $remaining |
     .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${UPDATED}"
  exit 1
fi
