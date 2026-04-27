#!/usr/bin/env bats
#
# Idempotency tests for hooks/orch-lifecycle/01-gh-plan-sync.sh.
#
# The hook must maintain a per-plan posted.json keyed by
# "${event}:${item_id_or_plan}:${iteration}". On duplicate keys it
# skips invoking gh-plan-sync.sh; on new keys it invokes the sync
# script and records the key only after gh exits 0.
#
# Test strategy: copy the real hook to a tempdir so SCRIPT_DIR resolves
# to the tempdir, then plant a stub gh-plan-sync.sh next to it. The
# stub records each invocation in $STUB_LOG and exits with the code in
# $STUB_EXIT (default 0). This isolates the hook's idempotency logic
# from the real sync script's gh + provider stack.

REPO_ROOT_REAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
HOOK_SRC="${REPO_ROOT_REAL}/hooks/orch-lifecycle/01-gh-plan-sync.sh"

setup() {
  TEST_TMP="$(mktemp -d -t orch-hook-idem-XXXXXX)"
  export TEST_TMP
  SLUG="idem-plan"
  export SLUG

  # Layout: tempdir mirrors the real repo's hook + sync-script tree
  # so the copied hook's relative SYNC_SCRIPT path resolves to the stub.
  mkdir -p "${TEST_TMP}/hooks/orch-lifecycle"
  mkdir -p "${TEST_TMP}/scripts"
  cp "${HOOK_SRC}" "${TEST_TMP}/hooks/orch-lifecycle/01-gh-plan-sync.sh"
  chmod +x "${TEST_TMP}/hooks/orch-lifecycle/01-gh-plan-sync.sh"

  STUB_LOG="${TEST_TMP}/sync-calls.log"
  export STUB_LOG
  : >"${STUB_LOG}"
  STUB_EXIT_FILE="${TEST_TMP}/sync-exit"
  export STUB_EXIT_FILE
  echo 0 >"${STUB_EXIT_FILE}"

  cat >"${TEST_TMP}/scripts/gh-plan-sync.sh" <<'STUB'
#!/usr/bin/env bash
# Stub sync script — records every invocation and exits with the code
# in $STUB_EXIT_FILE (default 0).
printf '%s\n' "$*" >>"${STUB_LOG}"
exit "$(cat "${STUB_EXIT_FILE}" 2>/dev/null || echo 0)"
STUB
  chmod +x "${TEST_TMP}/scripts/gh-plan-sync.sh"

  # dega-core.yaml with github.sync enabled (the hook greps "sync:").
  cat >"${TEST_TMP}/dega-core.yaml" <<'YAML'
github:
  sync: true
YAML

  # Plan state with an issue number and two review-ready items.
  PLAN_DIR="${TEST_TMP}/.orchestrator/plans/${SLUG}"
  mkdir -p "${PLAN_DIR}/done" "${PLAN_DIR}/reviews"
  cat >"${PLAN_DIR}/state.json" <<'JSON'
{
  "issueNumber": 4242,
  "items": [
    {"id": 1, "description": "first item", "iteration": 1, "lastResult": "SHIP"},
    {"id": 2, "description": "second item", "iteration": 1, "lastResult": "SHIP"}
  ],
  "finalReview": {"reworkItems": []}
}
JSON

  # Make the tempdir a git repo so `git rev-parse --show-toplevel`
  # resolves REPO_ROOT to TEST_TMP.
  git -C "${TEST_TMP}" init --quiet --initial-branch=main
  git -C "${TEST_TMP}" config user.email "test@example.com"
  git -C "${TEST_TMP}" config user.name "Test"

  HOOK="${TEST_TMP}/hooks/orch-lifecycle/01-gh-plan-sync.sh"
  export HOOK
  POSTED_JSON="${PLAN_DIR}/posted.json"
  export POSTED_JSON
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

# Count the number of invocations the stub recorded.
sync_call_count() {
  if [[ -s "${STUB_LOG}" ]]; then
    wc -l <"${STUB_LOG}" | tr -d ' '
  else
    echo 0
  fi
}

# True iff posted.json exists and contains the given key.
posted_has_key() {
  local key="$1"
  [[ -f "${POSTED_JSON}" ]] || return 1
  jq -e --arg k "${key}" 'has($k)' "${POSTED_JSON}" >/dev/null 2>&1
}

# --- new-post: first call posts and records the key ---

@test "review event posts when posted.json is absent and records the key" {
  cd "${TEST_TMP}"
  run "${HOOK}" review "${SLUG}"
  [ "${status}" -eq 0 ]

  # Both items should have triggered exactly one sync invocation.
  [ "$(sync_call_count)" -eq 2 ]

  # posted.json must exist and contain a key for each item at iter 1.
  [ -f "${POSTED_JSON}" ]
  posted_has_key "review:1:1"
  posted_has_key "review:2:1"
}

# --- duplicate-skip: pre-seeded keys cause the sync script to be skipped ---

@test "review event skips items whose key is already in posted.json" {
  cd "${TEST_TMP}"

  # Pre-seed posted.json with item 1's key only — item 2 should still post.
  printf '%s\n' '{"review:1:1": {"postedAt": "2026-04-27T00:00:00Z"}}' \
    >"${POSTED_JSON}"

  run "${HOOK}" review "${SLUG}"
  [ "${status}" -eq 0 ]

  # Only item 2 should have triggered a sync call.
  [ "$(sync_call_count)" -eq 1 ]
  grep -q -- '--item-id 2' "${STUB_LOG}"
  ! grep -q -- '--item-id 1' "${STUB_LOG}"

  # Both keys must now be present.
  posted_has_key "review:1:1"
  posted_has_key "review:2:1"
}

@test "review event with all keys pre-seeded performs zero sync calls" {
  cd "${TEST_TMP}"

  printf '%s\n' \
    '{"review:1:1": {"postedAt": "x"}, "review:2:1": {"postedAt": "y"}}' \
    >"${POSTED_JSON}"

  run "${HOOK}" review "${SLUG}"
  [ "${status}" -eq 0 ]
  [ "$(sync_call_count)" -eq 0 ]
}

# --- gh-failure-no-record: a failed sync call must NOT record the key ---

@test "review event does not record key when sync script exits nonzero" {
  cd "${TEST_TMP}"

  # Force the stub to fail so the hook's gh path returns nonzero.
  echo 1 >"${STUB_EXIT_FILE}"

  run "${HOOK}" review "${SLUG}"
  # Hook is best-effort — it should still exit 0 even if a post failed.
  [ "${status}" -eq 0 ]

  # The stub WAS invoked (twice — one per item) but no key may be recorded
  # because the sync script reported failure. A subsequent run must retry.
  [ "$(sync_call_count)" -eq 2 ]

  if [[ -f "${POSTED_JSON}" ]]; then
    run jq -e 'has("review:1:1")' "${POSTED_JSON}"
    [ "${status}" -ne 0 ]
    run jq -e 'has("review:2:1")' "${POSTED_JSON}"
    [ "${status}" -ne 0 ]
  fi

  # Subsequent run with stub now succeeding must repost and record.
  echo 0 >"${STUB_EXIT_FILE}"
  : >"${STUB_LOG}"
  run "${HOOK}" review "${SLUG}"
  [ "${status}" -eq 0 ]
  [ "$(sync_call_count)" -eq 2 ]
  posted_has_key "review:1:1"
  posted_has_key "review:2:1"
}

# --- iteration bump: a new iteration is a new key ---

@test "review event posts again when item iteration advances" {
  cd "${TEST_TMP}"

  # First pass at iteration 1 records keys.
  run "${HOOK}" review "${SLUG}"
  [ "${status}" -eq 0 ]
  posted_has_key "review:1:1"

  # Bump item 1 to iteration 2 in state.json. The new key must not be
  # in posted.json yet, so the hook must repost for that item.
  jq '.items[0].iteration = 2' "${TEST_TMP}/.orchestrator/plans/${SLUG}/state.json" \
    >"${TEST_TMP}/state.tmp"
  mv "${TEST_TMP}/state.tmp" "${TEST_TMP}/.orchestrator/plans/${SLUG}/state.json"

  : >"${STUB_LOG}"
  run "${HOOK}" review "${SLUG}"
  [ "${status}" -eq 0 ]

  # Item 1 reposts at iter 2; item 2 still at iter 1, already recorded → skipped.
  [ "$(sync_call_count)" -eq 1 ]
  grep -q -- '--item-id 1' "${STUB_LOG}"
  posted_has_key "review:1:2"
}
