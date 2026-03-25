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
# Requires: jq, claude CLI, tmux, orch-state.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh
source "${SCRIPT_DIR}/orch-state.sh"

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

POLL_INTERVAL=$(orch_read_config "poll_interval_seconds")
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# --- Tmux session ---

TMUX_SESSION="orch-${SLUG}"
WINDOW_NAME="verifier"
VERIFY_RESULT_FILE="${PLAN_DIR}/verify-result.txt"

# Remove stale result file
rm -f "${VERIFY_RESULT_FILE}"

# --- Build verifier prompt ---

VERIFIER_PROMPT=$(cat "${PROMPT_TEMPLATE}")
VERIFIER_PROMPT="${VERIFIER_PROMPT//\{PLAN_PATH\}/${PLAN_DIR}/plan.md}"
VERIFIER_PROMPT="${VERIFIER_PROMPT//\{RESULT_FILE\}/${VERIFY_RESULT_FILE}}"
VERIFIER_PROMPT="${VERIFIER_PROMPT//\{UNCHECKED_CRITERIA\}/${UNCHECKED_CRITERIA}}"

# Write prompt to temp file (tmux send-keys has length limits)
PROMPT_FILE=$(mktemp "${ORCH_STATE_DIR}/verifier-prompt-XXXXXX")
mv "${PROMPT_FILE}" "${PROMPT_FILE}.md"
PROMPT_FILE="${PROMPT_FILE}.md"
printf '%s\n' "${VERIFIER_PROMPT}" >"${PROMPT_FILE}"

# --- Determine working directory ---

VERIFY_CWD="${REPO_ROOT}"
if [[ -d "${WORKTREE_DIR}" ]]; then
	VERIFY_CWD="${WORKTREE_DIR}"
fi

# --- Spawn verifier in tmux window ---

# Kill stale verifier window from previous iteration
tmux kill-window -t "${TMUX_SESSION}:${WINDOW_NAME}" 2>/dev/null || true

tmux new-window -d -t "${TMUX_SESSION}" -n "${WINDOW_NAME}" \
	"cd '${VERIFY_CWD}' && \
	 RALPH_ROLE=verifier RALPH_TASK_DIR='${PLAN_DIR}' RALPH_LOOP=1 \
	 env -u CLAUDECODE claude -p --dangerously-skip-permissions \
	 \"\$(cat '${PROMPT_FILE}')\" ; \
	 echo '--- verifier exited ---'; \
	 sleep 5"

# Stream verifier output to log file
tmux pipe-pane -t "${TMUX_SESSION}:${WINDOW_NAME}" \
	-o "cat >> '${LOG_DIR}/verifier.log'"

echo "orch-verify: spawned verifier in tmux window '${WINDOW_NAME}'"

# --- Poll for verify-result.txt ---

MAX_POLLS=120 # 120 * 10s = 20 minutes default timeout
poll_count=0

while true; do
	if [[ -f "${VERIFY_RESULT_FILE}" ]]; then
		RESULT=$(head -1 "${VERIFY_RESULT_FILE}" | tr -d '[:space:]')
		echo "orch-verify: verify-result.txt found — decision: ${RESULT}"
		break
	fi

	# Detect dead verifier (window gone, no result file)
	if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
		LIVE_WINDOWS=$(tmux list-windows -t "${TMUX_SESSION}" \
			-F '#{window_name} #{pane_dead}' 2>/dev/null || true)
		IS_ALIVE=false
		if printf '%s\n' "${LIVE_WINDOWS}" | grep -q "^${WINDOW_NAME} 0$"; then
			IS_ALIVE=true
		fi
		if [[ "${IS_ALIVE}" == false ]]; then
			echo "orch-verify: verifier exited without writing result — FAIL"
			RESULT="FAIL"
			break
		fi
	fi

	poll_count=$((poll_count + 1))
	if ((poll_count >= MAX_POLLS)); then
		echo "orch-verify: timeout after $((MAX_POLLS * POLL_INTERVAL))s — FAIL"
		tmux kill-window -t "${TMUX_SESSION}:${WINDOW_NAME}" 2>/dev/null || true
		RESULT="FAIL"
		break
	fi

	sleep "${POLL_INTERVAL}"
done

# --- Kill verifier window ---

tmux kill-window -t "${TMUX_SESSION}:${WINDOW_NAME}" 2>/dev/null || true

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
