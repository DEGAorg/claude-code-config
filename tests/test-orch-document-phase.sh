#!/usr/bin/env bash
# Tests for the per-item DOCUMENTING phase: prepare/aggregate helpers,
# PASS rollup, FAIL → REVISE rollup, rerun-only-failing-items selection,
# and stream-json report parsing. State-only — no tmux, no Claude.
#
# Mirrors the structure of test-orch-parallel-review.sh.
#
# Usage: bash tests/test-orch-document-phase.sh

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
  local label="$1" haystack="$2" needle="$3"
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

# --- Setup ---

TEST_SLUG="test-document-$$"

cleanup() {
  rm -rf "${REPO_ROOT}/.orchestrator/plans/${TEST_SLUG}"
}
trap cleanup EXIT

export ORCH_REPO_ROOT="${REPO_ROOT}"
export ORCH_STATE_DIR="${REPO_ROOT}/.orchestrator"

# Source orch-state.sh first so its functions exist.
# shellcheck source=../scripts/orch-state.sh disable=SC1091
source "${REPO_ROOT}/scripts/orch-state.sh"

# Source orch-document.sh in library mode (BASH_SOURCE != $0 so the
# main spawn loop returns early). This brings the orch_document_*
# helpers into scope without launching tmux or claude.
# shellcheck source=../scripts/orch-document.sh disable=SC1091
source "${REPO_ROOT}/scripts/orch-document.sh"

orch_ensure_plan_dirs "${TEST_SLUG}"
DOC_DIR=$(orch_plan_documenting_dir "${TEST_SLUG}")
STATE_FILE=$(orch_plan_state_file "${TEST_SLUG}")

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 4-item canary state: items 1-3 review-passed (eligible),
# item 4 work-failed and review-skipped (not eligible).
build_state() {
  jq -n \
    --arg now "${NOW}" \
    --arg slug "${TEST_SLUG}" \
    '{
      version: 1,
      plan: $slug,
      maxParallelWorkers: 4,
      mode: "foreground",
      items: [
        {id:1, description:"Item 1", deps:[], status:"done",   reviewStatus:"passed",  iteration:1, maxIterations:3, lastResult:"SHIP"},
        {id:2, description:"Item 2", deps:[], status:"done",   reviewStatus:"passed",  iteration:1, maxIterations:3, lastResult:"SHIP"},
        {id:3, description:"Item 3", deps:[], status:"done",   reviewStatus:"passed",  iteration:1, maxIterations:3, lastResult:"SHIP"},
        {id:4, description:"Item 4", deps:[], status:"failed", reviewStatus:"skipped", iteration:1, maxIterations:3, lastResult:"work-failed"}
      ],
      finalReview:   { status: "done",    result: "SHIP", reworkItems: [] },
      documentation: { status: "pending", result: null,   reworkItems: [] },
      startedAt: $now,
      updatedAt: $now
    }'
}

# ===================================================================
echo ""
echo "=== Test 1: prepare_item_states transitions docStatus correctly ==="

orch_write_state "${TEST_SLUG}" "$(build_state)"
orch_init_documentation_state "${TEST_SLUG}"
orch_document_prepare_item_states "${TEST_SLUG}"

DS1=$(jq -r '.items[] | select(.id == 1) | .docStatus' "${STATE_FILE}")
DS2=$(jq -r '.items[] | select(.id == 2) | .docStatus' "${STATE_FILE}")
DS3=$(jq -r '.items[] | select(.id == 3) | .docStatus' "${STATE_FILE}")
DS4=$(jq -r '.items[] | select(.id == 4) | .docStatus' "${STATE_FILE}")
DOC_STATUS=$(jq -r '.documentation.status' "${STATE_FILE}")
DOC_RESULT=$(jq -r '.documentation.result' "${STATE_FILE}")

assert_eq "review-passed item 1 → docStatus=pending" "pending" "${DS1}"
assert_eq "review-passed item 2 → docStatus=pending" "pending" "${DS2}"
assert_eq "review-passed item 3 → docStatus=pending" "pending" "${DS3}"
assert_eq "work-failed item 4   → docStatus=skipped" "skipped" "${DS4}"
assert_eq "documentation.status running" "running" "${DOC_STATUS}"
assert_eq "documentation.result still null" "null" "${DOC_RESULT}"

