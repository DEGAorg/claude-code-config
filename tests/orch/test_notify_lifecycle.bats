#!/usr/bin/env bats
#
# Tests for hooks/orch-lifecycle/02-agent-notify.sh.
#
# The lifecycle hook reads .orchestrator/plans/<slug>/state.json and writes
# .orchestrator/notifications/<slug>.json on terminal events. This test
# covers the `ship` path: a fixture state.json with finalReview.prUrl /
# finalReview.prNumber should produce a notification file containing all
# documented schema keys.

REPO_ROOT_REAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
HOOK="${REPO_ROOT_REAL}/hooks/orch-lifecycle/02-agent-notify.sh"

setup() {
  TEST_TMP="$(mktemp -d -t orch-notify-lifecycle-XXXXXX)"
  export TEST_TMP

  SLUG="example-plan"
  export SLUG

  PLAN_DIR="${TEST_TMP}/.orchestrator/plans/${SLUG}"
  NOTIF_DIR="${TEST_TMP}/.orchestrator/notifications"
  mkdir -p "${PLAN_DIR}"
  export PLAN_DIR
  export NOTIF_DIR

  cat >"${PLAN_DIR}/state.json" <<'JSON'
{
  "slug": "example-plan",
  "issueNumber": 123,
  "status": "completed",
  "finalReview": {
    "decision": "SHIP",
    "prUrl": "https://github.com/example/repo/pull/456",
    "prNumber": 456
  }
}
JSON
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

@test "ship event writes notification with all required schema keys" {
  cd "${TEST_TMP}"
  run bash "${HOOK}" ship "${SLUG}" --items 4 --passed 4 --elapsed 12m
  [ "${status}" -eq 0 ]

  NOTIF_FILE="${NOTIF_DIR}/${SLUG}.json"
  [ -f "${NOTIF_FILE}" ]

  # Required keys present.
  for key in slug status prUrl prNumber issueNumber summary createdAt seen; do
    run jq -e --arg k "${key}" 'has($k)' "${NOTIF_FILE}"
    [ "${status}" -eq 0 ]
  done

  # Required values match the fixture.
  run jq -e '.slug == "example-plan"' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
  run jq -e '.status == "completed"' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
  run jq -e '.prUrl == "https://github.com/example/repo/pull/456"' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
  run jq -e '.prNumber == 456' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
  run jq -e '.issueNumber == 123' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
  run jq -e '.seen == false' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
  run jq -e '.summary | type == "string" and length > 0' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
  run jq -e '.createdAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "${NOTIF_FILE}"
  [ "${status}" -eq 0 ]
}
