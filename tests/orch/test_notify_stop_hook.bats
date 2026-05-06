#!/usr/bin/env bats
#
# Tests for hooks/stop/01-orch-notify.sh.
#
# The Stop hook scans ${CLAUDE_PROJECT_DIR}/.orchestrator/notifications/*.json
# for entries with `seen: false`, emits a Claude Code Stop-hook block JSON
# ({"decision": "block", "reason": "..."}) on stdout, and marks each entry
# `seen: true` via atomic rewrite. A second invocation with no unseen
# entries must be silent (idempotent).

REPO_ROOT_REAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
HOOK="${REPO_ROOT_REAL}/hooks/stop/01-orch-notify.sh"

setup() {
  TEST_TMP="$(mktemp -d -t orch-stop-hook-XXXXXX)"
  export TEST_TMP
  export CLAUDE_PROJECT_DIR="${TEST_TMP}"

  NOTIF_DIR="${TEST_TMP}/.orchestrator/notifications"
  mkdir -p "${NOTIF_DIR}"
  export NOTIF_DIR

  cat >"${NOTIF_DIR}/example-plan.json" <<'JSON'
{
  "slug": "example-plan",
  "status": "ship",
  "issueNumber": 123,
  "prNumber": 456,
  "prUrl": "https://github.com/example/repo/pull/456",
  "summary": "All items shipped.",
  "seen": false
}
JSON
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

@test "stop hook emits block JSON with non-empty reason and marks entries seen" {
  run bash "${HOOK}" </dev/null
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  # stdout must be a JSON object with decision == "block" and a non-empty reason.
  printf '%s' "${output}" | jq -e '.decision == "block"' >/dev/null
  printf '%s' "${output}" | jq -e '.reason | type == "string" and length > 0' >/dev/null

  # The notification file must now have seen: true.
  run jq -e '.seen == true' "${NOTIF_DIR}/example-plan.json"
  [ "${status}" -eq 0 ]
}

@test "stop hook is idempotent — second run produces no stdout" {
  run bash "${HOOK}" </dev/null
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  run bash "${HOOK}" </dev/null
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "stop hook is a no-op when notifications dir is absent" {
  rm -rf "${NOTIF_DIR}"
  run bash "${HOOK}" </dev/null
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