# ===================================================================
echo ""
echo "=== Test 2: orch_sync_documenting_files — PASS / FAIL / unexpected ==="

# Mark items 1, 2, 3 as documenting and write their doc files.
for id in 1 2 3; do
  orch_document_mark_documenting "${TEST_SLUG}" "${id}"
done

cat >"${DOC_DIR}/item-1.txt" <<'EOF'
PASS
status: PASS
item_id: 1
edited_files:
  - README.md
summary: |
  Added orch-document.sh to README's command table.
EOF

cat >"${DOC_DIR}/item-2.txt" <<'EOF'
PASS
status: NO_CHANGES_NEEDED
item_id: 2
edited_files: []
summary: |
  Internal-only change. No external surface to document.
EOF

cat >"${DOC_DIR}/item-3.txt" <<'EOF'
FAIL
status: BLOCKED
item_id: 3
blockers: |
  Diff describes a new config field but no docs/ page exists for it.
EOF

orch_sync_documenting_files "${TEST_SLUG}"

DS1=$(jq -r '.items[] | select(.id == 1) | .docStatus' "${STATE_FILE}")
DS2=$(jq -r '.items[] | select(.id == 2) | .docStatus' "${STATE_FILE}")
DS3=$(jq -r '.items[] | select(.id == 3) | .docStatus' "${STATE_FILE}")
assert_eq "item 1 PASS file → docStatus=passed" "passed" "${DS1}"
assert_eq "item 2 PASS file → docStatus=passed" "passed" "${DS2}"
assert_eq "item 3 FAIL file → docStatus=failed" "failed" "${DS3}"

# Garbage decision marks failed
orch_write_state "${TEST_SLUG}" "$(build_state)"
orch_init_documentation_state "${TEST_SLUG}"
orch_document_prepare_item_states "${TEST_SLUG}"
orch_document_mark_documenting "${TEST_SLUG}" 1
printf 'MAYBE\nNot sure about this.\n' >"${DOC_DIR}/item-1.txt"
orch_sync_documenting_files "${TEST_SLUG}"
DS1=$(jq -r '.items[] | select(.id == 1) | .docStatus' "${STATE_FILE}")
assert_eq "unexpected token → docStatus=failed" "failed" "${DS1}"

# ===================================================================
echo ""
echo "=== Test 3: aggregate — all PASS yields SHIP ==="

orch_write_state "${TEST_SLUG}" "$(build_state)"
orch_init_documentation_state "${TEST_SLUG}"
orch_document_prepare_item_states "${TEST_SLUG}"

# Mark items 1-3 documenting + write PASS files
for id in 1 2 3; do
  orch_document_mark_documenting "${TEST_SLUG}" "${id}"
  printf 'PASS\nstatus: PASS\nitem_id: %s\n' "${id}" >"${DOC_DIR}/item-${id}.txt"
done

orch_sync_documenting_files "${TEST_SLUG}"

RESULT=$(orch_document_aggregate "${TEST_SLUG}")
assert_eq "all PASS → aggregate echoes SHIP" "SHIP" "${RESULT}"

DOC_RESULT=$(jq -r '.documentation.result' "${STATE_FILE}")
DOC_STATUS=$(jq -r '.documentation.status' "${STATE_FILE}")
REWORK=$(jq '.documentation.reworkItems | length' "${STATE_FILE}")
assert_eq "documentation.result SHIP" "SHIP" "${DOC_RESULT}"
assert_eq "documentation.status done" "done" "${DOC_STATUS}"
assert_eq "no rework items" "0" "${REWORK}"

# Item 4 stays skipped (work-failed) and does not block SHIP
DS4=$(jq -r '.items[] | select(.id == 4) | .docStatus' "${STATE_FILE}")
S4=$(jq -r '.items[] | select(.id == 4) | .status' "${STATE_FILE}")
assert_eq "work-failed item 4 docStatus stays skipped" "skipped" "${DS4}"
assert_eq "work-failed item 4 status stays failed" "failed" "${S4}"

