#!/usr/bin/env bash
# Tests for canon/scripts/canon-error.sh — the shared stderr/exit helper
# that enforces the canon script runtime contract (see canon/scripts/README.md).
#
# This suite runs without a test framework: each check increments a counter
# and prints a line; the script exits non-zero if any check fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/../canon-error.sh"

FAILED=0
PASSED=0

fail() {
  echo "FAIL: $*" >&2
  FAILED=$((FAILED + 1))
}

pass() {
  PASSED=$((PASSED + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass
  else
    fail "${label}: expected <${expected}>, got <${actual}>"
  fi
}

assert_matches() {
  local label="$1" pattern="$2" actual="$3"
  if [[ "$actual" =~ $pattern ]]; then
    pass
  else
    fail "${label}: expected match /${pattern}/, got <${actual}>"
  fi
}

# --- File presence -----------------------------------------------------------

if [[ ! -f "$HELPER" ]]; then
  fail "helper missing: ${HELPER} does not exist"
fi

if [[ ! -x "$HELPER" ]]; then
  fail "helper not executable: ${HELPER}"
fi

if ! grep -q '^#!/usr/bin/env bash' "$HELPER" 2>/dev/null; then
  fail "helper missing bash shebang"
fi

if ! grep -q 'set -euo pipefail' "$HELPER" 2>/dev/null; then
  fail "helper missing 'set -euo pipefail'"
fi

# If the helper is missing, bail before sourcing — nothing else will work.
if [[ ! -f "$HELPER" ]]; then
  echo "${FAILED} failure(s), ${PASSED} pass(es)" >&2
  exit 1
fi

# --- Behavior: run canon_error in a subshell and capture stdout/stderr/exit --

run_canon_error() {
  # Usage: run_canon_error <code> <short> [detail...]
  # Sets globals: RC_OUT, RC_ERR, RC_CODE
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  (
    # shellcheck disable=SC1090
    source "$HELPER"
    canon_error "$@"
  ) >"$tmp_out" 2>"$tmp_err"
  RC_CODE=$?
  RC_OUT="$(cat "$tmp_out")"
  RC_ERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# --- Taxonomy: exit codes 1, 2, 3 --------------------------------------------

run_canon_error 1 generic-failure
assert_eq "exit code 1" 1 "$RC_CODE"

run_canon_error 2 missing-tool
assert_eq "exit code 2" 2 "$RC_CODE"

run_canon_error 3 needs-login
assert_eq "exit code 3" 3 "$RC_CODE"

# --- Stderr line format: 'canon-error: <code>: <short>' ----------------------

run_canon_error 1 generic-failure
first_err="$(printf '%s\n' "$RC_ERR" | head -n 1)"
assert_eq "code 1 stderr line" "canon-error: 1: generic-failure" "$first_err"

run_canon_error 2 missing-tool
first_err="$(printf '%s\n' "$RC_ERR" | head -n 1)"
assert_eq "code 2 stderr line" "canon-error: 2: missing-tool" "$first_err"

run_canon_error 3 needs-login
first_err="$(printf '%s\n' "$RC_ERR" | head -n 1)"
assert_eq "code 3 stderr line" "canon-error: 3: needs-login" "$first_err"

# --- Nothing on stdout -------------------------------------------------------

run_canon_error 1 generic-failure
assert_eq "stdout is empty for code 1" "" "$RC_OUT"

run_canon_error 2 missing-tool "jq is required"
assert_eq "stdout is empty when detail given" "" "$RC_OUT"

# --- Detail lines appear on stderr after the prefix line ---------------------

run_canon_error 2 missing-tool "jq is required; install via 'brew install jq'"
first_err="$(printf '%s\n' "$RC_ERR" | head -n 1)"
rest_err="$(printf '%s\n' "$RC_ERR" | tail -n +2)"
assert_eq "detail: first line is prefix" "canon-error: 2: missing-tool" "$first_err"
assert_matches "detail: free text appears after prefix" "jq is required" "$rest_err"

# --- Multiple detail args are preserved on stderr ----------------------------

run_canon_error 3 needs-login "please run" "canon login"
assert_matches "multi-detail: 'please run' on stderr" "please run" "$RC_ERR"
assert_matches "multi-detail: 'canon login' on stderr" "canon login" "$RC_ERR"

# --- Summary -----------------------------------------------------------------

echo "${PASSED} pass(es), ${FAILED} failure(s)"
if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
