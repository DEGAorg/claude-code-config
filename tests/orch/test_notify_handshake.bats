#!/usr/bin/env bats
#
# End-to-end handshake test for the orch agent-notification hooks.
#
# The unit tests for the lifecycle hook (test_notify_lifecycle.bats) and the
# Stop hook (test_notify_stop_hook.bats) each use their own isolated fixture.
# That leaves a gap: a schema drift between what the lifecycle hook writes
# and what the Stop hook expects to read would not be caught.
#
# This test runs both hooks against a single shared fixture in sequence:
#   1. Lifecycle hook writes the notification (`ship` event).
#   2. Stop hook reads it, emits block JSON, marks it seen.
#   3. Stop hook re-runs and produces no output (idempotency end-to-end).
#
# If the file format ever drifts between the two scripts, this test fails.

REPO_ROOT_REAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
LIFECYCLE_HOOK="${REPO_ROOT_REAL}/hooks/orch-lifecycle/02-agent-notify.sh"
STOP_HOOK="${REPO_ROOT_REAL}/hooks/stop/01-orch-notify.sh"

setup() {
  TEST_TMP="$(mktemp -d -t orch-notify-handshake-XXXXXX)"
  export TEST_TMP
  export CLAUDE_PROJECT_DIR="${TEST_TMP}"

  SLUG="handshake-plan"
  export SLUG

  PLAN_DIR="${TEST_TMP}/.orchestrator/plans/${SLUG}"
  NOTIF_DIR="${TEST_TMP}/.orchestrator/notifications"
  mkdir -p "${PLAN_DIR}"
  export PLAN_DIR
  export NOTIF_DIR

  cat >"${PLAN_DIR}/state.json" <<'JSON'
{
  "slug": "handshake-plan",
  "issueNumber": 777,
  "status": "completed",
  "finalReview": {
    "decision": "SHIP",
    "prUrl": "https://github.com/DEGAorg/claude-code-config/pull/777",
    "prNumber": 777
  }
}
JSON
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

@test "lifecycle ship → stop hook surfaces the notification end-to-end" {
  cd "${TEST_TMP}"

  # 1. Lifecycle hook produces the notification.
  run bash "${LIFECYCLE_HOOK}" ship "${SLUG}" --items 6 --passed 6 --elapsed 8m
  [ "${status}" -eq 0 ]
  [ -f "${NOTIF_DIR}/${SLUG}.json" ]

  # 2. Stop hook consumes the file and emits valid block JSON.
  run bash "${STOP_HOOK}" </dev/null
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  printf '%s' "${output}" | jq -e '.decision == "block"' >/dev/null
  printf '%s' "${output}" | jq -e '.reason | type == "string" and length > 0' >/dev/null

  # The reason must reference the slug AND the PR url that the lifecycle
  # hook persisted from state.json — proving the schema contract holds.
  printf '%s' "${output}" | jq -e --arg slug "${SLUG}" '.reason | contains($slug)' >/dev/null
  printf '%s' "${output}" | jq -e '.reason | contains("pull/777")' >/dev/null

  # 3. Notification is now marked seen.
  run jq -e '.seen == true' "${NOTIF_DIR}/${SLUG}.json"
  [ "${status}" -eq 0 ]

  # 4. Second Stop hook run is silent (no double-injection).
  run bash "${STOP_HOOK}" </dev/null
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "lifecycle verify-failed → stop hook surfaces the failure" {
  cd "${TEST_TMP}"

  # Replace state.json with a verify-failed fixture.
  cat >"${PLAN_DIR}/state.json" <<'JSON'
{
  "slug": "handshake-plan",
  "issueNumber": 777,
  "status": "in_progress",
  "verification": {
    "status": "failed",
    "uncheckedCount": 3
  }
}
JSON

  run bash "${LIFECYCLE_HOOK}" verify "${SLUG}"
  [ "${status}" -eq 0 ]
  [ -f "${NOTIF_DIR}/${SLUG}.json" ]

  run jq -e '.status == "failed"' "${NOTIF_DIR}/${SLUG}.json"
  [ "${status}" -eq 0 ]

  run bash "${STOP_HOOK}" </dev/null
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | jq -e '.decision == "block"' >/dev/null
  printf '%s' "${output}" | jq -e '.reason | contains("failed")' >/dev/null
}
