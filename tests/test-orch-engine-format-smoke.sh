#!/usr/bin/env bash
# End-to-end smoke for the FORMATTING phase wired into orch-engine.sh.
#
# Two modes, gated by CANON_E2E_LIVE:
#
#   CANON_E2E_LIVE != "1" (cheap, CI default):
#     Source orch-format.sh and orch-state.sh in library mode, assert
#     that the FORMATTING helpers (orch_plan_formatting_dir,
#     orch_init_formatting_state, orch_format_aggregate,
#     orch_format_changed_sh, orch_format_stage_inputs,
#     orch_format_read_verdict) exist and behave correctly against a
#     temp state file. Also asserts that orch-engine.sh references the
#     orch-format.sh runner and the formatting phase wiring landed.
#     No tmux, no agent — fast enough for CI.
#
#   CANON_E2E_LIVE == "1" (local dev):
#     Build a synthetic 1-item plan whose only commit lands a
#     deliberately misformatted shell file, spawn the real engine via
#     scripts/orch-run.sh, and assert that:
#       - the engine reaches state.status="completed"
#       - one `chore: shfmt + shellcheck pass` commit lands on the
#         orch branch
#       - the offending file is shfmt-clean after the run
#     This invokes a real agent and costs real budget; gated off by
#     default.
#
# Usage:
#   bash tests/test-orch-engine-format-smoke.sh         # cheap path
#   CANON_E2E_LIVE=1 bash tests/test-orch-engine-format-smoke.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

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
  local label="$1" haystack="$2" needle="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    echo "  PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label}"
    echo "    needle: ${needle}"
    echo "    haystack: ${haystack}"
    FAIL=$((FAIL + 1))
  fi
}

# === Engine wiring check (always runs) ============================
echo "=== Wiring check: orch-engine.sh references orch-format.sh ==="
engine="${REPO_ROOT}/scripts/orch-engine.sh"
if [[ ! -f "${engine}" ]]; then
  echo "  FAIL: scripts/orch-engine.sh not found"
  exit 1
fi
engine_text=$(cat "${engine}")
assert_contains "orch-engine references orch-format.sh" \
  "${engine_text}" "orch-format.sh"
assert_contains "orch-engine wires the format phase" \
  "${engine_text}" "Per-plan FORMATTING phase"
assert_contains "orch-engine handles FORMATTING_FAILED" \
  "${engine_text}" "FORMATTING_FAILED"

# === Library-mode helper smoke (always runs) ======================
echo ""
echo "=== Library-mode helpers ==="

TEST_TMP="/tmp/orch-fmt-smoke-$$"
mkdir -p "${TEST_TMP}"
trap 'rm -rf "${TEST_TMP}"' EXIT

SLUG="smoke-helpers"
ORCH_STATE_DIR="${TEST_TMP}/.orchestrator"
export ORCH_STATE_DIR
ORCH_REPO_ROOT="${TEST_TMP}"
export ORCH_REPO_ROOT

# Source the runner + state lib in library mode (BASH_SOURCE != $0).
# shellcheck source=../scripts/orch-state.sh disable=SC1091
source "${REPO_ROOT}/scripts/orch-state.sh"
# shellcheck source=../scripts/orch-format.sh disable=SC1091
source "${REPO_ROOT}/scripts/orch-format.sh"

# orch_plan_formatting_dir resolves under the plans tree.
expected_fmt_dir="${ORCH_STATE_DIR}/plans/${SLUG}/formatting"
actual_fmt_dir="$(orch_plan_formatting_dir "${SLUG}")"
assert_eq "orch_plan_formatting_dir resolves" \
  "${expected_fmt_dir}" "${actual_fmt_dir}"

# Build a minimal state.json then init formatting state.
mkdir -p "${ORCH_STATE_DIR}/plans/${SLUG}"
cat >"${ORCH_STATE_DIR}/plans/${SLUG}/state.json" <<'EOF'
{
  "version": 1,
  "plan": "smoke-helpers",
  "items": [],
  "finalReview": {"status": "done", "result": "SHIP", "reworkItems": []},
  "documentation": {"status": "done", "result": "SHIP", "reworkItems": []}
}
EOF

