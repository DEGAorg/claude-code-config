#!/usr/bin/env bash
# Per-plan FORMATTING phase — runs after DOCUMENTING all-PASS (or after
# REVIEW all-PASS when DOCUMENTING is absent) and before SHIP. Spawns a
# single lint-fixer agent in the plan worktree to auto-fix shfmt and
# shell-lint issues across every `.sh` file the orch branch changed vs
# its base.
#
# Single agent, single PASS/FAIL result.
#   PASS  → if the agent staged any files, the runner makes one
#           `chore: shfmt + shellcheck pass` commit, then exit 0.
#   FAIL  → exit non-zero so the engine routes the highest-numbered
#           reviewed item back to REVISE for another worker pass.
#
# Usage: scripts/orch-format.sh <slug>
#
# Library mode: tests source this file (BASH_SOURCE != $0). Helper
# functions are defined eagerly; the spawn loop only runs when invoked
# directly.
#
# Env overrides (mostly for tests):
#   ORCH_REPO_ROOT             — alt repo root
#   ORCH_STATE_DIR             — alt state dir
#   ORCH_BASE                  — base branch to diff (default: read
#                                .base from state.json, fallback develop)
#   ORCH_FORMAT_AGENT_TIMEOUT  — seconds to wait for the agent
#                                (default 600)
#   ORCH_FORMAT_POLL_INTERVAL  — poll interval (default 10)
#
# Requires: jq, tmux, agent CLI (claude/gemini/codex), orch-state.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=orch-state.sh disable=SC1091
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=agent-shim.sh disable=SC1091
source "${SCRIPT_DIR}/agent-shim.sh"

FORMAT_AGENT_PROMPT_FILE="${SCRIPT_DIR}/../agents/lint-fixer.md"

# --- Helpers (callable from tests when this file is sourced) ---

# Compute the list of .sh files changed on the orch branch vs base.
# Echoes one path per line; empty stdout means nothing to format.
orch_format_changed_sh() {
  local worktree_dir="$1"
  local base="$2"
  git -C "${worktree_dir}" diff --name-only "${base}..HEAD" -- '*.sh' \
    2>/dev/null || true
}

# Write the inputs file the lint-fixer agent reads (cwd-relative). Also
# writes a unified diff so the agent can read it without invoking git.
orch_format_stage_inputs() {
  local worktree_dir="$1"
  local base="$2"
  local inputs_dir="${worktree_dir}/inputs"
  mkdir -p "${inputs_dir}"
  orch_format_changed_sh "${worktree_dir}" "${base}" \
    >"${inputs_dir}/changed-files.txt"
  git -C "${worktree_dir}" diff "${base}..HEAD" -- '*.sh' \
    >"${inputs_dir}/diff.patch" 2>/dev/null || :
}

# Read the verdict token from formatting/result.txt (first whitespace
# token of the first line). Echoes "PASS" or "FAIL".
orch_format_read_verdict() {
  local result_file="$1"
  if [[ ! -f "${result_file}" ]]; then
    printf 'FAIL'
    return 0
  fi
  local token
  token=$(head -1 "${result_file}" | awk '{print $1}' | tr -d '[:space:]')
  case "${token}" in
  PASS) printf 'PASS' ;;
  *) printf 'FAIL' ;;
  esac
}

# Library mode: when sourced, do not run main loop.
if [[ "${BASH_SOURCE[0]:-}" != "${0}" ]]; then
  return 0
fi

# --- Main entry point (only runs when invoked directly) ---

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
  echo "error: usage: orch-format.sh <slug>" >&2
  exit 1
