#!/usr/bin/env bats
#
# Tests for the detached-by-default behavior of scripts/orch-run.sh.
#
# The default invocation must run orchestration without a tmux
# `dashboard` window and without invoking `orch-display.sh`. The
# `--attach` flag (alias `-a`) opts back into the legacy foreground
# behavior. `--background` is preserved as a silent no-op so existing
# callers do not break.
#
# Strategy: spin up a self-contained git repo in TEST_TMP that mirrors
# the real repo's `scripts/` tree. tmux, node, and orch-display.sh are
# replaced by recording shims that append their argv to log files.
# orch-run.sh is invoked against a stub plan; assertions inspect the
# recorded calls. Because tmux is shimmed, no real session, engine, or
# worker is ever spawned — the test exercises orch-run.sh's launch
# logic only.

REPO_ROOT_REAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

setup() {
  TEST_TMP="$(mktemp -d -t orch-attach-XXXXXX)"
  export TEST_TMP

  SLUG="attach-test"
  export SLUG

  # Mirror the real scripts/ tree so orch-run.sh's `source` and
  # `${SCRIPT_DIR}/...` lookups resolve inside the test repo.
  mkdir -p "${TEST_TMP}/scripts"
  cp -R "${REPO_ROOT_REAL}/scripts/." "${TEST_TMP}/scripts/"

  # Recording log files.
  TMUX_LOG="${TEST_TMP}/tmux-calls.log"
  NODE_LOG="${TEST_TMP}/node-calls.log"
  DISPLAY_LOG="${TEST_TMP}/orch-display-calls.log"
  export TMUX_LOG NODE_LOG DISPLAY_LOG
  : >"${TMUX_LOG}"
  : >"${NODE_LOG}"
  : >"${DISPLAY_LOG}"

  # Replace orch-display.sh in the copied tree with a recording stub.
  # orch-run.sh invokes it as `bash "${SCRIPT_DIR}/orch-display.sh"`.
  cat >"${TEST_TMP}/scripts/orch-display.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${DISPLAY_LOG}"
exit 0
STUB
  chmod +x "${TEST_TMP}/scripts/orch-display.sh"

  # PATH shims for tmux + node. Each records its argv and emulates the
  # minimum behavior orch-run.sh expects.
  SHIM_DIR="${TEST_TMP}/shims"
  mkdir -p "${SHIM_DIR}"

  cat >"${SHIM_DIR}/tmux" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TMUX_LOG}"
case "$1" in
has-session) exit 1 ;;
list-windows) exit 0 ;;
*) exit 0 ;;
esac
SHIM
  chmod +x "${SHIM_DIR}/tmux"

  cat >"${SHIM_DIR}/node" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${NODE_LOG}"
exit 0
SHIM
  chmod +x "${SHIM_DIR}/node"

  export PATH="${SHIM_DIR}:${PATH}"

  # Minimal repo state: github.sync false so the GH-issue auto-create
  # path is skipped and the plan lives under docs/exec-plans/active/.
  cat >"${TEST_TMP}/dega-core.yaml" <<'YAML'
provider: github
github:
  sync: false
YAML

  PLAN_DIR="${TEST_TMP}/docs/exec-plans/active/${SLUG}"
  mkdir -p "${PLAN_DIR}"
  cat >"${PLAN_DIR}/plan.md" <<'PLAN'
# Plan: attach-test

## Progress log

- [ ] do nothing
PLAN

  # Initialize a real git repo so `git rev-parse --show-toplevel` works
  # and orch_create_worktree can `git worktree add` against HEAD. The
  # plan must be committed to satisfy the dirty-plan guard.
  git -C "${TEST_TMP}" init --quiet --initial-branch=main
  git -C "${TEST_TMP}" config user.email "test@example.com"
  git -C "${TEST_TMP}" config user.name "Test"
  git -C "${TEST_TMP}" add -A
  git -C "${TEST_TMP}" commit --quiet -m "init"

  # Pin state + repo roots into the test repo for full isolation.
  export ORCH_REPO_ROOT="${TEST_TMP}"
  export ORCH_STATE_DIR="${TEST_TMP}/.orchestrator"

  cd "${TEST_TMP}"
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

# Run orch-run.sh from the test repo, capturing status + output.
# Note: a leading `!` does not trigger bash errexit, so negative
# assertions in this file always go through `run` + an explicit status
# check rather than `! grep ...`.
run_orch() {
  run bash "${TEST_TMP}/scripts/orch-run.sh" "${SLUG}" "$@"
}

assert_orch_ok() {
  if [ "${status}" -ne 0 ]; then
    printf 'orch-run.sh failed (status=%s)\n--- output ---\n%s\n' \
      "${status}" "${output}" >&2
    return 1
  fi
}

assert_grep() {
  run grep -qE "$1" "$2"
  [ "${status}" -eq 0 ]
}

refute_grep() {
  run grep -qE "$1" "$2"
  [ "${status}" -ne 0 ]
}

# --- (1) default = detached ---

@test "default invocation creates session with no dashboard window and does not invoke orch-display.sh" {
  run_orch
  assert_orch_ok
  assert_grep '^new-session ' "${TMUX_LOG}"
  assert_grep '^new-window .* -n engine' "${TMUX_LOG}"
  refute_grep '^new-session .* -n dashboard' "${TMUX_LOG}"
  [ ! -s "${DISPLAY_LOG}" ]
  # node is never executed in detached mode (no dashboard loop). The
  # tmux shim records the new-session command string but does not
  # execute it, so node only runs if orch-run.sh itself spawns it.
  [ ! -s "${NODE_LOG}" ]
}

# --- (2) --attach = legacy foreground ---

@test "--attach creates a dashboard window and invokes orch-display.sh" {
  run_orch --attach
  assert_orch_ok
  assert_grep '^new-session .* -n dashboard' "${TMUX_LOG}"
  assert_grep '^new-window .* -n engine' "${TMUX_LOG}"
  [ -s "${DISPLAY_LOG}" ]
}

# --- (3) -a alias matches --attach ---

@test "-a short alias matches --attach" {
  run_orch -a
  assert_orch_ok
  assert_grep '^new-session .* -n dashboard' "${TMUX_LOG}"
  [ -s "${DISPLAY_LOG}" ]
}

# --- (4) --background = silent no-op (matches default) ---

@test "--background exits 0 silently and behaves identically to default" {
  run_orch --background
  assert_orch_ok
  refute_grep '^new-session .* -n dashboard' "${TMUX_LOG}"
  [ ! -s "${DISPLAY_LOG}" ]
  # No "unknown option" or surprise error noise from the deprecation.
  [[ "${output}" != *"unknown option"* ]]
  [[ "${output}" != *"Unknown option"* ]]
}

# --- (5) detached session ends cleanly after engine exit ---
#
# In detached mode the dashboard window does not exist, so the engine
# window's command string is the only thing keeping the session alive
# after engine exit. It must include the `tmux kill-session` cleanup
# epilogue so the session is reaped without operator intervention.

@test "detached session has cleanup wired so it ends after engine exit" {
  run_orch
  assert_orch_ok
  assert_grep '^new-window .* -n engine' "${TMUX_LOG}"
  assert_grep '^new-window .* -n engine .*tmux kill-session' "${TMUX_LOG}"
}
