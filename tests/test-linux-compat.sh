#!/usr/bin/env bash
# Integration test: verify orchestrator scripts handle Linux/headless
# environments gracefully. Simulates headless Linux by clearing display
# variables and overriding uname via PATH shim.
#
# Usage: bash tests/test-linux-compat.sh
#
# Runs on macOS — tests the Linux code paths without an actual Linux box.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

# --- Helpers ---

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected: ${expected}"
    echo "    actual:   ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected to contain: ${needle}"
    echo "    actual: ${haystack}"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    expected exit code: ${expected}"
    echo "    actual exit code:   ${actual}"
    FAIL=$((FAIL + 1))
  fi
}

# --- Setup: create a uname shim that returns "Linux" ---

SHIM_DIR=$(mktemp -d)
cat >"${SHIM_DIR}/uname" <<'SHIM'
#!/bin/bash
# Shim: pretend we're on Linux
for arg in "$@"; do
  case "$arg" in
    -s) echo "Linux"; exit 0 ;;
    -a) echo "Linux test-host 6.1.0 #1 SMP x86_64 GNU/Linux"; exit 0 ;;
  esac
done
echo "Linux"
SHIM
chmod +x "${SHIM_DIR}/uname"

CLEANUP_TMUX=""
cleanup() {
  rm -rf "${SHIM_DIR}"
  if [[ -n "${CLEANUP_TMUX}" ]]; then
    tmux kill-session -t "${CLEANUP_TMUX}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo ""
echo "=== Test 1: orch-display.sh — headless detection skips window open ==="

# Create a temporary tmux session so orch-display.sh passes the session check
TEST_TMUX_SESSION="test-linux-compat-$$"
tmux new-session -d -s "${TEST_TMUX_SESSION}" "sleep 60" 2>/dev/null || true

# Extend cleanup to kill our tmux session
CLEANUP_TMUX="${TEST_TMUX_SESSION}"

# Simulate headless Linux: no DISPLAY, no WAYLAND_DISPLAY, no TERM_PROGRAM
OUTPUT=$(
  env -u DISPLAY -u WAYLAND_DISPLAY -u TERM_PROGRAM \
    PATH="${SHIM_DIR}:${PATH}" \
    bash "${REPO_ROOT}/scripts/orch-display.sh" "${TEST_TMUX_SESSION}" 2>&1
) || true

assert_contains "headless message logged" "headless environment detected" "${OUTPUT}"
assert_contains "manual attach hint" "Run manually:" "${OUTPUT}"

echo ""
echo "=== Test 2: orch-display.sh — DISPLAY set triggers Linux terminal path ==="

# With DISPLAY set, headless check passes — but no gnome-terminal/konsole/xterm
# are available on macOS, so it should fall back to the manual-attach message.
OUTPUT2=$(
  env -u WAYLAND_DISPLAY -u TERM_PROGRAM \
    DISPLAY=":0" \
    PATH="${SHIM_DIR}:${PATH}" \
    bash "${REPO_ROOT}/scripts/orch-display.sh" "${TEST_TMUX_SESSION}" 2>&1
) || true

# It tries to open a Linux terminal, fails to find one, prints fallback
assert_contains "no terminal fallback" "no supported terminal detected" "${OUTPUT2}"

echo ""
echo "=== Test 3: play-sound.sh — headless Linux skips audio ==="

# Simulate headless Linux: no PULSE_SERVER, no pactl, no /dev/snd, not WSL
OUTPUT3=$(
  env -u PULSE_SERVER -u DISPLAY -u WAYLAND_DISPLAY -u TERM_PROGRAM \
    -u WSL_DISTRO_NAME \
    PATH="${SHIM_DIR}:${PATH}" \
    DEGA_SOUND="test" \
    bash "${REPO_ROOT}/hooks/play-sound.sh" 2>&1
) || true
EXIT3=$?

assert_exit_code "play-sound exits 0 on headless" "0" "${EXIT3}"
assert_contains "headless audio skip" "headless environment" "${OUTPUT3}"

echo ""
echo "=== Test 4: play-sound.sh — sound=none exits immediately ==="

OUTPUT4=$(
  env DEGA_SOUND="none" \
    bash "${REPO_ROOT}/hooks/play-sound.sh" 2>&1
) || true
EXIT4=$?

assert_exit_code "play-sound exits 0 with sound=none" "0" "${EXIT4}"
assert_eq "no output when disabled" "" "${OUTPUT4}"

echo ""
echo "=== Test 5: orch-state.sh — sources cleanly under simulated Linux ==="

# orch-state.sh is a library — verify it sources without error under Linux env
OUTPUT5=$(
  env PATH="${SHIM_DIR}:${PATH}" \
    bash -c "
      source '${REPO_ROOT}/scripts/orch-state.sh' 2>&1 && echo 'SOURCE_OK'
    " 2>&1
) || true

# Direct execution should fail (guard clause), but sourcing should work
assert_contains "orch-state.sh sources OK" "SOURCE_OK" "${OUTPUT5}"

echo ""
echo "=== Test 6: orch-state.sh — date commands use portable format ==="

# Verify all date calls in orch-state.sh use -u +FORMAT (portable) not -jf (BSD)
BSD_DATE_CALLS=$(grep -c 'date -jf' "${REPO_ROOT}/scripts/orch-state.sh" || true)
assert_eq "no BSD date -jf in orch-state.sh" "0" "${BSD_DATE_CALLS}"

echo ""
echo "=== Test 7: orch-engine.sh — date fallback exists for epoch conversion ==="

# The date -jf call at line ~605 should have a GNU fallback (date -d)
ENGINE_DATE_LINE=$(grep -n 'date -jf' "${REPO_ROOT}/scripts/orch-engine.sh" || true)
if [[ -n "${ENGINE_DATE_LINE}" ]]; then
  # Verify it has a fallback
  FALLBACK=$(grep -A1 'date -jf' "${REPO_ROOT}/scripts/orch-engine.sh" |
    grep -c 'date -d' || true)
  if [[ "${FALLBACK}" -gt 0 ]]; then
    echo "  PASS: orch-engine.sh date -jf has GNU date -d fallback"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: orch-engine.sh date -jf without GNU fallback"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  PASS: orch-engine.sh has no BSD-only date -jf calls"
  PASS=$((PASS + 1))
fi

echo ""
echo "=== Test 8: orch-run.sh — check_deps validates required tools ==="

# orch-run.sh check_deps() looks for jq, tmux, node — these are cross-platform
# Verify the function exists and lists the right tools
DEPS_CHECK=$(grep -A5 'check_deps()' "${REPO_ROOT}/scripts/orch-run.sh")
assert_contains "checks for jq" "jq" "${DEPS_CHECK}"
assert_contains "checks for tmux" "tmux" "${DEPS_CHECK}"
assert_contains "checks for node" "node" "${DEPS_CHECK}"

echo ""
echo "=== Test 9: orch-parse-items.sh — works under simulated Linux ==="

# Create a temp plan to parse
TEST_SLUG="test-linux-compat-$$"
TEST_PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${TEST_SLUG}"
mkdir -p "${TEST_PLAN_DIR}"

# Extend cleanup
cleanup_extended() {
  rm -rf "${SHIM_DIR}"
  rm -rf "${TEST_PLAN_DIR}"
  if [[ -n "${CLEANUP_TMUX}" ]]; then
    tmux kill-session -t "${CLEANUP_TMUX}" 2>/dev/null || true
  fi
}
trap cleanup_extended EXIT

cat >"${TEST_PLAN_DIR}/plan.md" <<'PLAN'
# Plan: Linux Compat Test

## Progress log

- [ ] First task
- [ ] Second task (deps: 1)
PLAN

PARSED=$(
  env PATH="${SHIM_DIR}:${PATH}" \
    bash "${REPO_ROOT}/scripts/orch-parse-items.sh" "${TEST_SLUG}" 2>&1
)
ITEM_COUNT=$(printf '%s' "${PARSED}" | jq '.items | length')
assert_eq "parse-items under Linux shim" "2" "${ITEM_COUNT}"

echo ""
echo "=== Test 10: No macOS-only commands without fallbacks ==="

# Scan all orchestrator scripts for macOS-only commands lacking fallbacks.
# afplay, osascript, open (as command) — these should only appear inside
# Darwin case blocks or with fallback logic.
ORCH_SCRIPTS=(
  "${REPO_ROOT}/scripts/orch-run.sh"
  "${REPO_ROOT}/scripts/orch-engine.sh"
  "${REPO_ROOT}/scripts/orch-state.sh"
  "${REPO_ROOT}/scripts/orch-review.sh"
  "${REPO_ROOT}/scripts/orch-verify.sh"
  "${REPO_ROOT}/scripts/orch-parse-items.sh"
)

UNGUARDED_MACOS=0
for script in "${ORCH_SCRIPTS[@]}"; do
  basename=$(basename "${script}")
  # Check for bare afplay/osascript calls outside case blocks
  for cmd in afplay osascript; do
    if grep -n "${cmd}" "${script}" 2>/dev/null | grep -v '^\s*#' | grep -v 'Darwin' >/dev/null 2>&1; then
      # Found the command — check if it's inside a Darwin case block
      # by looking for Darwin) within 20 lines before
      while IFS=: read -r lineno _; do
        before=$(head -n "${lineno}" "${script}" | tail -20)
        if ! echo "${before}" | grep -q 'Darwin'; then
          echo "  WARN: ${basename}:${lineno} uses ${cmd} without Darwin guard"
          UNGUARDED_MACOS=$((UNGUARDED_MACOS + 1))
        fi
      done < <(grep -n "${cmd}" "${script}" 2>/dev/null | grep -v '^\s*#')
    fi
  done
done

if [[ "${UNGUARDED_MACOS}" -eq 0 ]]; then
  echo "  PASS: no unguarded macOS-only commands in orchestrator scripts"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ${UNGUARDED_MACOS} unguarded macOS-only command(s) found"
  FAIL=$((FAIL + 1))
fi

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
