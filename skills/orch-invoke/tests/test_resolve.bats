#!/usr/bin/env bats
#
# Tests for skills/orch-invoke/resolve.sh.
#
# Run with:  bats skills/orch-invoke/tests/test_resolve.bats
#
# The resolver loads candidate issues from $ORCH_INVOKE_ISSUES_FIXTURE when
# that variable is set, which lets these tests exercise all four status
# branches deterministically without calling `gh`.

setup() {
  SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RESOLVE="$SKILL_DIR/resolve.sh"
  export ORCH_INVOKE_ISSUES_FIXTURE="$SKILL_DIR/tests/fixtures/issues.json"
}

@test "explicit issue number resolves to exact with matching slug" {
  run "$RESOLVE" "run issue 214 in the background"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "exact" ]
  [ "$(jq -r '.issue'  <<<"$output")" = "214" ]
  [ "$(jq -r '.slug'   <<<"$output")" = "20260422-orch-events" ]
}

@test "hash-prefixed issue number is recognized" {
  run "$RESOLVE" "kick off #213"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "exact" ]
  [ "$(jq -r '.issue'  <<<"$output")" = "213" ]
  [ "$(jq -r '.slug'   <<<"$output")" = "20260422-orch-invoke-skill" ]
}

@test "unique keyword match returns status=match with single candidate" {
  run "$RESOLVE" "run the canon demo plan"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "match" ]
  [ "$(jq -r '.issue'  <<<"$output")" = "180" ]
  [ "$(jq -r '.slug'   <<<"$output")" = "20260410-canon-demo-flow" ]
  [ "$(jq -r '.candidates | length' <<<"$output")" = "1" ]
}

@test "tied keyword scores produce status=ambiguous with candidates listed" {
  run "$RESOLVE" "run the migration plan"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "ambiguous" ]
  [ "$(jq -r '.issue'  <<<"$output")" = "null" ]
  [ "$(jq -r '.candidates | length' <<<"$output")" -ge 2 ]
  # Both "harness-migration" and "tui-migration" should appear.
  numbers=$(jq -r '.candidates[].issue' <<<"$output" | sort -n | tr '\n' ' ')
  [[ "$numbers" == *"206"* ]]
  [[ "$numbers" == *"209"* ]]
}

@test "no keyword overlap yields status=empty" {
  run "$RESOLVE" "please asdfqwerty zxcvbnm"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status'             <<<"$output")" = "empty" ]
  [ "$(jq -r '.issue'              <<<"$output")" = "null" ]
  [ "$(jq -r '.slug'               <<<"$output")" = "null" ]
  [ "$(jq -r '.candidates | length' <<<"$output")" = "0" ]
}

@test "explicit slug resolves to exact with its issue number" {
  run "$RESOLVE" "run 20260421-orch-harness-migration"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = "exact" ]
  [ "$(jq -r '.issue'  <<<"$output")" = "209" ]
  [ "$(jq -r '.slug'   <<<"$output")" = "20260421-orch-harness-migration" ]
}

@test "missing argument exits non-zero" {
  run "$RESOLVE"
  [ "$status" -ne 0 ]
}

@test "unreadable fixture exits non-zero with diagnostic" {
  ORCH_INVOKE_ISSUES_FIXTURE=/nonexistent/path.json run "$RESOLVE" "run issue 1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"fixture not readable"* ]]
}
