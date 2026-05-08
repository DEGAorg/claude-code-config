#!/usr/bin/env bats
#
# Regression: AGENTS.md and agents/conductor.md must not reference the
# stale install path `~/.claude/scripts/orch-run.sh`. The canonical home
# is `~/.degacore/scripts/`. Stale `~/.claude/scripts/` copies contain
# pre-flip code (BACKGROUND=false default + unconditional tmux dashboard
# launch) and break the detached-by-default behavior asserted in
# tests/orch/test_attach_default.bats.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export REPO_ROOT
}

@test "AGENTS.md has no references to ~/.claude/scripts/orch-run.sh" {
  run grep -F -- '~/.claude/scripts/orch-run.sh' "${REPO_ROOT}/AGENTS.md"
  # grep exits 1 when no matches are found — that is the desired state.
  [ "${status}" -eq 1 ]
}

@test "agents/conductor.md has no references to ~/.claude/scripts/orch-run.sh" {
  run grep -F -- '~/.claude/scripts/orch-run.sh' "${REPO_ROOT}/agents/conductor.md"
  [ "${status}" -eq 1 ]
}
