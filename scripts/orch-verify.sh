#!/usr/bin/env bash
# Completion criteria verifier — spawns a verifier agent to execute and
# check off unchecked completion criteria in plan.md.
#
# Called by orch-engine.sh after review returns SHIP but unchecked
# completion criteria remain. The verifier runs tests, linters, etc.
# and marks each criterion [x] if it passes.
#
# Usage: scripts/orch-verify.sh <slug>
#
# Exit codes:
#   0 — all criteria verified (PASS)
#   1 — some criteria remain unchecked (FAIL)
#
# Requires: jq, agent CLI (claude/gemini/codex), orch-state.sh,
#           agent-shim.sh, harness/dispatcher.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=agent-shim.sh
source "${SCRIPT_DIR}/agent-shim.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/harness/dispatcher.sh"

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
  echo "error: usage: orch-verify.sh <slug>" >&2
  exit 1
fi

PROMPT_TEMPLATE="${SCRIPT_DIR}/../agents/orch-verifier.md"

# GH_SYNC flag — exported by orch-run.sh when github.sync is true
GH_SYNC="${GH_SYNC:-false}"

# Per-plan paths from orch-state.sh helpers
ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
PLAN_BASE_DIR=$(orch_plan_dir "${SLUG}")
PID_DIR="${PLAN_BASE_DIR}/pids"
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

# Use worktree plan path; in GH mode resolve from .orchestrator/
if [[ "${GH_SYNC}" == true ]]; then
  PLAN_DIR="${WORKTREE_DIR}/.orchestrator/plans/${SLUG}"
elif [[ -d "${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}" ]]; then
  PLAN_DIR="${WORKTREE_DIR}/docs/exec-plans/active/${SLUG}"
else
  PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
fi

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
  echo "error: state file not found: ${ORCH_STATE_FILE}" >&2
  exit 1
fi

if [[ ! -f "${PLAN_DIR}/plan.md" ]]; then
  echo "error: plan not found: ${PLAN_DIR}/plan.md" >&2
  exit 1
fi

if [[ ! -f "${PROMPT_TEMPLATE}" ]]; then
  echo "error: verifier prompt template not found: ${PROMPT_TEMPLATE}" >&2
  exit 1
fi

# --- Extract unchecked completion criteria ---

