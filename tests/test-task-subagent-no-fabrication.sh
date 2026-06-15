#!/usr/bin/env bash
# Probe: does a Task subagent reliably Write a file, or does it fabricate?
#
# Runs 3 iterations of: spawn `claude -p` headless, ask it to delegate a
# file-write to a general-purpose Task subagent, then check the file actually
# landed on disk with the deterministic token we asked for.
#
# Context: prior investigation traced canon-tui's "narrate-don't-execute"
# fabrication to Claude Code v2.1.69+ deferring built-in tools behind
# ToolSearch (see .scratch/canon-tui-fabrication-final-findings.md). The
# documented workaround is ENABLE_TOOL_SEARCH=false. This probe answers:
# with that env var set, does a Task subagent now reliably execute the
# Write tool, or does it still narrate a fabricated success?
#
# Three iterations because fabrication is probabilistic — one PASS in
# isolation is not a signal.
#
# Exit code: this is an informational probe, not a regression test. It
# always exits 0 when it ran to completion (claude binary present, all
# iterations attempted). The data point the caller wants is in the
# "PASS: N FAIL: N" summary line. Callers that want to gate on the result
# should grep the summary, not the exit code.
#
# Usage:
#   bash tests/test-task-subagent-no-fabrication.sh
#
# Env:
#   CLAUDE_BIN   path to claude binary (default: claude)
#   ITERATIONS   number of probe runs (default: 3)
#   PROBE_MODEL  model to pin (default: unset — uses claude's default)
#   PROBE_TIMEOUT  per-iteration wall-clock cap in seconds (default: 180)
#
# Skips (exit 0, no failure) when claude is not on PATH — keeps this safe
# to run in CI where claude isn't authenticated.

set -euo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
ITERATIONS="${ITERATIONS:-3}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-180}"

if ! command -v "${CLAUDE_BIN}" >/dev/null 2>&1; then
  printf 'SKIP: %s not found on PATH — probe requires a working Claude Code CLI\n' "${CLAUDE_BIN}"
  exit 0
fi

# timeout(1) is GNU; on macOS it lives as gtimeout under coreutils. Fall back
# to no-timeout if neither is available — better to run than to skip silently.
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

PASS=0
FAIL=0
RESULTS=()
WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "${WORK_ROOT}"' EXIT

run_probe() {
  local i="$1"
  local work_dir="${WORK_ROOT}/iter-${i}"
  mkdir -p "${work_dir}"

  local token
  token="PROBE-$$-${i}-$(date +%s)"
  local target="${work_dir}/probe-output.txt"
  local log="${work_dir}/claude.log"

  # Prompt the agent to delegate to a general-purpose subagent. The subagent
  # is the unit under test: does it actually invoke Write, or does it claim
  # success without touching the disk?
  local prompt
  prompt="Use the Task tool with subagent_type \"general-purpose\" to write a file.

The subagent MUST use the Write tool to create exactly one file at this
absolute path:

  ${target}

The file contents must be exactly the following single line (no leading
or trailing whitespace, no markdown, no extra newlines beyond the line
itself):

  ${token}

After the subagent reports done, reply with just \"OK\". Do not perform
the Write yourself — delegate to the subagent. Do not write anything to
chat beyond \"OK\"."

  # Nested-session guard: claude refuses to launch inside another claude
  # session unless CLAUDECODE / CLAUDE_CODE_ENTRYPOINT are unset. ENABLE_TOOL_SEARCH=false
  # disables the deferred-tools mechanism that prior investigation
  # identified as the fabrication trigger.
  local -a cmd=(
    env
    -u CLAUDECODE
    -u CLAUDE_CODE_ENTRYPOINT
    ENABLE_TOOL_SEARCH=false
  )
  if [[ -n "${TIMEOUT_BIN}" ]]; then
    cmd+=("${TIMEOUT_BIN}" "${PROBE_TIMEOUT}")
  fi
  cmd+=(
    "${CLAUDE_BIN}"
    -p
    --output-format text
    --permission-mode bypassPermissions
    --add-dir "${work_dir}"
    --no-session-persistence
  )
  if [[ -n "${PROBE_MODEL:-}" ]]; then
    cmd+=(--model "${PROBE_MODEL}")
  fi
  cmd+=("${prompt}")

  local exit_code=0
  "${cmd[@]}" >"${log}" 2>&1 || exit_code=$?

  if [[ ${exit_code} -ne 0 ]]; then
    printf '  iter %d: FAIL — claude exited %d\n' "${i}" "${exit_code}"
    printf '    log tail:\n'
    tail -20 "${log}" 2>/dev/null | sed 's/^/      /'
    FAIL=$((FAIL + 1))
    RESULTS+=("iter ${i}: FAIL (claude exit ${exit_code})")
    return 0
  fi

  if [[ ! -f "${target}" ]]; then
    printf '  iter %d: FAIL — target file not written: %s\n' "${i}" "${target}"
    printf '    log tail:\n'
    tail -20 "${log}" 2>/dev/null | sed 's/^/      /'
    FAIL=$((FAIL + 1))
    RESULTS+=("iter ${i}: FAIL (file missing — likely fabrication)")
    return 0
  fi

  local actual
  actual="$(cat "${target}")"
  if [[ "${actual}" != "${token}" ]]; then
    printf '  iter %d: FAIL — file contents mismatch\n' "${i}"
    printf '    expected: %s\n' "${token}"
    printf '    actual:   %s\n' "${actual}"
    FAIL=$((FAIL + 1))
    RESULTS+=("iter ${i}: FAIL (content mismatch)")
    return 0
  fi

  printf '  iter %d: PASS\n' "${i}"
  PASS=$((PASS + 1))
  RESULTS+=("iter ${i}: PASS")
}

printf 'Probe: Task-subagent -> Write file (%d iterations)\n' "${ITERATIONS}"
printf '  claude:  %s\n' "$(command -v "${CLAUDE_BIN}")"
printf '  version: %s\n' "$("${CLAUDE_BIN}" --version 2>/dev/null | head -1 || printf 'unknown')"
printf '  env:     ENABLE_TOOL_SEARCH=false  CLAUDECODE=unset\n'
printf '\n'

for i in $(seq 1 "${ITERATIONS}"); do
  run_probe "${i}"
done

printf '\n================================\n'
printf '  PASS: %d  FAIL: %d  (of %d)\n' "${PASS}" "${FAIL}" "${ITERATIONS}"
printf '================================\n'
for r in "${RESULTS[@]}"; do
  printf '  %s\n' "${r}"
done

# Always exit 0 — this is an informational probe. Caller decides what the
# PASS/FAIL count means for the plan's next step.
exit 0
