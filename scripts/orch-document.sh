#!/usr/bin/env bash
# Per-item DOCUMENTING phase — runs after the per-item REVIEW returns SHIP
# and before SHIP. Spawns one doc-writer agent per item in parallel via
# tmux windows, polls for documenting/item-N.txt files, and rolls up
# pass/fail to state.documentation.result.
#
# A doc-writer FAIL/BLOCKED flips state.documentation.result = "REVISE"
# the same way a failed final review does — affected items reset to
# status="ready" with iteration++, reviewStatus="pending", and
# docStatus="pending" so the engine re-runs the wave.
#
# Usage: scripts/orch-document.sh <slug>
#
# Library mode: tests source this file (BASH_SOURCE != $0). Helper
# functions are defined eagerly; the spawn loop only runs when invoked
# directly.
#
# Requires: jq, agent CLI (claude/gemini/codex), tmux, orch-state.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=orch-state.sh disable=SC1091
source "${SCRIPT_DIR}/orch-state.sh"
# shellcheck source=agent-shim.sh disable=SC1091
source "${SCRIPT_DIR}/agent-shim.sh"

DOC_AGENT_PROMPT_FILE="${SCRIPT_DIR}/../agents/doc-writer.md"

# --- Helpers (callable from tests when this file is sourced) ---

