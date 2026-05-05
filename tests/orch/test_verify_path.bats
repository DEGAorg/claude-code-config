#!/usr/bin/env bats
#
# Regression test for orch-verify.sh PATH injection.
#
# Forensics: when orch-verify runs criterion commands via `bash -c`,
# the subshell inherits whatever PATH the parent has. Under tmux/launchd
# the parent PATH may lack Homebrew dirs, so commands like `rg`, `yq`,
# `fd` fail to resolve and the criterion is incorrectly marked failed.
# Fix: prepend `/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:` to
# PATH inside the `bash -c` subshell. The prefix is overridable via
# ORCH_VERIFY_PATH_PREFIX so this test can point it at a tmpdir
# fixture binary instead of mutating the host's /opt/homebrew/bin.

setup() {
  TEST_TMP="$(mktemp -d -t orch-verify-path-XXXXXX)"
  export TEST_TMP
  REPO_ROOT_REAL="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export REPO_ROOT_REAL

  # Fixture: a binary under a /opt/homebrew/bin-shaped tmpdir. The
  # fixture dir is NOT in the parent PATH, so the criterion can only
  # resolve when orch-verify.sh injects it via ORCH_VERIFY_PATH_PREFIX.
  FIXTURE_BIN_DIR="${TEST_TMP}/opt/homebrew/bin"
  mkdir -p "${FIXTURE_BIN_DIR}"
  cat >"${FIXTURE_BIN_DIR}/fixture-tool" <<'SH'
#!/bin/sh
echo fixture-ok
exit 0
SH
  chmod +x "${FIXTURE_BIN_DIR}/fixture-tool"
  export FIXTURE_BIN_DIR

  SLUG="path-test"
  export SLUG
  STATE_DIR="${TEST_TMP}/.orchestrator"
  PLAN_DIR="${STATE_DIR}/worktrees/${SLUG}/.orchestrator/plans/${SLUG}"
  STATE_PLAN_DIR="${STATE_DIR}/plans/${SLUG}"
  mkdir -p "${PLAN_DIR}" "${STATE_PLAN_DIR}/logs"
  export PLAN_DIR

  cat >"${PLAN_DIR}/plan.md" <<'MD'
# Synthetic plan

## Completion criteria

- [ ] `fixture-tool` exits 0
MD

  cat >"${STATE_PLAN_DIR}/state.json" <<'JSON'
{
  "verification": {"status": "pending", "uncheckedCount": 0, "iteration": 0},
  "updatedAt": ""
}
JSON
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

@test "orch-verify resolves criterion via injected PATH prefix and marks [x]" {
  run env \
    ORCH_VERIFY_PATH_PREFIX="${FIXTURE_BIN_DIR}" \
    ORCH_STATE_DIR="${TEST_TMP}/.orchestrator" \
    ORCH_REPO_ROOT="${TEST_TMP}" \
    GH_SYNC=true \
    bash "${REPO_ROOT_REAL}/scripts/orch-verify.sh" "${SLUG}"
  [ "${status}" -eq 0 ]

  # Criterion must be flipped to [x] in the plan
  run grep -F -- '- [x] `fixture-tool` exits 0' "${PLAN_DIR}/plan.md"
  [ "${status}" -eq 0 ]
}

@test "orch-verify fails when prefix does not contain the fixture" {
  # No prefix override → defaults to /opt/homebrew/bin etc., which does
  # not contain fixture-tool. Criterion stays unchecked, exit 1.
  run env \
    ORCH_VERIFY_PATH_PREFIX="/nonexistent-prefix-dir" \
    ORCH_STATE_DIR="${TEST_TMP}/.orchestrator" \
    ORCH_REPO_ROOT="${TEST_TMP}" \
    GH_SYNC=true \
    bash "${REPO_ROOT_REAL}/scripts/orch-verify.sh" "${SLUG}"
  [ "${status}" -ne 0 ]

  run grep -F -- '- [ ] `fixture-tool` exits 0' "${PLAN_DIR}/plan.md"
  [ "${status}" -eq 0 ]
}