# ===================================================================
echo ""
echo "=== Test 4: aggregate — any FAIL/BLOCKED yields REVISE ==="

orch_write_state "${TEST_SLUG}" "$(build_state)"
orch_init_documentation_state "${TEST_SLUG}"
orch_document_prepare_item_states "${TEST_SLUG}"

for id in 1 2 3; do
  orch_document_mark_documenting "${TEST_SLUG}" "${id}"
done

# Item 1 PASS, item 2 BLOCKED → FAIL, item 3 PASS
printf 'PASS\nstatus: PASS\nitem_id: 1\n' >"${DOC_DIR}/item-1.txt"
printf 'FAIL\nstatus: BLOCKED\nitem_id: 2\n' >"${DOC_DIR}/item-2.txt"
printf 'PASS\nstatus: PASS\nitem_id: 3\n' >"${DOC_DIR}/item-3.txt"

orch_sync_documenting_files "${TEST_SLUG}"

RESULT=$(orch_document_aggregate "${TEST_SLUG}")
assert_eq "any FAIL → aggregate echoes REVISE" "REVISE" "${RESULT}"

DOC_RESULT=$(jq -r '.documentation.result' "${STATE_FILE}")
REWORK_IDS=$(jq -c '.documentation.reworkItems' "${STATE_FILE}")
S2=$(jq -r '.items[] | select(.id == 2) | .status' "${STATE_FILE}")
ITER2=$(jq -r '.items[] | select(.id == 2) | .iteration' "${STATE_FILE}")
RS2=$(jq -r '.items[] | select(.id == 2) | .reviewStatus' "${STATE_FILE}")
DS2=$(jq -r '.items[] | select(.id == 2) | .docStatus' "${STATE_FILE}")
S1=$(jq -r '.items[] | select(.id == 1) | .status' "${STATE_FILE}")
DS1=$(jq -r '.items[] | select(.id == 1) | .docStatus' "${STATE_FILE}")
DS3=$(jq -r '.items[] | select(.id == 3) | .docStatus' "${STATE_FILE}")

assert_eq "documentation.result REVISE" "REVISE" "${DOC_RESULT}"
assert_eq "rework items [2]" "[2]" "${REWORK_IDS}"
assert_eq "failed item 2 reset → status=ready" "ready" "${S2}"
assert_eq "failed item 2 iteration incremented" "2" "${ITER2}"
assert_eq "failed item 2 reset → reviewStatus=pending" "pending" "${RS2}"
assert_eq "failed item 2 reset → docStatus=pending" "pending" "${DS2}"
assert_eq "passed item 1 stays done" "done" "${S1}"
assert_eq "passed item 1 docStatus stays passed" "passed" "${DS1}"
assert_eq "passed item 3 docStatus stays passed" "passed" "${DS3}"

# ===================================================================
echo ""
echo "=== Test 5: rerun-only-failing-items — second phase entry ==="
echo "          (state already reflects post-REVISE rollup from Test 4)"

# Simulate the engine re-entering documenting after the wave re-runs
# item 2 and review re-passes it. The wave mutation: reviewStatus → "passed".
UPDATED=$(jq '(.items[] | select(.id == 2)).reviewStatus = "passed"' "${STATE_FILE}")
orch_write_state "${TEST_SLUG}" "${UPDATED}"

# Phase entry helpers run again (idempotent)
orch_init_documentation_state "${TEST_SLUG}"
orch_document_prepare_item_states "${TEST_SLUG}"

DS1=$(jq -r '.items[] | select(.id == 1) | .docStatus' "${STATE_FILE}")
DS2=$(jq -r '.items[] | select(.id == 2) | .docStatus' "${STATE_FILE}")
DS3=$(jq -r '.items[] | select(.id == 3) | .docStatus' "${STATE_FILE}")
DS4=$(jq -r '.items[] | select(.id == 4) | .docStatus' "${STATE_FILE}")

assert_eq "item 1 still passed (no re-doc on rerun)" "passed" "${DS1}"
assert_eq "item 2 pending (re-doc target)" "pending" "${DS2}"
assert_eq "item 3 still passed (no re-doc on rerun)" "passed" "${DS3}"
assert_eq "item 4 still skipped" "skipped" "${DS4}"

