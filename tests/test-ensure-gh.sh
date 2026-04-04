#!/usr/bin/env bash
# Unit tests for provider CLI availability (provider_ensure_cli).
# Tests through the provider abstraction layer rather than scripts/ensure-gh.sh
# directly.
# Run from repo root: bash tests/test-ensure-gh.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

printf 'provider-ensure-cli\n'

# --- Test: provider_ensure_cli succeeds when gh is in PATH ---

exit_code=0
output="$(cd "${REPO_ROOT}" && bash -c \
	"source '${REPO_ROOT}/scripts/providers/provider.sh'; provider_ensure_cli" \
	2>&1)" || exit_code=$?
check gh-in-path \
	"provider_ensure_cli succeeds when gh is already in PATH" \
	0 "${exit_code}"

# --- Test: provider_auth_check succeeds when gh is authenticated ---

exit_code=0
output="$(cd "${REPO_ROOT}" && bash -c \
	"source '${REPO_ROOT}/scripts/providers/provider.sh'; provider_auth_check" \
	2>&1)" || exit_code=$?
check auth-check \
	"provider_auth_check succeeds when gh is authenticated" \
	0 "${exit_code}"

# --- Test: missing gh and brew produces helpful error ---
# Create a fake PATH with neither gh nor brew, and a temp dir with dega-core.yaml

FAKE_DIR="$(mktemp -d)"
trap 'rm -rf "${FAKE_DIR}"' EXIT

# Populate fake dir with minimal required commands
for cmd in bash env uname printf echo cat jq grep sed head tr dirname basename cd pwd; do
	real="$(command -v "${cmd}" 2>/dev/null || true)"
	if [[ -n "${real}" ]]; then
		ln -sf "${real}" "${FAKE_DIR}/${cmd}"
	fi
done

# Create dega-core.yaml for provider.sh resolution
cat >"${FAKE_DIR}/dega-core.yaml" <<'YAML'
provider: github
YAML

exit_code=0
output="$(cd "${FAKE_DIR}" && PATH="${FAKE_DIR}" bash -c \
	"source '${REPO_ROOT}/scripts/providers/provider.sh'; provider_ensure_cli" \
	2>&1)" || exit_code=$?
check no-gh-no-brew \
	"provider_ensure_cli fails when gh and brew both missing" \
	1 "${exit_code}"

check_contains no-gh-error-msg \
	"shows install instructions when gh missing" \
	"gh CLI is not installed" "${output}"

# --- Test: platform-specific instructions ---
# The error output should mention at least one install URL

check_contains no-gh-has-url \
	"shows a URL in install instructions" \
	"https://" "${output}"

# --- Test: provider scripts pass shellcheck ---

if command -v shellcheck &>/dev/null; then
	for script in providers/provider.sh providers/github.sh; do
		exit_code=0
		shellcheck -x -e SC1091 "${REPO_ROOT}/scripts/${script}" \
			>/dev/null 2>&1 || exit_code=$?
		check "shellcheck-$(basename "${script}" .sh)" \
			"scripts/${script} passes shellcheck" \
			0 "${exit_code}"
	done
else
	printf '  skip shellcheck: not installed\n'
fi

# --- Test: provider scripts pass shfmt ---

if command -v shfmt &>/dev/null; then
	for script in providers/provider.sh providers/github.sh; do
		exit_code=0
		shfmt -d "${REPO_ROOT}/scripts/${script}" \
			>/dev/null 2>&1 || exit_code=$?
		check "shfmt-$(basename "${script}" .sh)" \
			"scripts/${script} passes shfmt" \
			0 "${exit_code}"
	done
else
	printf '  skip shfmt: not installed\n'
fi

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
