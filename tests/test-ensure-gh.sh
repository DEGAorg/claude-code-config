#!/usr/bin/env bash
# Unit tests for scripts/ensure-gh.sh
# Run from repo root: bash tests/test-ensure-gh.sh
set -euo pipefail

SCRIPT="scripts/ensure-gh.sh"
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

printf 'ensure-gh\n'

# --- Test: gh already in PATH succeeds silently ---

exit_code=0
output="$(bash "${SCRIPT}" 2>&1)" || exit_code=$?
check gh-in-path \
	"succeeds when gh is already in PATH" \
	0 "${exit_code}"

# --- Test: ensure_gh function is sourceable ---

exit_code=0
output="$(bash -c "source ${SCRIPT}; ensure_gh" 2>&1)" || exit_code=$?
check source-function \
	"ensure_gh function works when sourced" \
	0 "${exit_code}"

# --- Test: missing gh and brew produces helpful error ---
# Create a fake PATH with neither gh nor brew

FAKE_DIR="$(mktemp -d)"
trap 'rm -rf "${FAKE_DIR}"' EXIT

# Populate fake dir with minimal required commands
for cmd in bash env uname printf echo cat; do
	real="$(command -v "${cmd}" 2>/dev/null || true)"
	if [[ -n "${real}" ]]; then
		ln -sf "${real}" "${FAKE_DIR}/${cmd}"
	fi
done

exit_code=0
output="$(PATH="${FAKE_DIR}" bash "${SCRIPT}" 2>&1)" || exit_code=$?
check no-gh-no-brew \
	"fails when gh and brew both missing" \
	1 "${exit_code}"

check_contains no-gh-error-msg \
	"shows install instructions when gh missing" \
	"gh CLI is not installed" "${output}"

# --- Test: platform-specific instructions ---
# The error output should mention at least one install URL

check_contains no-gh-has-url \
	"shows a URL in install instructions" \
	"https://" "${output}"

# --- Test: script is shellcheck clean ---

if command -v shellcheck &>/dev/null; then
	exit_code=0
	shellcheck "${SCRIPT}" >/dev/null 2>&1 || exit_code=$?
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
