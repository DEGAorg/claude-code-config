#!/usr/bin/env bash
# Tests for the umbrella skill canon/skills/canon.md.
#
# The umbrella skill is the default NL entry point post-bootstrap. It must:
#   - Declare an @description with canon-specific NL triggers
#     ("run canon", "continue canon", "what's next in canon") — not
#     generic phrases that could over-fire.
#   - Delegate state detection to canon/scripts/phase-detect.sh rather
#     than re-implementing detection logic.
#   - Document a dispatch table covering every phase emitted by
#     phase-detect.sh (not-bootstrapped, bootstrapped-no-strategy,
#     has-strategy, running) and the sub-skill each maps to
#     (canon-new, canon-start, canon-stop, or a resume message).
#   - Reference each sub-skill by name so a reader can trace the routing
#     without reading the code.
#
# These tests are content-level assertions on the markdown file — no
# runtime behaviour is exercised here.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SKILL="$REPO_ROOT/canon/skills/canon.md"

fail_count=0
pass_count=0

assert_file_exists() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    pass_count=$((pass_count + 1))
    echo "ok  — $label"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL — $label"
    echo "  missing: $path"
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if [[ -f "$path" ]] && grep -qF -- "$needle" "$path"; then
    pass_count=$((pass_count + 1))
    echo "ok  — $label"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL — $label"
    echo "  file:   $path"
    echo "  needle: $needle"
  fi
}

assert_contains_regex() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -f "$path" ]] && grep -Eq -- "$pattern" "$path"; then
    pass_count=$((pass_count + 1))
    echo "ok  — $label"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL — $label"
    echo "  file:    $path"
    echo "  pattern: $pattern"
  fi
}

# ---- Existence ----

test_skill_file_exists() {
  assert_file_exists "$SKILL" "canon/skills/canon.md exists"
}

# ---- NL description + triggers ----

test_has_description_marker() {
  assert_contains "$SKILL" "@description" "umbrella skill declares @description"
}

test_description_mentions_run_canon() {
  assert_contains_regex "$SKILL" "run canon" "@description triggers on 'run canon'"
}

test_description_mentions_continue_canon() {
  assert_contains_regex "$SKILL" "continue canon" "@description triggers on 'continue canon'"
}

test_description_mentions_whats_next() {
  # From the Risks/decisions section: "what's next in canon"
  assert_contains_regex "$SKILL" "what'?s next in canon" "@description triggers on \"what's next in canon\""
}

# ---- Delegates to phase-detect.sh ----

test_references_phase_detect_script() {
  assert_contains "$SKILL" "canon/scripts/phase-detect.sh" "skill invokes canon/scripts/phase-detect.sh"
}

# ---- Dispatch table covers every phase ----

test_dispatch_mentions_not_bootstrapped() {
  assert_contains "$SKILL" "not-bootstrapped" "dispatch covers not-bootstrapped"
}

test_dispatch_mentions_bootstrapped_no_strategy() {
  assert_contains "$SKILL" "bootstrapped-no-strategy" "dispatch covers bootstrapped-no-strategy"
}

test_dispatch_mentions_has_strategy() {
  assert_contains "$SKILL" "has-strategy" "dispatch covers has-strategy"
}

test_dispatch_mentions_running() {
  assert_contains_regex "$SKILL" '\brunning\b' "dispatch covers running phase"
}

# ---- Dispatch targets reference each sub-skill ----

test_dispatch_routes_to_canon_new() {
  assert_contains "$SKILL" "canon-new" "dispatch routes to canon-new skill"
}

test_dispatch_routes_to_canon_start() {
  assert_contains "$SKILL" "canon-start" "dispatch routes to canon-start skill"
}

test_dispatch_routes_to_canon_stop() {
  assert_contains "$SKILL" "canon-stop" "dispatch routes to canon-stop skill"
}

# ---- Table-shaped dispatch (at least one phase→skill row) ----

test_has_dispatch_table() {
  # Markdown-table row linking a phase token to a skill. Accept either a
  # pipe-delimited table row or a clearly labelled mapping line.
  assert_contains_regex "$SKILL" \
    '(not-bootstrapped|bootstrapped-no-strategy|has-strategy|running).*(canon-new|canon-start|canon-stop)' \
    "dispatch table pairs a phase with a sub-skill on one line"
}

main() {
  test_skill_file_exists
  test_has_description_marker
  test_description_mentions_run_canon
  test_description_mentions_continue_canon
  test_description_mentions_whats_next
  test_references_phase_detect_script
  test_dispatch_mentions_not_bootstrapped
  test_dispatch_mentions_bootstrapped_no_strategy
  test_dispatch_mentions_has_strategy
  test_dispatch_mentions_running
  test_dispatch_routes_to_canon_new
  test_dispatch_routes_to_canon_start
  test_dispatch_routes_to_canon_stop
  test_has_dispatch_table

  echo ""
  echo "Passed: $pass_count  Failed: $fail_count"
  if ((fail_count > 0)); then
    exit 1
  fi
}

main "$@"
