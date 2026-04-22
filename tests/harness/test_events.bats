#!/usr/bin/env bats
#
# Smoke test for the orch event stream.
#
# Simulates a minimal plan lifecycle by invoking `harness::emit_event`
# in the same order the orchestrator (orch-run.sh, orch-engine.sh,
# orch-review.sh) does during a real run, then asserts the resulting
# events.jsonl is well-formed JSONL and the `evt` sequence matches the
# schema documented in scripts/harness/events-schema.md.
#
# Requires: bats-core, jq. If bats is not installed locally, see the
# plan risks note — the shellcheck/shfmt criteria are the hard gates.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/harness/local.sh"
  TMPDIR_TEST="$(mktemp -d)"
  EVENTS_FILE="${TMPDIR_TEST}/events.jsonl"
}

teardown() {
  if [[ -n "${TMPDIR_TEST:-}" && -d "${TMPDIR_TEST}" ]]; then
    rm -rf "${TMPDIR_TEST}"
  fi
}

@test "harness::emit_event produces valid JSONL for a full plan lifecycle" {
  # plan_start: emitted by orch-run.sh once after state init.
  run harness::emit_event "${EVENTS_FILE}" plan_start \
    slug=dummy-plan total_items:=2 max_parallel_workers:=2 mode=foreground
  [ "$status" -eq 0 ]

  # item_spawn + item_status per item, per orch-engine.sh.
  run harness::emit_event "${EVENTS_FILE}" item_spawn \
    slug=dummy-plan item:=1 iteration:=1 pid:=12345 \
    log_path=/tmp/worker-1.log worktree=/tmp/wt-1
  [ "$status" -eq 0 ]

  run harness::emit_event "${EVENTS_FILE}" item_status \
    slug=dummy-plan item:=1 from=ready to=running iteration:=1
  [ "$status" -eq 0 ]

  run harness::emit_event "${EVENTS_FILE}" item_status \
    slug=dummy-plan item:=1 from=running to=done iteration:=1
  [ "$status" -eq 0 ]

  # review_start + review_end per orch-review.sh.
  run harness::emit_event "${EVENTS_FILE}" review_start \
    slug=dummy-plan item:=1 iteration:=1 pid:=12346 log_path=/tmp/reviewer-1.log
  [ "$status" -eq 0 ]

  run harness::emit_event "${EVENTS_FILE}" review_end \
    slug=dummy-plan item:=1 iteration:=1 verdict=SHIP duration_ms:=123
  [ "$status" -eq 0 ]

  # plan_end: emitted by orch-run.sh / orch-engine.sh at termination.
  run harness::emit_event "${EVENTS_FILE}" plan_end \
    slug=dummy-plan status=completed total_items:=2 done_items:=2 \
    failed_items:=0 duration_ms:=4567
  [ "$status" -eq 0 ]

  # File exists and is non-empty.
  [ -s "${EVENTS_FILE}" ]

  # Every line is valid JSON.
  while IFS= read -r line; do
    [ -n "${line}" ]
    echo "${line}" | jq -e . >/dev/null
  done <"${EVENTS_FILE}"

  # Every line has required fields (ts, evt).
  run jq -se 'all(.[]; has("ts") and has("evt"))' "${EVENTS_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  # ts format: ISO-8601 UTC with .sssZ suffix.
  run jq -se 'all(.[]; .ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"))' "${EVENTS_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  # evt sequence matches the orchestrator contract.
  actual_seq="$(jq -r '.evt' "${EVENTS_FILE}" | tr '\n' ' ')"
  expected_seq="plan_start item_spawn item_status item_status review_start review_end plan_end "
  [ "${actual_seq}" = "${expected_seq}" ]

  # item_status transitions are well-formed (from != to).
  run jq -se 'all(.[] | select(.evt=="item_status"); .from != .to)' "${EVENTS_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]

  # Numeric raw-JSON fields are actual JSON numbers, not strings.
  run jq -sr '.[] | select(.evt=="item_spawn") | .item | type' "${EVENTS_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "number" ]

  run jq -sr '.[] | select(.evt=="plan_end") | .duration_ms | type' "${EVENTS_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" = "number" ]
}

@test "harness::emit_event rejects malformed arguments" {
  run harness::emit_event "${EVENTS_FILE}" plan_start badkvnoequals
  [ "$status" -ne 0 ]

  run harness::emit_event "${EVENTS_FILE}" plan_start "1badkey=foo"
  [ "$status" -ne 0 ]

  run harness::emit_event "" plan_start
  [ "$status" -ne 0 ]

  run harness::emit_event "${EVENTS_FILE}" ""
  [ "$status" -ne 0 ]
}

@test "harness::emit_event appends (does not truncate)" {
  harness::emit_event "${EVENTS_FILE}" plan_start slug=p
  harness::emit_event "${EVENTS_FILE}" plan_end slug=p status=completed
  run wc -l <"${EVENTS_FILE}"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '[:space:]')" = "2" ]
}
