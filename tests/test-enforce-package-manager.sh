#!/usr/bin/env bash
# Unit tests for hooks/enforce-package-manager.sh
# Run from repo root: bash tests/test-enforce-package-manager.sh
set -euo pipefail

HOOK="hooks/enforce-package-manager.sh"
PASS=0
FAIL=0

PNPM_DIR=$(mktemp -d)
touch "${PNPM_DIR}/pnpm-lock.yaml"
PLAIN_DIR=$(mktemp -d)
trap 'rm -rf "${PNPM_DIR}" "${PLAIN_DIR}"' EXIT

run_hook() {
  local json="$1"
  local project_dir="$2"
  local exit_code=0
  printf '%s\n' "${json}" \
    | CLAUDE_PROJECT_DIR="${project_dir}" bash "${HOOK}" >/dev/null 2>&1 \
    || exit_code=$?
  printf '%d' "${exit_code}"
}

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

printf 'enforce-package-manager\n'

check empty-cmd \
  "empty command is a no-op" \
  0 "$(run_hook '{"tool_input":{}}' "${PLAIN_DIR}")"

check npm-no-pnpm \
  "npm in non-pnpm project is a no-op" \
  0 "$(run_hook '{"tool_input":{"command":"npm install foo"}}' "${PLAIN_DIR}")"

check pnpm-pass \
  "pnpm in pnpm project passes" \
  0 "$(run_hook '{"tool_input":{"command":"pnpm install foo"}}' "${PNPM_DIR}")"

check npm-blocked \
  "npm install in pnpm project is blocked" \
  2 "$(run_hook '{"tool_input":{"command":"npm install foo"}}' "${PNPM_DIR}")"

check npm-ci-blocked \
  "npm ci in pnpm project is blocked" \
  2 "$(run_hook '{"tool_input":{"command":"npm ci"}}' "${PNPM_DIR}")"

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