orch_init_formatting_state "${SLUG}"

fmt_status=$(jq -r '.formatting.status' \
  "${ORCH_STATE_DIR}/plans/${SLUG}/state.json")
assert_eq "orch_init_formatting_state sets status=pending" \
  "pending" "${fmt_status}"

# Aggregate PASS → SHIP.
result=$(orch_format_aggregate "${SLUG}" PASS)
assert_eq "orch_format_aggregate PASS returns SHIP" "SHIP" "${result}"
fmt_result=$(jq -r '.formatting.result' \
  "${ORCH_STATE_DIR}/plans/${SLUG}/state.json")
assert_eq "state.formatting.result is SHIP" "SHIP" "${fmt_result}"

# Aggregate FAIL → REVISE.
result=$(orch_format_aggregate "${SLUG}" FAIL)
assert_eq "orch_format_aggregate FAIL returns REVISE" "REVISE" "${result}"

# orch_format_read_verdict parses PASS/FAIL correctly.
res_file="${TEST_TMP}/result-pass.txt"
printf 'PASS\nall good\n' >"${res_file}"
verdict=$(orch_format_read_verdict "${res_file}")
assert_eq "verdict reader returns PASS for PASS file" "PASS" "${verdict}"

res_file="${TEST_TMP}/result-fail.txt"
printf 'FAIL shellcheck blocked\nSC2068...\n' >"${res_file}"
verdict=$(orch_format_read_verdict "${res_file}")
assert_eq "verdict reader returns FAIL for FAIL file" "FAIL" "${verdict}"

verdict=$(orch_format_read_verdict "${TEST_TMP}/does-not-exist.txt")
assert_eq "verdict reader returns FAIL for missing file" "FAIL" "${verdict}"

# orch_format_changed_sh / orch_format_stage_inputs against a real git
# repo with one misformatted .sh on a branch off main.
repo="${TEST_TMP}/repo"
mkdir -p "${repo}"
git init -b main -q "${repo}"
git -C "${repo}" config user.email "smoke@example.com"
git -C "${repo}" config user.name "smoke"
git -C "${repo}" config commit.gpgsign false
printf 'baseline\n' >"${repo}/README"
git -C "${repo}" add -A
git -C "${repo}" commit -q -m "init"
git -C "${repo}" switch -q -c branch-with-sh
mkdir -p "${repo}/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'echo hi' >"${repo}/scripts/h.sh"
git -C "${repo}" add -A
git -C "${repo}" commit -q -m "add h.sh"

changed=$(orch_format_changed_sh "${repo}" main)
assert_contains "changed_sh detects scripts/h.sh" \
  "${changed}" "scripts/h.sh"

orch_format_stage_inputs "${repo}" main
inputs_file="${repo}/inputs/changed-files.txt"
diff_file="${repo}/inputs/diff.patch"
assert_eq "stage_inputs wrote changed-files.txt" \
  "0" "$([[ -f "${inputs_file}" ]] && echo 0 || echo 1)"
assert_eq "stage_inputs wrote diff.patch" \
  "0" "$([[ -f "${diff_file}" ]] && echo 0 || echo 1)"
inputs_text=$(cat "${inputs_file}")
assert_contains "inputs/changed-files.txt lists scripts/h.sh" \
  "${inputs_text}" "scripts/h.sh"

# === Live engine smoke (gated) ====================================
if [[ "${CANON_E2E_LIVE:-0}" == "1" ]]; then
  echo ""
  echo "=== Live engine smoke (CANON_E2E_LIVE=1) — NOT IMPLEMENTED YET ==="
  echo "  The live path requires orch-run.sh against a fresh GitHub issue"
  echo "  and a real agent invocation; skipping for now. This is the"
  echo "  documented v1 boundary — extend in a follow-up plan."
fi

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