fi

ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
FORMAT_DIR=$(orch_plan_formatting_dir "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

if [[ ! -f "${ORCH_STATE_FILE}" ]]; then
  echo "error: state file not found: ${ORCH_STATE_FILE}" >&2
  exit 1
fi

if [[ ! -d "${WORKTREE_DIR}" ]]; then
  echo "error: worktree not found: ${WORKTREE_DIR}" >&2
  exit 1
fi

if [[ ! -f "${FORMAT_AGENT_PROMPT_FILE}" ]]; then
  echo "error: lint-fixer prompt not found: ${FORMAT_AGENT_PROMPT_FILE}" >&2
  exit 1
fi

# Resolve base branch: env override → state.base → develop.
ORCH_BASE_BRANCH="${ORCH_BASE:-}"
if [[ -z "${ORCH_BASE_BRANCH}" ]]; then
  ORCH_BASE_BRANCH=$(jq -r '.base // empty' "${ORCH_STATE_FILE}" 2>/dev/null || true)
fi
ORCH_BASE_BRANCH="${ORCH_BASE_BRANCH:-develop}"

POLL_INTERVAL="${ORCH_FORMAT_POLL_INTERVAL:-}"
if [[ -z "${POLL_INTERVAL}" ]]; then
  POLL_INTERVAL=$(orch_read_config "format_poll_interval_seconds" 2>/dev/null || true)
fi
POLL_INTERVAL="${POLL_INTERVAL:-10}"
AGENT_TIMEOUT="${ORCH_FORMAT_AGENT_TIMEOUT:-600}"

mkdir -p "${FORMAT_DIR}" "${LOG_DIR}"
mkdir -p "${WORKTREE_DIR}/inputs" "${WORKTREE_DIR}/formatting"

orch_init_formatting_state "${SLUG}"

# --- Compute changed .sh and short-circuit on empty ---

orch_format_stage_inputs "${WORKTREE_DIR}" "${ORCH_BASE_BRANCH}"
INPUTS_FILE="${WORKTREE_DIR}/inputs/changed-files.txt"
RESULT_FILE="${WORKTREE_DIR}/formatting/result.txt"
rm -f "${RESULT_FILE}"

if [[ ! -s "${INPUTS_FILE}" ]]; then
  echo "orch-format: no changed .sh files vs ${ORCH_BASE_BRANCH} — PASS"
  printf 'PASS\nno changed .sh files\n' >"${RESULT_FILE}"
  cp "${RESULT_FILE}" "${FORMAT_DIR}/result.txt"
  result=$(orch_format_aggregate "${SLUG}" PASS)
  echo "orch-format: ${result}"
  exit 0
fi

CHANGED_COUNT=$(wc -l <"${INPUTS_FILE}" | tr -d '[:space:]')
echo "orch-format: ${CHANGED_COUNT} changed .sh file(s) vs ${ORCH_BASE_BRANCH}"

# --- Spawn lint-fixer agent ---

TMUX_SESSION="orch-${SLUG}"

if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  echo "error: tmux session ${TMUX_SESSION} not running" >&2
  exit 1
fi

PROMPT_FILE=$(mktemp "${ORCH_STATE_DIR}/lint-fixer-prompt-XXXXXX")
mv "${PROMPT_FILE}" "${PROMPT_FILE}.md"
PROMPT_FILE="${PROMPT_FILE}.md"
{
  cat "${FORMAT_AGENT_PROMPT_FILE}"
  printf '\n---\n\n'
  printf '## Your Assignment\n\n'
  printf -- '- **Working directory**: %s\n' "${WORKTREE_DIR}"
  printf -- '- **Inputs**: inputs/changed-files.txt (cwd-relative; one path per line)\n'
  printf -- '- **Diff**: inputs/diff.patch (cwd-relative)\n'
  printf -- '- **Output**: formatting/result.txt (cwd-relative; first line PASS or FAIL <reason>)\n'
} >"${PROMPT_FILE}"

PROVIDER="$(dega_agent_type)"
RAW_LOG="${LOG_DIR}/lint-fixer.log"
: >"${RAW_LOG}"

if [[ "${PROVIDER}" == "claude" ]]; then
  # shellcheck disable=SC2016  # literal $(cat '...') is intended for tmux shell
  AGENT_CMD="claude --verbose --output-format stream-json --permission-mode acceptEdits --allowed-tools 'Read' 'Edit(*.sh)' 'Glob' 'Grep' 'Bash' --disallowed-tools 'Write' -p \"\$(cat '${PROMPT_FILE}')\""
else
  echo "orch-format: WARN — provider ${PROVIDER} does not support tool-scope flags; using prompt-only enforcement" >&2
  CMD_TEMPLATE="$(dega_agent_build_headless_cmd "DEGA_PROMPT_MARKER")"
  # shellcheck disable=SC2016  # literal $(cat '...') is intended for tmux shell
  PROMPT_REPLACEMENT="\"\$(cat '${PROMPT_FILE}')\""
  AGENT_CMD="${CMD_TEMPLATE/DEGA_PROMPT_MARKER/${PROMPT_REPLACEMENT}}"
fi

SESSION_VAR="$(dega_agent_session_var)"
ENV_PREFIX=""
if [[ -n "${SESSION_VAR}" ]]; then
  ENV_PREFIX="env -u '${SESSION_VAR}'"
fi

WINDOW="lint-fixer"
tmux kill-window -t "${TMUX_SESSION}:${WINDOW}" 2>/dev/null || true

tmux new-window -d -t "${TMUX_SESSION}" -n "${WINDOW}" \
  "cd '${WORKTREE_DIR}' && ${ENV_PREFIX} timeout ${AGENT_TIMEOUT} ${AGENT_CMD} ; \
   echo '--- lint-fixer exited ---'; sleep 2"

tmux pipe-pane -t "${TMUX_SESSION}:${WINDOW}" -o "cat >> '${RAW_LOG}'"

echo "orch-format: spawned lint-fixer agent (timeout ${AGENT_TIMEOUT}s)"

# --- Poll for result ---

DEADLINE=$(($(date +%s) + AGENT_TIMEOUT + 30))
while true; do
  if [[ -f "${RESULT_FILE}" ]]; then
    break
  fi
  if (($(date +%s) >= DEADLINE)); then
    echo "orch-format: timeout waiting for ${RESULT_FILE}" >&2
    printf 'FAIL\nagent timeout after %ds\n' "${AGENT_TIMEOUT}" >"${RESULT_FILE}"
    break
  fi
  # Window died with no result file?
  if ! tmux list-windows -t "${TMUX_SESSION}" -F '#{window_name}' 2>/dev/null |
    grep -qx "${WINDOW}"; then
    if [[ ! -f "${RESULT_FILE}" ]]; then
      echo "orch-format: lint-fixer window exited without writing result" >&2
      printf 'FAIL\nagent window died before writing result\n' >"${RESULT_FILE}"
      break
    fi
  fi
  sleep "${POLL_INTERVAL}"
done

tmux kill-window -t "${TMUX_SESSION}:${WINDOW}" 2>/dev/null || true

# Mirror the result file into the plan dir for engine observability.
cp "${RESULT_FILE}" "${FORMAT_DIR}/result.txt"

VERDICT=$(orch_format_read_verdict "${RESULT_FILE}")

# --- Commit on PASS if the agent staged anything ---

COMMIT_FAILED=0
if [[ "${VERDICT}" == "PASS" ]]; then
  if ! git -C "${WORKTREE_DIR}" diff --cached --quiet 2>/dev/null; then
    if git -C "${WORKTREE_DIR}" commit --no-verify \
      -m "chore: shfmt + shellcheck pass"; then
      echo "orch-format: committed chore: shfmt + shellcheck pass"
    else
      COMMIT_FAILED=1
      echo "orch-format: WARN — commit failed" >&2
    fi
  fi
fi

result=$(orch_format_aggregate "${SLUG}" "${VERDICT}")
echo "orch-format: ${result}"

if [[ "${VERDICT}" == "PASS" && "${COMMIT_FAILED}" -eq 0 ]]; then
  exit 0
fi
exit 1
