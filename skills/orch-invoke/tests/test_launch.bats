#!/usr/bin/env bats
#
# Tests for skills/orch-invoke/launch.sh.
#
# Run with:  bats skills/orch-invoke/tests/test_launch.bats
#
# Each test builds an isolated ORCH_ROOT tree under BATS_TEST_TMPDIR so the
# launcher exercises its real plan-lookup, deps-validation, master.json
# already-running detection, and events.jsonl polling paths without touching
# the working repo. The orch-run binary is stubbed via ORCH_RUN_CMD so no
# tmux/background engine is actually started.

setup() {
  SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LAUNCH="$SKILL_DIR/launch.sh"

  ROOT="$BATS_TEST_TMPDIR/root"
  SLUG="20260422-example-plan"
  ISSUE=4242

  PLAN_DIR="$ROOT/docs/exec-plans/active/$SLUG"
  STATE_DIR="$ROOT/.orchestrator/plans/$SLUG"
  EVENTS_PATH="$STATE_DIR/events.jsonl"
  PID_FILE="$STATE_DIR/pids/engine-$SLUG.pid"
  MASTER="$ROOT/.orchestrator/master.json"

  mkdir -p "$PLAN_DIR" "$STATE_DIR/pids" "$ROOT/.orchestrator"

  export ORCH_ROOT="$ROOT"
  export ORCH_INVOKE_SKIP_GH=1
  export ORCH_INVOKE_TIMEOUT=3
}

write_plan_with_deps() {
  cat >"$PLAN_DIR/plan.md" <<EOF
# Example plan

## Progress log

- [ ] First item
- [ ] Second item (deps: 1)
- [ ] Third item (deps: 2)
EOF
}

write_plan_missing_deps() {
  cat >"$PLAN_DIR/plan.md" <<EOF
# Example plan

## Progress log

- [ ] First item
- [ ] Second item
- [ ] Third item (deps: 2)
EOF
}

# Build a stub orch-run.sh and set ORCH_RUN_CMD to point at it.
# The stub writes a plan_start event and a PID file to simulate a successful
# background launch.
stub_orch_run() {
  STUB="$BATS_TEST_TMPDIR/orch-run-stub.sh"
  cat >"$STUB" <<EOF
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$STATE_DIR/pids"
printf '%s\n' '{"evt":"plan_start","slug":"$SLUG","issue":$ISSUE}' >>"$EVENTS_PATH"
echo 98765 >"$PID_FILE"
exit 0
EOF
  chmod +x "$STUB"
  export ORCH_RUN_CMD="$STUB"
}

@test "missing-deps annotation on a Progress-log item is refused" {
  write_plan_missing_deps
  stub_orch_run

  run "$LAUNCH" --issue "$ISSUE" --slug "$SLUG"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.ok' <<<"$output")" = "false" ]
  [ "$(jq -r '.error' <<<"$output")" = "missing_deps" ]
  # The stub must not have been invoked.
  [ ! -f "$EVENTS_PATH" ]
}

@test "already-running plan in master.json is refused with pid carried through" {
  write_plan_with_deps
  stub_orch_run

  cat >"$MASTER" <<EOF
{
  "plans": [
    {
      "slug": "$SLUG",
      "status": "running",
      "pid": 12345,
      "eventsPath": ".orchestrator/plans/$SLUG/events.jsonl",
      "statePath": ".orchestrator/plans/$SLUG/state.json"
    }
  ]
}
EOF

  run "$LAUNCH" --issue "$ISSUE" --slug "$SLUG"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.ok' <<<"$output")" = "false" ]
  [ "$(jq -r '.error' <<<"$output")" = "already_running" ]
  [ "$(jq -r '.pid' <<<"$output")" = "12345" ]
  [ "$(jq -r '.events_path' <<<"$output")" = ".orchestrator/plans/$SLUG/events.jsonl" ]
  # Stub must not have been invoked.
  [ ! -f "$EVENTS_PATH" ]
}

@test "completed plan in master.json does not block a new launch" {
  write_plan_with_deps
  stub_orch_run

  cat >"$MASTER" <<EOF
{
  "plans": [
    { "slug": "$SLUG", "status": "completed", "pid": 1 }
  ]
}
EOF

  run "$LAUNCH" --issue "$ISSUE" --slug "$SLUG"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ok' <<<"$output")" = "true" ]
}

@test "happy-path: stubbed orch-run emits plan_start and launcher returns ok" {
  write_plan_with_deps
  stub_orch_run

  run "$LAUNCH" --issue "$ISSUE" --slug "$SLUG"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.ok'          <<<"$output")" = "true" ]
  [ "$(jq -r '.slug'        <<<"$output")" = "$SLUG" ]
  [ "$(jq -r '.issue'       <<<"$output")" = "$ISSUE" ]
  [ "$(jq -r '.pid'         <<<"$output")" = "98765" ]
  [ "$(jq -r '.events_path' <<<"$output")" = ".orchestrator/plans/$SLUG/events.jsonl" ]
  [ "$(jq -r '.state_path'  <<<"$output")" = ".orchestrator/plans/$SLUG/state.json" ]
}

@test "launch_timeout when stubbed orch-run never writes plan_start" {
  write_plan_with_deps
  SILENT_STUB="$BATS_TEST_TMPDIR/orch-run-silent.sh"
  cat >"$SILENT_STUB" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$SILENT_STUB"
  export ORCH_RUN_CMD="$SILENT_STUB"
  export ORCH_INVOKE_TIMEOUT=2

  run "$LAUNCH" --issue "$ISSUE" --slug "$SLUG"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.error' <<<"$output")" = "launch_timeout" ]
}

@test "plan_not_found when slug directory is missing" {
  run "$LAUNCH" --issue "$ISSUE" --slug "does-not-exist-slug"
  [ "$status" -ne 0 ]
  [ "$(jq -r '.error' <<<"$output")" = "plan_not_found" ]
}