# Selection logic: only docStatus=pending items get spawned
PENDING_IDS=$(jq -r \
  '.items[] | select(.docStatus == "pending") | .id' "${STATE_FILE}" |
  tr '\n' ' ' | sed 's/ $//')
assert_eq "second pass selects only failed item 2" "2" "${PENDING_IDS}"

# Documentation.reworkItems carried forward (helper preserves .documentation)
REWORK_IDS=$(jq -c '.documentation.reworkItems' "${STATE_FILE}")
assert_eq "documentation.reworkItems preserved on re-entry" "[2]" "${REWORK_IDS}"

# Now write PASS for item 2 and aggregate again — should SHIP
orch_document_mark_documenting "${TEST_SLUG}" 2
printf 'PASS\nstatus: PASS\nitem_id: 2\n' >"${DOC_DIR}/item-2.txt"
orch_sync_documenting_files "${TEST_SLUG}"

RESULT=$(orch_document_aggregate "${TEST_SLUG}")
assert_eq "second pass aggregates to SHIP after fix" "SHIP" "${RESULT}"

DOC_RESULT=$(jq -r '.documentation.result' "${STATE_FILE}")
REWORK=$(jq '.documentation.reworkItems | length' "${STATE_FILE}")
assert_eq "second pass documentation.result SHIP" "SHIP" "${DOC_RESULT}"
assert_eq "second pass clears reworkItems" "0" "${REWORK}"

# ===================================================================
echo ""
echo "=== Test 6: parse_report — extracts decision from stream-json log ==="

TMP_LOG=$(mktemp)

# Valid PASS report inside an assistant text chunk
cat >"${TMP_LOG}" <<'EOF'
{"type":"system","subtype":"init"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at the diff..."}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Final report:\n\n```doc-writer-report\nstatus: PASS\nitem_id: 1\nedited_files:\n  - README.md\nsummary: |\n  Added a new entry.\n```\n"}]}}
{"type":"result","is_error":false}
EOF
PARSED=$(orch_document_parse_report "${TMP_LOG}")
HEAD=$(printf '%s' "${PARSED}" | head -1 | tr -d '[:space:]')
assert_eq "parse_report — PASS first line" "PASS" "${HEAD}"
assert_contains "parse_report — body has status: PASS" "${PARSED}" "status: PASS"
assert_contains "parse_report — body has edited_files" "${PARSED}" "README.md"

# BLOCKED report → first line FAIL
cat >"${TMP_LOG}" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"```doc-writer-report\nstatus: BLOCKED\nitem_id: 2\nedited_files: []\nblockers: |\n  Need new doc file.\n```"}]}}
EOF
PARSED=$(orch_document_parse_report "${TMP_LOG}")
HEAD=$(printf '%s' "${PARSED}" | head -1 | tr -d '[:space:]')
assert_eq "parse_report — BLOCKED → FAIL" "FAIL" "${HEAD}"
assert_contains "parse_report — body preserves blocker" "${PARSED}" "Need new doc file"

# NO_CHANGES_NEEDED → PASS
cat >"${TMP_LOG}" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"```doc-writer-report\nstatus: NO_CHANGES_NEEDED\nitem_id: 3\nedited_files: []\nsummary: |\n  Internal-only.\n```"}]}}
EOF
PARSED=$(orch_document_parse_report "${TMP_LOG}")
HEAD=$(printf '%s' "${PARSED}" | head -1 | tr -d '[:space:]')
assert_eq "parse_report — NO_CHANGES_NEEDED → PASS" "PASS" "${HEAD}"

# Missing block → FAIL
cat >"${TMP_LOG}" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"I cannot determine the correct doc edit."}]}}
EOF
PARSED=$(orch_document_parse_report "${TMP_LOG}")
HEAD=$(printf '%s' "${PARSED}" | head -1 | tr -d '[:space:]')
assert_eq "parse_report — missing block → FAIL" "FAIL" "${HEAD}"
assert_contains "parse_report — diagnostic on missing block" "${PARSED}" "No doc-writer-report block"

