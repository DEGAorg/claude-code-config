#!/usr/bin/env bash
# Unit tests for scripts/gh-plan-sync.sh
# Tests argument parsing, validation, and comment formatting.
# Does NOT call the real gh CLI — tests that would require a live
# GitHub API are limited to validation/error-path checks.
# Run from repo root: bash tests/test-gh-plan-sync.sh
set -euo pipefail

SCRIPT="scripts/gh-plan-sync.sh"
PASS=0
FAIL=0

check() {
	local id="$1"
	local description="$2"
	local expected="$3"
	local actual="$4"
	if [[ "${actual}" -eq "${expected}" ]]; then
		printf '  ok  %s: %s\n' "${id}" "${description}"
		PASS=$((PASS + 1))
	else
		printf '  FAIL %s: %s (expected exit %d, got %s)\n' \
			"${id}" "${description}" "${expected}" "${actual}"
		FAIL=$((FAIL + 1))
	fi
}

check_contains() {
	local id="$1"
	local description="$2"
	local pattern="$3"
	local output="$4"
	if [[ "${output}" == *"${pattern}"* ]]; then
		printf '  ok  %s: %s\n' "${id}" "${description}"
		PASS=$((PASS + 1))
	else
		printf '  FAIL %s: %s (expected output to contain "%s")\n' \
			"${id}" "${description}" "${pattern}"
		FAIL=$((FAIL + 1))
	fi
}

printf 'gh-plan-sync\n'

# --- Validation tests (these fail before any gh API calls) ---

# Test: missing event type
exit_code=0
output="$(bash "${SCRIPT}" 2>&1)" || exit_code=$?
check no-event \
	"fails with no arguments" \
	1 "${exit_code}"
check_contains no-event-msg \
	"error mentions event type" \
	"event type required" "${output}"

# Test: missing slug
exit_code=0
output="$(bash "${SCRIPT}" start 2>&1)" || exit_code=$?
check no-slug \
	"fails with missing slug" \
	1 "${exit_code}"
check_contains no-slug-msg \
	"error mentions slug" \
	"slug required" "${output}"

# Test: missing --issue
exit_code=0
output="$(bash "${SCRIPT}" start my-plan 2>&1)" || exit_code=$?
check no-issue \
	"fails with missing --issue" \
	1 "${exit_code}"
check_contains no-issue-msg \
	"error mentions --issue" \
	"--issue" "${output}"

# Test: unknown event type
exit_code=0
output="$(bash "${SCRIPT}" bogus my-plan --issue 1 2>&1)" || exit_code=$?
check bad-event \
	"fails with unknown event type" \
	1 "${exit_code}"
check_contains bad-event-msg \
	"error mentions unknown event" \
	"unknown event type" "${output}"

# Test: unknown option
exit_code=0
output="$(bash "${SCRIPT}" start my-plan --issue 1 --bogus 2>&1)" || exit_code=$?
check bad-option \
	"fails with unknown option" \
	1 "${exit_code}"
check_contains bad-option-msg \
	"error mentions unknown option" \
	"unknown option" "${output}"

# Test: valid events are accepted (start, review, ship, revise)
# These will fail at the auth check (not at validation), proving they
# pass argument parsing. Auth failure exits with code 1.
for event in start review ship revise; do
	exit_code=0
	# Use a fake PATH that has gh (stub returning auth failure) but blocks real API
	STUB_DIR="$(mktemp -d)"
	cat >"${STUB_DIR}/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: auth status fails, everything else succeeds
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
STUB
	chmod +x "${STUB_DIR}/gh"

	output="$(PATH="${STUB_DIR}:${PATH}" bash "${SCRIPT}" "${event}" my-plan \
		--issue 42 2>&1)" || exit_code=$?
	rm -rf "${STUB_DIR}"

	check "valid-event-${event}" \
		"${event} event passes validation (fails at auth)" \
		1 "${exit_code}"
	check_contains "valid-event-${event}-auth" \
		"${event} event fails with auth error, not validation" \
		"not authenticated" "${output}"
done

# --- Test: script is shellcheck clean ---

if command -v shellcheck &>/dev/null; then
	exit_code=0
	shellcheck -x -e SC1091 "${SCRIPT}" >/dev/null 2>&1 || exit_code=$?
	check shellcheck \
		"passes shellcheck" \
		0 "${exit_code}"
else
	printf '  skip shellcheck: not installed\n'
fi

# --- Test: script is shfmt clean ---

if command -v shfmt &>/dev/null; then
	exit_code=0
	shfmt -d "${SCRIPT}" >/dev/null 2>&1 || exit_code=$?
	check shfmt \
		"passes shfmt" \
		0 "${exit_code}"
else
	printf '  skip shfmt: not installed\n'
fi

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
