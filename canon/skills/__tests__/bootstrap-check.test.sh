#!/usr/bin/env bash
# Tests for canon/scripts/bootstrap-check.sh.
#
# The script prints one of three phase tokens to stdout:
#   - not-bootstrapped          (no dega-core.yaml at repo root)
#   - bootstrapped-no-strategy  (dega-core.yaml present, canon/strategies/ empty or absent)
#   - has-strategy              (dega-core.yaml present, canon/strategies/ contains at least one strategy)
#
# The script is invoked against the current working directory, so each test
# sets up a fixture tree under mktemp and cd's into it before running.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/canon/scripts/bootstrap-check.sh"

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
    echo "FAIL — bootstrap-check.sh does not exist at $SCRIPT"
    exit 1
  fi
  if [[ ! -x "$SCRIPT" ]]; then
    echo "FAIL — bootstrap-check.sh is not executable"
    exit 1
  fi
}

make_fixture() {
  mktemp -d
}

test_not_bootstrapped() {
  local fixture
  fixture="$(make_fixture)"
  # Empty dir — no dega-core.yaml.
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "not-bootstrapped" "$out" "empty repo → not-bootstrapped"
  rm -rf "$fixture"
}

test_not_bootstrapped_with_canon_dir_but_no_yaml() {
  local fixture
  fixture="$(make_fixture)"
  mkdir -p "$fixture/canon/strategies"
  echo "placeholder" >"$fixture/canon/strategies/foo.md"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "not-bootstrapped" "$out" "canon/ without dega-core.yaml → not-bootstrapped"
  rm -rf "$fixture"
}

test_bootstrapped_no_strategy_missing_dir() {
  local fixture
  fixture="$(make_fixture)"
  : >"$fixture/dega-core.yaml"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "bootstrapped-no-strategy" "$out" "yaml present, no canon/strategies dir → bootstrapped-no-strategy"
  rm -rf "$fixture"
}

test_bootstrapped_no_strategy_empty_dir() {
  local fixture
  fixture="$(make_fixture)"
  : >"$fixture/dega-core.yaml"
  mkdir -p "$fixture/canon/strategies"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "bootstrapped-no-strategy" "$out" "yaml present, empty canon/strategies → bootstrapped-no-strategy"
  rm -rf "$fixture"
}

test_has_strategy() {
  local fixture
  fixture="$(make_fixture)"
  : >"$fixture/dega-core.yaml"
  mkdir -p "$fixture/canon/strategies"
  echo "# my-strategy" >"$fixture/canon/strategies/my-strategy.md"
  local out
  out="$(cd "$fixture" && "$SCRIPT")"
  assert_eq "has-strategy" "$out" "yaml present, non-empty canon/strategies → has-strategy"
  rm -rf "$fixture"
}

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
  test_not_bootstrapped
  test_not_bootstrapped_with_canon_dir_but_no_yaml
  test_bootstrapped_no_strategy_missing_dir
  test_bootstrapped_no_strategy_empty_dir
  test_has_strategy
  test_exit_zero

  echo ""
  echo "Passed: $pass_count  Failed: $fail_count"
  if ((fail_count > 0)); then
    exit 1
  fi
}

main "$@"