# Plain-text log (non-stream-json) — fallback path
cat >"${TMP_LOG}" <<'EOF'
some preamble
```doc-writer-report
status: PASS
item_id: 9
edited_files:
  - AGENTS.md
```
EOF
PARSED=$(orch_document_parse_report "${TMP_LOG}")
HEAD=$(printf '%s' "${PARSED}" | head -1 | tr -d '[:space:]')
assert_eq "parse_report — plain-text fallback PASS" "PASS" "${HEAD}"

rm -f "${TMP_LOG}"

# ===================================================================
echo ""
echo "=== Test 7: extract_edited_files — list / inline / NO_CHANGES_NEEDED ==="

TMP_DOC=$(mktemp)

cat >"${TMP_DOC}" <<'EOF'
PASS
status: PASS
edited_files:
  - README.md
  - AGENTS.md
summary: |
  Updates.
EOF
LIST=$(orch_document_extract_edited_files "${TMP_DOC}" | tr '\n' ' ' | sed 's/ $//')
assert_eq "extract — block list returns both paths" "README.md AGENTS.md" "${LIST}"

cat >"${TMP_DOC}" <<'EOF'
PASS
status: NO_CHANGES_NEEDED
edited_files: []
EOF
LIST=$(orch_document_extract_edited_files "${TMP_DOC}")
assert_eq "extract — empty inline list returns nothing" "" "${LIST}"

cat >"${TMP_DOC}" <<'EOF'
PASS
status: PASS
edited_files: [README.md, docs/x.md]
EOF
LIST=$(orch_document_extract_edited_files "${TMP_DOC}" | tr '\n' ' ' | sed 's/ $//')
assert_eq "extract — inline list returns both paths" "README.md docs/x.md" "${LIST}"

rm -f "${TMP_DOC}"

# ===================================================================
echo ""
echo "=== Test 8: feedback file format on REVISE ==="
#
# Re-create the REVISE state from Test 4 so we can verify the feedback
# bundle the engine and re-spawned workers will see. We simulate the
# main script's feedback-write block (the script wraps it inside the
# main entry point we cannot trigger here without tmux).

orch_write_state "${TEST_SLUG}" "$(build_state)"
orch_init_documentation_state "${TEST_SLUG}"
orch_document_prepare_item_states "${TEST_SLUG}"

for id in 1 2 3; do
  orch_document_mark_documenting "${TEST_SLUG}" "${id}"
done
printf 'PASS\nstatus: PASS\nitem_id: 1\n' >"${DOC_DIR}/item-1.txt"
printf 'FAIL\nstatus: BLOCKED\nblockers: |\n  Need new doc page.\n' >"${DOC_DIR}/item-2.txt"
printf 'PASS\nstatus: PASS\nitem_id: 3\n' >"${DOC_DIR}/item-3.txt"

orch_sync_documenting_files "${TEST_SLUG}"
RESULT=$(orch_document_aggregate "${TEST_SLUG}")
assert_eq "Test 8 setup — REVISE produced" "REVISE" "${RESULT}"

# Build feedback bundle the same way orch-document.sh main does
PLAN_DIR_FOR_TEST="${REPO_ROOT}/.orchestrator/plans/${TEST_SLUG}"
mkdir -p "${PLAN_DIR_FOR_TEST}"
FAILED_IDS=$(jq -r '.documentation.reworkItems[]?' "${STATE_FILE}")
FEEDBACK="${PLAN_DIR_FOR_TEST}/document-feedback.txt"
{
  printf 'REWORK_ITEMS: %s\n' \
    "$(printf '%s\n' "${FAILED_IDS}" | paste -sd ', ' -)"
  for fid in ${FAILED_IDS}; do
    doc="${DOC_DIR}/item-${fid}.txt"
    if [[ -f "${doc}" ]]; then
      printf '\n--- item %s (documenter failed) ---\n' "${fid}"
      tail -n +2 "${doc}"
    fi
  done
} >"${FEEDBACK}"

FEEDBACK_BODY=$(cat "${FEEDBACK}")
assert_contains "feedback lists rework items" "${FEEDBACK_BODY}" "REWORK_ITEMS: 2"
assert_contains "feedback inlines item 2 blocker" "${FEEDBACK_BODY}" "Need new doc page"

rm -f "${FEEDBACK}"

# --- Summary ---

echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