UNCHECKED_CRITERIA=$(awk '
	/^```/ { fence = !fence; next }
	fence { next }
	/^## Completion criteria/ { capturing = 1; next }
	capturing && /^## / { capturing = 0; next }
	capturing && /^- \[ \]/ { print }
' "${PLAN_DIR}/plan.md")

if [[ -z "${UNCHECKED_CRITERIA}" ]]; then
  echo "orch-verify: all completion criteria already checked — PASS"
  exit 0
fi

UNCHECKED_COUNT=$(printf '%s\n' "${UNCHECKED_CRITERIA}" | wc -l | tr -d ' ')
echo "orch-verify: ${UNCHECKED_COUNT} unchecked completion criteria found"

# --- Update verification state ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED=$(jq \
  --arg now "${NOW}" \
  --argjson count "${UNCHECKED_COUNT}" \
  '.verification.status = "running" |
	 .verification.uncheckedCount = $count |
	 .verification.iteration = ((.verification.iteration // 0) + 1) |
	 .updatedAt = $now' "${ORCH_STATE_FILE}")
orch_write_state "${SLUG}" "${UPDATED}"

# --- Read poll interval ---

POLL_INTERVAL=$(orch_read_config "verify_poll_interval_seconds")
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# --- Harness handles ---

VERIFIER_ROLE="verifier"
VERIFIER_ID="0"
VERIFY_RESULT_FILE="${PLAN_DIR}/verify-result.txt"
VERIFIER_LOG="${LOG_DIR}/verifier.log"
VERIFIER_STARTED_AT_FILE="${PID_DIR}/${VERIFIER_ROLE}-${VERIFIER_ID}.started_at"

# Remove stale result file
rm -f "${VERIFY_RESULT_FILE}"

# Terminate any stale verifier from a previous iteration
STALE_PID_FILE="${PID_DIR}/${VERIFIER_ROLE}-${VERIFIER_ID}.pid"
if [[ -f "${STALE_PID_FILE}" ]]; then
  STALE_HANDLE=$(head -n1 "${STALE_PID_FILE}" | tr -d '[:space:]')
  if [[ -n "${STALE_HANDLE}" ]]; then
    harness::terminate handle="${STALE_HANDLE}" grace=2 >/dev/null 2>&1 || true
  fi
  rm -f "${STALE_PID_FILE}" "${VERIFIER_STARTED_AT_FILE}"
fi

mkdir -p "${PID_DIR}" "${LOG_DIR}"

# --- Build verifier prompt ---

VERIFIER_PROMPT=$(cat "${PROMPT_TEMPLATE}")
VERIFIER_PROMPT="${VERIFIER_PROMPT//\{PLAN_PATH\}/${PLAN_DIR}/plan.md}"
VERIFIER_PROMPT="${VERIFIER_PROMPT//\{RESULT_FILE\}/${VERIFY_RESULT_FILE}}"
VERIFIER_PROMPT="${VERIFIER_PROMPT//\{UNCHECKED_CRITERIA\}/${UNCHECKED_CRITERIA}}"

# Write prompt to a file so the spawned shell can cat it in
PROMPT_FILE=$(mktemp "${ORCH_STATE_DIR}/verifier-prompt-XXXXXX")
mv "${PROMPT_FILE}" "${PROMPT_FILE}.md"
PROMPT_FILE="${PROMPT_FILE}.md"
printf '%s\n' "${VERIFIER_PROMPT}" >"${PROMPT_FILE}"

# --- Determine working directory ---

VERIFY_CWD="${REPO_ROOT}"
if [[ -d "${WORKTREE_DIR}" ]]; then
  VERIFY_CWD="${WORKTREE_DIR}"
fi

# --- Spawn verifier via harness ---

# Build agent command using shim helper (handles Codex exec pattern)
CMD_TEMPLATE="$(dega_agent_build_headless_cmd "DEGA_PROMPT_MARKER")"
AGENT_CMD_STR="${CMD_TEMPLATE/DEGA_PROMPT_MARKER/\"\$(cat '${PROMPT_FILE}')\"}"

# Skip env -u when session var is empty (e.g., Codex has no session var)
SESSION_VAR="$(dega_agent_session_var)"
ENV_PREFIX=""
if [[ -n "${SESSION_VAR}" ]]; then
  ENV_PREFIX="env -u '${SESSION_VAR}'"
fi

VERIFIER_CMD="RALPH_ROLE=verifier RALPH_TASK_DIR='${PLAN_DIR}' RALPH_LOOP=1 \
${ENV_PREFIX} ${AGENT_CMD_STR} ; \
echo '--- verifier exited ---'"

VERIFIER_HANDLE=$(harness::spawn_process \
  role="${VERIFIER_ROLE}" \
  id="${VERIFIER_ID}" \
  cwd="${VERIFY_CWD}" \
  cmd="${VERIFIER_CMD}" \
  logfile="${VERIFIER_LOG}" \
  pid_dir="${PID_DIR}" \
  started_at_file="${VERIFIER_STARTED_AT_FILE}")

if [[ -z "${VERIFIER_HANDLE}" ]]; then
  echo "error: harness failed to spawn verifier" >&2
  exit 1
fi

echo "orch-verify: spawned verifier via harness (handle=${VERIFIER_HANDLE}, log=${VERIFIER_LOG})"

# --- Poll for verify-result.txt ---

MAX_POLLS=120 # 120 * 10s = 20 minutes default timeout
poll_count=0

VERIFIER_STARTED_AT=""
if [[ -f "${VERIFIER_STARTED_AT_FILE}" ]]; then
  VERIFIER_STARTED_AT=$(cat "${VERIFIER_STARTED_AT_FILE}")
fi

while true; do
  if [[ -f "${VERIFY_RESULT_FILE}" ]]; then
    RESULT=$(head -1 "${VERIFY_RESULT_FILE}" | tr -d '[:space:]')
    echo "orch-verify: verify-result.txt found — decision: ${RESULT}"
    break
  fi

  # Detect dead verifier (process gone, no result file)
  STATUS_ARGS=(handle="${VERIFIER_HANDLE}")
  if [[ -n "${VERIFIER_STARTED_AT}" ]]; then
    STATUS_ARGS+=(started_at="${VERIFIER_STARTED_AT}")
  fi
  if ! harness::query_status "${STATUS_ARGS[@]}" >/dev/null 2>&1; then
    echo "orch-verify: verifier exited without writing result — FAIL"
    RESULT="FAIL"
    break
  fi

  poll_count=$((poll_count + 1))
  if ((poll_count >= MAX_POLLS)); then
    echo "orch-verify: timeout after $((MAX_POLLS * POLL_INTERVAL))s — FAIL"
    harness::terminate handle="${VERIFIER_HANDLE}" grace=5 >/dev/null 2>&1 || true
    RESULT="FAIL"
    break
  fi

  sleep "${POLL_INTERVAL}"
done

# --- Terminate verifier process ---

harness::terminate handle="${VERIFIER_HANDLE}" grace=5 >/dev/null 2>&1 || true
rm -f "${PID_DIR}/${VERIFIER_ROLE}-${VERIFIER_ID}.pid" "${VERIFIER_STARTED_AT_FILE}"

# --- Re-count unchecked criteria after verifier ran ---

REMAINING=$(awk '
	/^```/ { fence = !fence; next }
	fence { next }
	/^## Completion criteria/ { capturing = 1; next }
	capturing && /^## / { capturing = 0; next }
	capturing && /^- \[ \]/ { count++ }
	END { print count+0 }
' "${PLAN_DIR}/plan.md")

# --- Update state and return ---

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ "${RESULT}" == "PASS" ]] && [[ "${REMAINING}" -eq 0 ]]; then
  echo "orch-verify: PASS — all completion criteria verified"
  UPDATED=$(jq \
    --arg now "${NOW}" \
    '.verification.status = "passed" |
		 .verification.uncheckedCount = 0 |
		 .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${UPDATED}"
  exit 0
else
  echo "orch-verify: FAIL — ${REMAINING} criteria remain unchecked"
  UPDATED=$(jq \
    --arg now "${NOW}" \
    --argjson remaining "${REMAINING}" \
    '.verification.status = "failed" |
		 .verification.uncheckedCount = $remaining |
		 .updatedAt = $now' "${ORCH_STATE_FILE}")
  orch_write_state "${SLUG}" "${UPDATED}"
  exit 1
fi
