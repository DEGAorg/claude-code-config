#!/usr/bin/env bash
# Ralph Loop check script for claude-code-config repo
# Run from repo root: bash scripts/ralph-check.sh
# Exit 0 if all criteria pass, exit 1 if any fail.

set -euo pipefail

PASS=0
FAIL=0
LOG=".ralph-runs.log"

check() {
  local id="$1"
  local description="$2"
  local fix="$3"
  shift 3
  if eval "$@" &>/dev/null; then
    echo "✓ ${id}: ${description}"
    PASS=$((PASS + 1))
  else
    echo "✗ ${id}: ${description}"
    echo "  → fix: ${fix}"
    FAIL=$((FAIL + 1))
  fi
}

# Harness — rules
check rules-files \
  "rules/ has all 5 language files" \
  "create missing files in rules/ (python.md, node-typescript.md, rust.md, bash.md, github-actions.md)" \
  "test -f rules/python.md &&
   test -f rules/node-typescript.md &&
   test -f rules/rust.md &&
   test -f rules/bash.md &&
   test -f rules/github-actions.md"

# Harness — commands
check commands-files \
  "commands/ has all core commands" \
  "create missing files in commands/ (fix-issue.md, review-pr.md, plan.md, cleanup.md, doc-garden.md)" \
  "test -f commands/fix-issue.md &&
   test -f commands/review-pr.md &&
   test -f commands/plan.md &&
   test -f commands/cleanup.md &&
   test -f commands/doc-garden.md"

# Harness — skills and canon rules
check skills-and-canon-rules \
  "custom-linter skill and canon domain-layering rule exist" \
  "create skills/custom-linter-authoring.md and canon/rules/domain-layering.md" \
  "test -f skills/custom-linter-authoring.md &&
   test -f canon/rules/domain-layering.md"

# Harness — exec-plans structure
check exec-plans-dirs \
  "docs/exec-plans/active/ and completed/ exist" \
  "run: mkdir -p docs/exec-plans/active docs/exec-plans/completed" \
  "test -d docs/exec-plans/active &&
   test -d docs/exec-plans/completed"

# Harness — gaps marked done in CLAUDE.md
check harness-gaps-done \
  "Gaps 1-6 marked Done in CLAUDE.md" \
  "update CLAUDE.md implementation status table: mark gaps 1-6 as Done" \
  "grep -q '| 1 .*Done' CLAUDE.md &&
   grep -q '| 2 .*Done' CLAUDE.md &&
   grep -q '| 3 .*Done' CLAUDE.md &&
   grep -q '| 4 .*Done' CLAUDE.md &&
   grep -q '| 5 .*Done' CLAUDE.md &&
   grep -q '| 6 .*Done' CLAUDE.md"

# Ralph Loop — self-check
check ralph-files \
  "ralph.yaml and ralph-check.sh exist" \
  "create ralph.yaml and scripts/ralph-check.sh (chmod +x scripts/ralph-check.sh)" \
  "test -f ralph.yaml &&
   test -x scripts/ralph-check.sh"

check ralph-instruction \
  "CLAUDE.md contains ralph check instruction" \
  "add Ralph Loop section to CLAUDE.md Working Conventions referencing ralph-check.sh" \
  "grep -q 'ralph-check.sh' CLAUDE.md"

# Summary
TOTAL=$((PASS + FAIL))
echo ""
if [ "$FAIL" -eq 0 ]; then
  RESULT="PASS ${PASS}/${TOTAL}"
  echo "RESULT: ${PASS}/${TOTAL} criteria passing. All done."
else
  RESULT="FAIL ${PASS}/${TOTAL}"
  echo "RESULT: ${PASS}/${TOTAL} criteria passing. Keep working."
fi

# Append run record to log (visible proof the agent ran this)
echo "$(date '+%Y-%m-%d %H:%M:%S') | ${RESULT}" >>"${LOG}"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
