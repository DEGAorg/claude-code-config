#!/usr/bin/env bash
# Ralph Loop health check for claude-code-config repo.
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
  local cmd="$4"
  if eval "$cmd" &>/dev/null; then
    echo "✓ ${id}: ${description}"
    PASS=$((PASS + 1))
  else
    echo "✗ ${id}: ${description}"
    echo "  → fix: ${fix}"
    FAIL=$((FAIL + 1))
  fi
}

# Shell scripts pass shellcheck
check shellcheck \
  "no shellcheck errors in scripts/ and hooks/" \
  "run: shellcheck scripts/*.sh hooks/*.sh — fix each reported issue" \
  "shellcheck scripts/*.sh hooks/*.sh"

# Shell scripts are shfmt-formatted
check shfmt \
  "shell scripts are formatted (shfmt -i 2)" \
  "run: shfmt -i 2 -w scripts/*.sh hooks/*.sh" \
  "shfmt -i 2 -d scripts/ hooks/"

# CI workflows are valid
check actionlint \
  "CI workflows pass actionlint" \
  "run: actionlint — fix each reported issue" \
  "actionlint"

# No stray TODOs in core artifacts
check no-todos \
  "no TODO/FIXME in commands/, skills/, hooks/" \
  "resolve or remove TODO/FIXME comments in commands/, skills/, hooks/" \
  "! rg 'TODO|FIXME' commands/ skills/ hooks/"

# Active exec-plans are directories (no loose .md files)
check exec-plan-dirs \
  "all entries in docs/exec-plans/active/ are directories (no loose .md files)" \
  "migrate flat .md files to directories: mkdir active/SLUG && mv active/SLUG.md active/SLUG/plan.md" \
  "! find docs/exec-plans/active -maxdepth 1 -name '*.md' | grep -q ."

# Active ralph loop: block Stop if files changed but task not claimed complete
STATE_FILE=$(find docs/exec-plans/active -name '.ralph-state.json' 2>/dev/null | head -1)
if [[ -n "${STATE_FILE}" ]]; then
  CLAIMED=$(jq -r 'if .current_task.claimed_complete == false then "false" else "true" end' "${STATE_FILE}")
  CHANGES=0
  if git rev-parse HEAD >/dev/null 2>&1; then
    CHANGES=$(git diff HEAD --name-only 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ "${CHANGES}" -gt 0 && "${CLAIMED}" == "false" ]]; then
    echo "✗ task-claimed: files changed but current task not marked complete"
    echo "  → fix: run: bash scripts/task-complete.sh ${STATE_FILE}"
    FAIL=$((FAIL + 1))
  else
    echo "✓ task-claimed: no uncommitted work without task signal"
    PASS=$((PASS + 1))
  fi
fi

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

# Append run record to log
echo "$(date '+%Y-%m-%d %H:%M:%S') | ${RESULT}" >>"${LOG}"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