# Initialize per-item docStatus before the spawn loop runs.
#
# Transitions:
#   reviewStatus == "passed" && docStatus already "passed" → keep "passed"
#   reviewStatus == "passed"                               → docStatus = "pending"
#   reviewStatus == "failed" || "skipped"                  → docStatus = "skipped"
#   otherwise                                              → docStatus = "pending"
#
# Also flips .documentation.status to "running". Idempotent: re-entering
# the phase after a REVISE preserves already-passed items so only failed
# items get re-spawned.
orch_document_prepare_item_states() {
  local slug="$1"
  local state_file
  state_file=$(orch_plan_state_file "${slug}")
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local updated
  updated=$(jq --arg now "${now}" '
    .items |= map(
      if (.reviewStatus // "") == "passed" then
        if (.docStatus // "") == "passed" then .
        else .docStatus = "pending"
        end
      elif (.reviewStatus // "") == "failed" or (.reviewStatus // "") == "skipped" then
        .docStatus = "skipped"
      else
        .docStatus = "pending"
      end
    )
    | .documentation.status = "running"
    | .updatedAt = $now
  ' "${state_file}")
  orch_write_state "${slug}" "${updated}"
}

# Mark a single item's docStatus = "documenting" before the agent spawn.
orch_document_mark_documenting() {
  local slug="$1" item_id="$2"
  local state_file
  state_file=$(orch_plan_state_file "${slug}")
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local updated
  updated=$(jq \
    --argjson id "${item_id}" \
    --arg now "${now}" \
    '(.items[] | select(.id == $id)).docStatus = "documenting"
     | .updatedAt = $now' "${state_file}")
  orch_write_state "${slug}" "${updated}"
}

# Roll up per-item docStatus into state.documentation.{status,result,reworkItems}.
# Echoes "SHIP" or "REVISE" so the caller can branch.
#
# REVISE rollup resets each failed item:
#   status        = "ready"
#   iteration     = iteration + 1
#   reviewStatus  = "pending"
#   docStatus     = "pending"
orch_document_aggregate() {
  local slug="$1"
  local state_file
  state_file=$(orch_plan_state_file "${slug}")
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local failed_ids
  failed_ids=$(jq -r '.items[] | select(.docStatus == "failed") | .id' \
    "${state_file}")

  if [[ -z "${failed_ids}" ]]; then
    local updated
    updated=$(jq --arg now "${now}" '
      .documentation.status = "done"
      | .documentation.result = "SHIP"
      | .documentation.reworkItems = []
      | .updatedAt = $now
    ' "${state_file}")
    orch_write_state "${slug}" "${updated}"
    printf 'SHIP'
    return 0
  fi

  local rework_json
  rework_json=$(printf '%s\n' "${failed_ids}" | jq -R 'tonumber' | jq -s '.')

  local updated
  updated=$(jq --arg now "${now}" --argjson rework "${rework_json}" '
    .documentation.status = "done"
    | .documentation.result = "REVISE"
    | .documentation.reworkItems = $rework
    | .updatedAt = $now
    | reduce ($rework[] | tostring | tonumber) as $id (.;
        (.items[] | select(.id == $id)) |= (
          .status = "ready"
          | .iteration = ((.iteration // 0) + 1)
          | .reviewStatus = "pending"
          | .docStatus = "pending"
        )
      )
  ' "${state_file}")
  orch_write_state "${slug}" "${updated}"
  printf 'REVISE'
}

# Stage the doc-writer agent's input files inside the worktree.
# Inputs are written to <worktree>/inputs/ so the agent can Read them
# without running shell commands (Bash is denied in its tool scope).
orch_document_stage_inputs() {
  local worktree_dir="$1"
  local plan_dir="$2"
  local done_dir="$3"
  local item_id="$4"
  local item_desc="$5"

  local inputs_dir="${worktree_dir}/inputs"
  mkdir -p "${inputs_dir}"

  printf '%s\n' "${item_desc}" >"${inputs_dir}/item-description.txt"
  printf '%s\n' "${item_id}" >"${inputs_dir}/item-id.txt"

  local commit=""
  if [[ -d "${worktree_dir}/.git" || -f "${worktree_dir}/.git" ]]; then
    commit=$(git -C "${worktree_dir}" log --format='%H %s' 2>/dev/null |
      grep -m1 -E "^[a-f0-9]+ orch: item ${item_id} —" |
      awk '{print $1}' || true)
  fi

  if [[ -n "${commit}" ]]; then
    git -C "${worktree_dir}" show --no-color "${commit}" \
      >"${inputs_dir}/diff.patch" 2>/dev/null || :
    git -C "${worktree_dir}" show --name-only --format='' "${commit}" 2>/dev/null |
      grep -v '^$' >"${inputs_dir}/changed-files.txt" || :
  else
    : >"${inputs_dir}/diff.patch"
    : >"${inputs_dir}/changed-files.txt"
  fi

  if [[ -f "${plan_dir}/plan.md" ]]; then
    cp "${plan_dir}/plan.md" "${inputs_dir}/plan.md"
  else
    : >"${inputs_dir}/plan.md"
  fi

  if [[ -f "${done_dir}/item-${item_id}.txt" ]]; then
    cp "${done_dir}/item-${item_id}.txt" "${inputs_dir}/done-summary.txt"
  else
    : >"${inputs_dir}/done-summary.txt"
  fi
}

# Parse a doc-writer agent log into a `documenting/item-N.txt` payload.
# stdout: first line "PASS" or "FAIL", body is the report block (or
# diagnostic if missing).
#
# Mapping: status: PASS / NO_CHANGES_NEEDED → PASS;
#          status: BLOCKED → FAIL; missing/unknown → FAIL.
orch_document_parse_report() {
  local log_file="$1"

  if [[ ! -f "${log_file}" ]]; then
    printf 'FAIL\nlog file missing: %s\n' "${log_file}"
    return 0
  fi

  local text
  # stream-json lines: { "type": "assistant", "message": { "content": [...] } }
  text=$(jq -rs '
    map(select((.type? // "") == "assistant"))
    | map(.message.content // [])
    | flatten
    | map(select((.type? // "") == "text") | .text)
    | join("\n")
  ' "${log_file}" 2>/dev/null) || text=""

  if [[ -z "${text}" ]]; then
    text=$(cat "${log_file}" 2>/dev/null || printf '')
  fi

  local block
  block=$(printf '%s\n' "${text}" | awk '
    /^```doc-writer-report[[:space:]]*$/ { capturing = 1; buf = ""; next }
    capturing && /^```[[:space:]]*$/ { last = buf; capturing = 0; next }
    capturing { buf = buf $0 "\n" }
    END { if (capturing) last = buf; printf "%s", last }
  ')

  if [[ -z "${block}" ]]; then
    printf 'FAIL\nNo doc-writer-report block found in agent output.\n'
    return 0
  fi

  local status
  status=$(printf '%s\n' "${block}" | grep -m1 -E '^status:' |
    sed -E 's/^status:[[:space:]]*//' | tr -d '[:space:]' || true)

  case "${status}" in
  PASS | NO_CHANGES_NEEDED)
    printf 'PASS\n%s' "${block}"
    ;;
  BLOCKED)
    printf 'FAIL\n%s' "${block}"
    ;;
  *)
    printf 'FAIL\nunexpected status %q\n%s' "${status}" "${block}"
    ;;
  esac
}

# Persist a parsed report to the documenting/item-N.txt file.
orch_document_persist_report() {
  local slug="$1" item_id="$2" log_file="$3"
  local doc_dir
  doc_dir=$(orch_plan_documenting_dir "${slug}")
  mkdir -p "${doc_dir}"
  orch_document_parse_report "${log_file}" >"${doc_dir}/item-${item_id}.txt"
}

# Extract the `edited_files:` list from a documenting/item-N.txt payload.
# Echoes one path per line. Empty output means NO_CHANGES_NEEDED or no list.
orch_document_extract_edited_files() {
  local doc_file="$1"
  if [[ ! -f "${doc_file}" ]]; then
    return 0
  fi
  awk '
    BEGIN { capturing = 0 }
    /^edited_files:/ {
      # Inline form: edited_files: [] or edited_files: [a, b]
      rest = $0
      sub(/^edited_files:[[:space:]]*/, "", rest)
      if (rest == "" || rest == "[]") {
        capturing = 1
        next
      }
      # Inline list — strip brackets and split
      gsub(/^\[|\]$/, "", rest)
      n = split(rest, arr, /,[[:space:]]*/)
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]"\047]+|[[:space:]"\047]+$/, "", arr[i])
        if (arr[i] != "") print arr[i]
      }
      capturing = 1
      next
    }
    capturing {
      if (/^[[:space:]]*-[[:space:]]+/) {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]+/, "", line)
        gsub(/^[[:space:]"\047]+|[[:space:]"\047]+$/, "", line)
        if (line != "") print line
        next
      }
      if (/^[^[:space:]]/) capturing = 0
    }
  ' "${doc_file}"
}

# Library mode: when sourced, do not run main loop.
if [[ "${BASH_SOURCE[0]:-}" != "${0}" ]]; then
  return 0
fi

# --- Main entry point (only runs when invoked directly) ---

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
  echo "error: usage: orch-document.sh <slug>" >&2
  exit 1
fi

GH_SYNC="${GH_SYNC:-false}"

ORCH_STATE_FILE=$(orch_plan_state_file "${SLUG}")
DONE_DIR=$(orch_plan_done_dir "${SLUG}")
DOC_DIR=$(orch_plan_documenting_dir "${SLUG}")
LOG_DIR=$(orch_plan_log_dir "${SLUG}")
WORKTREE_DIR="${ORCH_STATE_DIR}/worktrees/${SLUG}"

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

if [[ ! -f "${DOC_AGENT_PROMPT_FILE}" ]]; then
  echo "error: doc-writer prompt not found: ${DOC_AGENT_PROMPT_FILE}" >&2
  exit 1
fi

# --- Init phase state (idempotent) ---

orch_init_documentation_state "${SLUG}"
orch_document_prepare_item_states "${SLUG}"

mkdir -p "${DOC_DIR}" "${LOG_DIR}"

MAX_WORKERS=$(jq '.maxParallelWorkers // 4' "${ORCH_STATE_FILE}")
POLL_INTERVAL=$(orch_read_config "review_poll_interval_seconds")
POLL_INTERVAL="${POLL_INTERVAL:-10}"

DOCUMENTABLE=$(jq '[.items[] | select(.docStatus == "pending")] | length' \
  "${ORCH_STATE_FILE}")
SKIPPED=$(jq '[.items[] | select(.docStatus == "skipped")] | length' \
  "${ORCH_STATE_FILE}")

if [[ "${DOCUMENTABLE}" -eq 0 ]]; then
  echo "orch-document: 0 items eligible to document (${SKIPPED} skipped) — aggregating empty pass"
  result=$(orch_document_aggregate "${SLUG}")
  echo "orch-document: ${result}"
  exit 0
fi

echo "orch-document: starting per-item documenting phase"
echo "  items to document: ${DOCUMENTABLE}"
echo "  items skipped (work-failed): ${SKIPPED}"
echo "  max concurrent documenters: ${MAX_WORKERS}"
echo "  poll interval: ${POLL_INTERVAL}s"

TMUX_SESSION="orch-${SLUG}"

# --- Spawn helper ---

spawn_documenter() {
  local item_id="$1"
  local item_desc="$2"
  local window_name="documenter-${item_id}"

  orch_document_mark_documenting "${SLUG}" "${item_id}"
  orch_document_stage_inputs "${WORKTREE_DIR}" "${PLAN_DIR}" \
    "${DONE_DIR}" "${item_id}" "${item_desc}"

  local prompt_body
  prompt_body=$(cat "${DOC_AGENT_PROMPT_FILE}")

  local prompt_file
  prompt_file=$(mktemp "${ORCH_STATE_DIR}/doc-writer-prompt-${item_id}-XXXXXX")
  mv "${prompt_file}" "${prompt_file}.md"
  prompt_file="${prompt_file}.md"
  {
    printf '%s\n' "${prompt_body}"
    printf '\n---\n\n'
    printf '## Your Assignment\n\n'
    printf -- '- **Item ID**: %s\n' "${item_id}"
    printf -- '- **Item description**: %s\n' "${item_desc}"
    printf -- '- **Inputs directory**: %s/inputs\n' "${WORKTREE_DIR}"
    printf -- '- **Working directory**: %s\n' "${WORKTREE_DIR}"
  } >"${prompt_file}"

  rm -f "${DOC_DIR}/item-${item_id}.txt"

  local doc_cwd="${REPO_ROOT}"
  if [[ -d "${WORKTREE_DIR}" ]]; then
    doc_cwd="${WORKTREE_DIR}"
  fi

  tmux kill-window -t "${TMUX_SESSION}:${window_name}" 2>/dev/null || true

  # Build the agent invocation. Claude gets explicit tool-scope flags so
  # the doc-writer cannot Bash, Write, or Edit non-markdown — see
  # plan.md Decision log "Tool scope enforced via explicit CLI flags".
  # For Codex/Gemini we degrade to prompt-only enforcement (logged).
  local agent_cmd_str
  local provider
  provider="$(dega_agent_type)"
  if [[ "${provider}" == "claude" ]]; then
    # shellcheck disable=SC2016  # literal $(cat '...') is intended for tmux shell
    agent_cmd_str="claude --verbose --output-format stream-json --permission-mode acceptEdits --allowed-tools 'Read' 'Edit(*.md)' 'Glob' 'Grep' --disallowed-tools 'Bash' 'Write' -p \"\$(cat '${prompt_file}')\""
  else
    echo "orch-document: WARN — provider ${provider} does not support tool-scope flags; using prompt-only enforcement" >&2
    local cmd_template prompt_replacement
    cmd_template="$(dega_agent_build_headless_cmd "DEGA_PROMPT_MARKER")"
    # shellcheck disable=SC2016  # literal $(cat '...') is intended for tmux shell
    prompt_replacement="\"\$(cat '${prompt_file}')\""
    agent_cmd_str="${cmd_template/DEGA_PROMPT_MARKER/${prompt_replacement}}"
  fi

  local session_var env_prefix
  session_var="$(dega_agent_session_var)"
  env_prefix=""
  if [[ -n "${session_var}" ]]; then
    env_prefix="env -u '${session_var}'"
  fi

  local agent_timeout="${ORCH_DOCUMENT_AGENT_TIMEOUT:-300}"
  local raw_log="${LOG_DIR}/documenter-${item_id}.log"
  : >"${raw_log}"

  tmux new-window -d -t "${TMUX_SESSION}" -n "${window_name}" \
    "cd '${doc_cwd}' && \
     GH_SYNC='${GH_SYNC}' \
     ${env_prefix} timeout ${agent_timeout} ${agent_cmd_str} ; \
     echo '--- documenter ${item_id} exited ---'; \
     sleep 2"

  tmux pipe-pane -t "${TMUX_SESSION}:${window_name}" \
    -o "cat >> '${raw_log}'"

  echo "orch-document: spawned ${window_name} for item ${item_id}: ${item_desc}"
}

# --- Persist reports for items whose tmux window has exited ---

persist_pending_reports() {
  if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
    return 0
  fi

  local documenting_ids
  documenting_ids=$(jq -r \
    '.items[] | select(.docStatus == "documenting") | .id' \
    "${ORCH_STATE_FILE}")
  if [[ -z "${documenting_ids}" ]]; then
    return 0
  fi

  local live_windows
  live_windows=$(tmux list-windows -t "${TMUX_SESSION}" \
    -F '#{window_name} #{pane_dead}' 2>/dev/null || true)

  for item_id in ${documenting_ids}; do
    local window_name="documenter-${item_id}"
    local raw_log="${LOG_DIR}/documenter-${item_id}.log"
    local doc_file="${DOC_DIR}/item-${item_id}.txt"

    if [[ -f "${doc_file}" ]]; then
      continue
    fi

    # Persist when the window is NOT alive — either `pane_dead=1` (exited
    # but still listed) OR gone entirely (default tmux removes a window
    # when its pane exits, so between two polls a window can transition
    # alive → gone without ever being observed as pane_dead=1). The
    # pipe-pane log is written eagerly to ${raw_log}, so it exists even
    # when tmux has already dropped the window. Without this, a clean
    # documenter exit between polls leaves docStatus=documenting until
    # detect_stale_documenters marks it failed — triggering a spurious
    # REVISE loop on items the doc-writer actually completed.
    if ! printf '%s\n' "${live_windows}" | grep -q "^${window_name} 0$"; then
      if [[ -f "${raw_log}" ]]; then
        orch_document_persist_report "${SLUG}" "${item_id}" "${raw_log}"
      else
        printf 'FAIL\ndocumenter exited with no log file\n' >"${doc_file}"
      fi
    fi
  done
}

# --- Kill finished documenter windows ---

kill_done_documenters() {
  if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
    return 0
  fi

  local done_statuses
  done_statuses=$(jq -r \
    '.items[] | select(.docStatus == "passed" or .docStatus == "failed") | .id' \
    "${ORCH_STATE_FILE}")

  if [[ -z "${done_statuses}" ]]; then
    return 0
  fi

  local live_windows
  live_windows=$(tmux list-windows -t "${TMUX_SESSION}" \
    -F '#{window_name}' 2>/dev/null || true)

  for item_id in ${done_statuses}; do
    local window_name="documenter-${item_id}"
    if printf '%s\n' "${live_windows}" | grep -qx "${window_name}"; then
      tmux kill-window -t "${TMUX_SESSION}:${window_name}" 2>/dev/null || true
      echo "orch-document: killed finished documenter window ${window_name}"
    fi
  done
}

# --- Detect dead-window items that produced no doc file ---

detect_stale_documenters() {
  if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
    return 0
  fi

  local documenting_ids
  documenting_ids=$(jq -r \
    '.items[] | select(.docStatus == "documenting") | .id' \
    "${ORCH_STATE_FILE}")

  if [[ -z "${documenting_ids}" ]]; then
    return 0
  fi

  local live_windows
  live_windows=$(tmux list-windows -t "${TMUX_SESSION}" \
    -F '#{window_name} #{pane_dead}' 2>/dev/null || true)

  local state
  state=$(cat "${ORCH_STATE_FILE}")
  local changed=false
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  for item_id in ${documenting_ids}; do
    local window_name="documenter-${item_id}"
    local is_alive=false

    if printf '%s\n' "${live_windows}" | grep -q "^${window_name} 0$"; then
      is_alive=true
    fi

    if [[ "${is_alive}" == false ]]; then
      state=$(printf '%s' "${state}" | jq \
        --argjson id "${item_id}" \
        --arg now "${now}" \
        '(.items[] | select(.id == $id)).docStatus = "failed"
         | .updatedAt = $now')
      echo "orch-document: documenter for item ${item_id} exited without writing doc — marking failed"
      changed=true
    fi
  done

  if [[ "${changed}" == "true" ]]; then
    orch_write_state "${SLUG}" "${state}"
  fi
}

# --- Build per-item docs commits ---
#
# After all docs PASS, walk passed items in id order and commit their
# edited_files separately. Items whose report had an empty edited_files
# (NO_CHANGES_NEEDED) produce no commit.
build_docs_commits() {
  if [[ ! -d "${WORKTREE_DIR}" ]]; then
    echo "orch-document: no worktree at ${WORKTREE_DIR} — skipping docs commits"
    return 0
  fi

  local passed_ids
  passed_ids=$(jq -r '.items[] | select(.docStatus == "passed") | .id' \
    "${ORCH_STATE_FILE}" | sort -n)

  for item_id in ${passed_ids}; do
    local doc_file="${DOC_DIR}/item-${item_id}.txt"
    [[ -f "${doc_file}" ]] || continue

    local edited
    edited=$(orch_document_extract_edited_files "${doc_file}")
    if [[ -z "${edited}" ]]; then
      continue
    fi

    local item_desc
    item_desc=$(jq -r \
      ".items[] | select(.id == ${item_id}) | .description" \
      "${ORCH_STATE_FILE}")

    local files_to_add=()
    while IFS= read -r f; do
      [[ -z "${f}" ]] && continue
      if [[ "${f}" != *.md ]]; then
        echo "orch-document: WARN — item ${item_id} edited non-markdown ${f}; skipping" >&2
        continue
      fi
      if [[ -f "${WORKTREE_DIR}/${f}" ]]; then
        files_to_add+=("${f}")
      fi
    done <<<"${edited}"

    if [[ ${#files_to_add[@]} -eq 0 ]]; then
      continue
    fi

    git -C "${WORKTREE_DIR}" add -- "${files_to_add[@]}"
    if git -C "${WORKTREE_DIR}" diff --cached --quiet; then
      echo "orch-document: item ${item_id} — no staged docs changes (already committed?)"
      continue
    fi
    if git -C "${WORKTREE_DIR}" commit --no-verify \
      -m "docs(item-${item_id}): ${item_desc}"; then
      echo "orch-document: committed docs(item-${item_id})"
    else
      echo "orch-document: WARN — failed to commit docs(item-${item_id}) (exit $?)" >&2
    fi
  done
}

# --- Poll loop ---

while true; do
  persist_pending_reports
  orch_sync_documenting_files "${SLUG}"
  kill_done_documenters
  detect_stale_documenters

  cnt_documenting=$(jq '[.items[] | select(.docStatus == "documenting")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_pending=$(jq '[.items[] | select(.docStatus == "pending")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_passed=$(jq '[.items[] | select(.docStatus == "passed")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_failed=$(jq '[.items[] | select(.docStatus == "failed")] | length' \
    "${ORCH_STATE_FILE}")
  cnt_skipped=$(jq '[.items[] | select(.docStatus == "skipped")] | length' \
    "${ORCH_STATE_FILE}")

  echo "orch-document: [poll] documenting=${cnt_documenting} pending=${cnt_pending} passed=${cnt_passed} failed=${cnt_failed} skipped=${cnt_skipped}"

  if [[ "${cnt_documenting}" -eq 0 ]] && [[ "${cnt_pending}" -eq 0 ]]; then
    echo "orch-document: phase complete — ${cnt_passed} passed, ${cnt_failed} failed, ${cnt_skipped} skipped"
    break
  fi

  available_slots=$((MAX_WORKERS - cnt_documenting))
  if ((available_slots > 0 && cnt_pending > 0)); then
    pending_ids=$(jq -r \
      '.items[] | select(.docStatus == "pending") | .id' \
      "${ORCH_STATE_FILE}")
    spawned=0
    for pid in ${pending_ids}; do
      if ((spawned >= available_slots)); then break; fi
      pdesc=$(jq -r \
        ".items[] | select(.id == ${pid}) | .description" \
        "${ORCH_STATE_FILE}")
      spawn_documenter "${pid}" "${pdesc}"
      spawned=$((spawned + 1))
    done
  fi

  sleep "${POLL_INTERVAL}"
done

# --- Aggregate ---

result=$(orch_document_aggregate "${SLUG}")

if [[ "${result}" == "SHIP" ]]; then
  echo "orch-document: SHIP — building per-item docs commits"
  build_docs_commits
  exit 0
fi

# REVISE: write feedback file for the engine + workers
FAILED_IDS=$(jq -r '.documentation.reworkItems[]?' "${ORCH_STATE_FILE}")
FEEDBACK_FILE="${PLAN_DIR}/document-feedback.txt"
{
  printf 'REWORK_ITEMS: %s\n' \
    "$(printf '%s\n' "${FAILED_IDS}" | paste -sd ', ' -)"
  for fid in ${FAILED_IDS}; do
    doc="${DOC_DIR}/item-${fid}.txt"
    if [[ -f "${doc}" ]]; then
      printf '\n--- item %s (documenter failed) ---\n' "${fid}"
      tail -n +2 "${doc}"
    fi
  done
} >"${FEEDBACK_FILE}"

echo "orch-document: REVISE — rework items: $(printf '%s\n' "${FAILED_IDS}" | paste -sd ', ' -)"
echo "  Feedback written to ${FEEDBACK_FILE}"
exit 0
