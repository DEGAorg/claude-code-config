#!/usr/bin/env bash
# Tests for canon/scripts/phase-detect.sh.
#
# The script extends bootstrap-check.sh with a fourth phase, "running",
# and prints one of four phase tokens to stdout:
#   - not-bootstrapped          (no dega-core.yaml at cwd)
#   - bootstrapped-no-strategy  (dega-core.yaml present, canon/strategies/ empty or absent)
#   - has-strategy              (dega-core.yaml + non-empty canon/strategies/, no active run)
#   - running                   (has-strategy AND .canon/state.json shows an active run,
#                                i.e. phase != "idle" AND status != "idle")
#
# The running marker is .canon/state.json's "phase" and "status" fields,
# per the plan's decision log. Each test sets up a fixture tree under
# mktemp and cd's into it before running the script.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/canon/scripts/phase-detect.sh"

fail_count=0
pass_count=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass_count=$((pass_count + 1))
    echo "ok  — $label"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL — $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

require_script() {
  if [[ ! -f "$SCRIPT" ]]; then
    echo "FAIL — phase-detect.sh does not exist at $SCRIPT"
    exit 1
  fi
  if [[ ! -x "$SCRIPT" ]]; then
    echo "FAIL — phase-detect.sh is not executable"
    exit 1
  fi
}

make_fixture() {
  mktemp -d
}

write_state() {
  # write_state <fixture-dir> <phase> <status>
  local fixture="$1"
  local phase="$2"
  local status="$3"
  mkdir -p "$fixture/.canon"
  printf '{"phase":"%s","status":"%s","startedAt":"t","updatedAt":"t","logs":[],"error":null,"metrics":{}}\n' \
    "$phase" "$status" >"$fixture/.canon/state.json"
}

seed_bootstrapped() {
  # Adds dega-core.yaml so the repo is at least bootstrapped.
  local fixture="$1"
  : >"$fixture/dega-core.yaml"
}

seed_strategy() {
  # Adds a strategy so the repo is at least has-strategy.
  local fixture="$1"
  mkdir -p "$fixture/canon/strategies"
  echo "# my-strategy" >"$fixture/canon/strategies/my-strategy.md"
}

# ---- Phase 1: not-bootstrapped ----

test_not_bootstrapped_empty() {
  local fixture
  fixture="$(make_fixture)"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "not-bootstrapped" "$out" "empty dir → not-bootstrapped"
  rm -rf "$fixture"
}

test_not_bootstrapped_ignores_state_json() {
  # Even if a stale .canon/state.json exists, lack of dega-core.yaml wins.
  local fixture
  fixture="$(make_fixture)"
  write_state "$fixture" "develop" "running"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "not-bootstrapped" "$out" "state.json without dega-core.yaml → not-bootstrapped"
  rm -rf "$fixture"
}

# ---- Phase 2: bootstrapped-no-strategy ----

test_bootstrapped_no_strategy_missing_dir() {
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "bootstrapped-no-strategy" "$out" "yaml, no canon/strategies → bootstrapped-no-strategy"
  rm -rf "$fixture"
}

test_bootstrapped_no_strategy_empty_dir() {
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  mkdir -p "$fixture/canon/strategies"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "bootstrapped-no-strategy" "$out" "yaml, empty canon/strategies → bootstrapped-no-strategy"
  rm -rf "$fixture"
}

# ---- Phase 3: has-strategy (idle) ----

test_has_strategy_no_state_json() {
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  seed_strategy "$fixture"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "has-strategy" "$out" "strategy present, no state.json → has-strategy"
  rm -rf "$fixture"
}

test_has_strategy_state_idle_idle() {
  # phase=idle AND status=idle → not running.
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  seed_strategy "$fixture"
  write_state "$fixture" "idle" "idle"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "has-strategy" "$out" "state phase=idle status=idle → has-strategy"
  rm -rf "$fixture"
}

test_has_strategy_state_init_idle() {
  # canon.sh initial write: phase=init, status=idle — waiting, not running.
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  seed_strategy "$fixture"
  write_state "$fixture" "init" "idle"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "has-strategy" "$out" "state phase=init status=idle → has-strategy (not yet running)"
  rm -rf "$fixture"
}

# ---- Phase 4: running ----

test_running_develop() {
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  seed_strategy "$fixture"
  write_state "$fixture" "develop" "running"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "running" "$out" "state phase=develop status=running → running"
  rm -rf "$fixture"
}

test_running_discover() {
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  seed_strategy "$fixture"
  write_state "$fixture" "discover" "running"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "running" "$out" "state phase=discover status=running → running"
  rm -rf "$fixture"
}

test_running_requires_strategy() {
  # Without a strategy, even an active state.json should not report running —
  # the prior phases are a prerequisite.
  local fixture
  fixture="$(make_fixture)"
  seed_bootstrapped "$fixture"
  write_state "$fixture" "develop" "running"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "bootstrapped-no-strategy" "$out" "state.json without strategy → bootstrapped-no-strategy (running requires prior phases)"
  rm -rf "$fixture"
}

# ---- exit code ----

test_exit_zero() {
  local fixture
  fixture="$(make_fixture)"
  set +e
  (cd "$fixture" && "$SCRIPT") >/dev/null
  local rc=$?
  set -e
  assert_eq "0" "$rc" "exits 0 even when not bootstrapped"
  rm -rf "$fixture"
}

main() {
  require_script
  test_not_bootstrapped_empty
  test_not_bootstrapped_ignores_state_json
  test_bootstrapped_no_strategy_missing_dir
  test_bootstrapped_no_strategy_empty_dir
  test_has_strategy_no_state_json
  test_has_strategy_state_idle_idle
  test_has_strategy_state_init_idle
  test_running_develop
  test_running_discover
  test_running_requires_strategy
  test_exit_zero

  echo ""
  echo "Passed: $pass_count  Failed: $fail_count"
  if ((fail_count > 0)); then
    exit 1
  fi
}

main "$@"
