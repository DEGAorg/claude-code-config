#!/usr/bin/env bash
# Tests for scripts/orch-format.sh — the per-plan FORMATTING phase runner.
#
# Drives the runner end-to-end with a stubbed `claude` on PATH that
# mimics the lint-fixer agent contract closely enough to exercise every
# branch the runner has to handle. Each case builds its own temp git
# repo + worktree under .orchestrator/worktrees/<slug>/, runs the
# runner against it, and asserts on exit code, the contents of
# formatting/result.txt, and whether a chore: commit landed.
#
# Cases (plan #310 — 20260510-orch-lint-gate, item 2):
#   (a) all .sh already clean     → exit 0, PASS, no new commit
#   (b) misformatted .sh          → exit 0, PASS, one chore: commit
#   (c) shellcheck-failing .sh    → exit non-zero, FAIL, lint output in result.txt
#   (d) no .sh files changed      → exit 0, PASS, no new commit
#
# Tmux is isolated via a per-test TMUX_TMPDIR so the test never collides
# with the user's running tmux server; PATH is set before the server
# starts, so the stub propagates into every spawned window.
#
# Usage: bash tests/test-orch-format-phase.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Override path is for self-validation: lets the test author exercise
# a throwaway runner before scripts/orch-format.sh lands.
RUNNER="${ORCH_FORMAT_RUNNER:-${REPO_ROOT}/scripts/orch-format.sh}"

PASS=0
FAIL=0

# --- Assertion helpers ---

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

assert_nonzero() {
  local label="$1" actual="$2"
  if [[ "${actual}" != "0" ]]; then
    echo "  PASS: ${label} (exit ${actual})"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${label} (expected non-zero, got 0)"
    FAIL=$((FAIL + 1))
  fi
}

# --- Env preconditions ---

for bin in tmux shfmt shellcheck jq git; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "skip: ${bin} not on PATH; this test requires it"
    exit 0
  fi
done

if [[ ! -f "${RUNNER}" ]]; then
  echo "skip: ${RUNNER} not present yet — item 3 has not landed."
  echo "      The test file is authored ahead of the runner (TDD); it"
  echo "      will execute once scripts/orch-format.sh exists."
  exit 0
fi

# --- Test infra ---

TEST_TMP="$(mktemp -d -t orch-format-test.XXXXXX)"
STUB_DIR="${TEST_TMP}/stub-bin"
mkdir -p "${STUB_DIR}"

# Isolated tmux server. Setting TMUX_TMPDIR before any `tmux` call routes
# both the test's setup and the runner through the same private socket;
# the server inherits PATH from this shell, so the stub propagates into
# every window the runner spawns.
#
# macOS pins unix-domain socket paths at 104 chars, so the tmpdir for the
# socket must be short — `/var/folders/...` from mktemp -t blows past it.
# We use a stable short path under /tmp keyed on this shell's PID.
TMUX_TMPDIR="/tmp/orch-fmt-$$/tmux"
export TMUX_TMPDIR
mkdir -p "${TMUX_TMPDIR}"

TMUX_SESSIONS=()

cleanup() {
  for s in "${TMUX_SESSIONS[@]:-}"; do
    [[ -n "${s:-}" ]] || continue
    tmux kill-session -t "${s}" 2>/dev/null || true
  done
  tmux kill-server 2>/dev/null || true
  rm -rf "${TEST_TMP}" "/tmp/orch-fmt-$$"
}
trap cleanup EXIT

# Stub `claude`. Implements the lint-fixer agent contract just closely
# enough to drive every test case:
#
#   1. Reads inputs/changed-files.txt from cwd (the worktree).
#   2. Empty or missing list → writes PASS, exits 0 (case d).
#   3. Otherwise: run shfmt -i 2 -w on each path, then run shellcheck
#      across the set.
#   4. Linter OK   → `git add` each path, write PASS (cases a, b).
#   5. Linter FAIL → write `FAIL <reason>` followed by the raw lint
#      output to formatting/result.txt (case c). The internal "can't
#      fix" iteration loop is collapsed to a single pass — the contract
#      under test is the runner's reaction to a FAIL result, not the
#      agent's internal retry budget.
cat >"${STUB_DIR}/claude" <<'STUB_EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p formatting
result_file="formatting/result.txt"
inputs_file="inputs/changed-files.txt"

if [[ ! -s "${inputs_file}" ]]; then
  printf 'PASS\n' >"${result_file}"
  exit 0
fi

mapfile -t files <"${inputs_file}"

for f in "${files[@]}"; do
  [[ -z "${f}" ]] && continue
  shfmt -i 2 -w "${f}"
done

sc_rc=0
sc_output=$(shellcheck -e SC1091 -S warning "${files[@]}" 2>&1) || sc_rc=$?

if [[ "${sc_rc}" -ne 0 ]]; then
  {
    printf 'FAIL shellcheck unresolved after 3 iterations on %s\n' \
      "${files[0]}"
    printf '%s\n' "${sc_output}"
  } >"${result_file}"
  exit 0
fi

for f in "${files[@]}"; do
  [[ -z "${f}" ]] && continue
  git add -- "${f}"
done

printf 'PASS\n' >"${result_file}"
STUB_EOF
chmod +x "${STUB_DIR}/claude"

export PATH="${STUB_DIR}:${PATH}"
# Pin the agent shim to claude so the runner uses the bare `claude`
# command (which our PATH stub intercepts) instead of gemini/codex.
export DEGA_PROVIDER="claude"

# --- Fixture builder ---
#
# Builds a per-test git repo with the layout orch-format.sh expects:
#   .orchestrator/plans/<slug>/state.json     — per-plan state
#   .orchestrator/worktrees/<slug>/           — real git worktree
#   docs/exec-plans/active/<slug>/plan.md     — plan body
#   dega-core.yaml                            — config (fast polling)
#
# Each test passes its own stage_fn which runs against the worktree to
# create the diff vs main that the case requires.
#
# Outputs (globals, read by the test cases):
#   FIXTURE_REPO       — main repo root
#   FIXTURE_WORKTREE   — git worktree dir (cwd for the agent)
build_fixture() {
  local slug="$1"
  local stage_fn="$2"

  local repo="${TEST_TMP}/${slug}/repo"
  rm -rf "${TEST_TMP:?}/${slug}"
  mkdir -p "${repo}"
  git init -b main -q "${repo}"
  git -C "${repo}" config user.email "test@example.com"
  git -C "${repo}" config user.name "orch-format-test"
  git -C "${repo}" config commit.gpgsign false

  mkdir -p "${repo}/scripts"
  cat >"${repo}/scripts/baseline.sh" <<'EOF'
#!/usr/bin/env bash
echo "baseline"
EOF
  git -C "${repo}" add -A
  git -C "${repo}" commit -q -m "init"

  local plan_dir="${repo}/.orchestrator/plans/${slug}"
  mkdir -p "${plan_dir}"/{done,documenting,reviews,logs}
  cat >"${plan_dir}/state.json" <<EOF
{
  "version": 1,
  "plan": "${slug}",
  "branch": "orch/${slug}",
  "base": "main",
  "maxParallelWorkers": 1,
  "mode": "foreground",
  "items": [
    {"id": 1, "description": "Stub item", "deps": [],
     "status": "done", "reviewStatus": "passed",
     "iteration": 1, "maxIterations": 3, "lastResult": "SHIP"}
  ],
  "finalReview":   {"status": "done", "result": "SHIP",  "reworkItems": []},
  "documentation": {"status": "done", "result": "SHIP",  "reworkItems": []},
  "formatting":    {"status": "pending", "result": null, "reworkItems": []}
}
EOF

  mkdir -p "${repo}/docs/exec-plans/active/${slug}"
  cat >"${repo}/docs/exec-plans/active/${slug}/plan.md" <<EOF
# Fixture plan: ${slug}

## Progress log

- [x] Stub item
EOF

  cat >"${repo}/dega-core.yaml" <<'EOF'
max_iterations: 3
review_poll_interval_seconds: 1
format_poll_interval_seconds: 1
verify:
  mode: advisory
EOF

  # Real git worktree on orch/<slug> branched from main. The worker's
  # commits land here; the runner's `git diff main..HEAD -- '*.sh'`
  # sees them. Each worktree has its own index, so the stub's `git add`
  # stages cleanly without touching the main repo.
  local wt="${repo}/.orchestrator/worktrees/${slug}"
  mkdir -p "$(dirname "${wt}")"
  git -C "${repo}" worktree add -q -b "orch/${slug}" "${wt}" main
  git -C "${wt}" config user.email "test@example.com"
  git -C "${wt}" config user.name "orch-format-test"
  git -C "${wt}" config commit.gpgsign false

  FIXTURE_REPO="${repo}"
  FIXTURE_WORKTREE="${wt}"

  "${stage_fn}" "${wt}"

  local session="orch-${slug}"
  tmux kill-session -t "${session}" 2>/dev/null || true
  tmux new-session -d -s "${session}" -n "control"
  TMUX_SESSIONS+=("${session}")
}

# Run orch-format.sh against the current fixture and echo its exit code.
# Runner stdout/stderr is redirected to stderr so the function's only
# captured output is the exit-code string consumed by the caller.
run_format_runner() {
  local slug="$1"
  local exit_code=0
  (
    cd "${FIXTURE_REPO}"
    ORCH_REPO_ROOT="${FIXTURE_REPO}" \
      ORCH_STATE_DIR="${FIXTURE_REPO}/.orchestrator" \
      ORCH_BASE="main" \
      ORCH_FORMAT_AGENT_TIMEOUT=60 \
      ORCH_FORMAT_POLL_INTERVAL=1 \
      timeout 90 bash "${RUNNER}" "${slug}" >&2
  ) || exit_code=$?
  printf '%s' "${exit_code}"
}

# --- Scenario stagers ---

stage_clean_sh() {
  local wt="$1"
  cat >"${wt}/scripts/clean.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "already clean"
EOF
  shfmt -i 2 -w "${wt}/scripts/clean.sh"
  git -C "${wt}" add -A
  git -C "${wt}" commit -q -m "orch: item 1 — add clean.sh"
}

stage_misformatted_sh() {
  local wt="$1"
  # 4-space indent — shfmt -i 2 will rewrite to 2-space.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if true; then' \
    '    echo "indent is four"' \
    'fi' >"${wt}/scripts/badfmt.sh"
  git -C "${wt}" add -A
  git -C "${wt}" commit -q -m "orch: item 1 — add badfmt.sh"
}

stage_shellcheck_broken_sh() {
  local wt="$1"
  # SC2068 (error severity, caught by -S warning): unquoted "$@"
  # expansion. shfmt does not fix this and the stub agent does not
  # attempt a remediation pass, mirroring the "agent can't fix" path
  # the runner has to handle. Use SC2068 rather than SC2086 because
  # SC2086 is info-level and -S warning filters it out.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'echo $@' >"${wt}/scripts/broken.sh"
  git -C "${wt}" add -A
  git -C "${wt}" commit -q -m "orch: item 1 — add broken.sh"
}

stage_no_sh_changed() {
  local wt="$1"
  # Add a non-.sh file so the orch branch has commits vs main, but
  # `git diff main..HEAD -- '*.sh'` returns an empty list.
  cat >"${wt}/NOTES.md" <<'EOF'
This change has no shell impact.
EOF
  git -C "${wt}" add -A
  git -C "${wt}" commit -q -m "orch: item 1 — add NOTES.md"
}

# === Case (a): clean .sh — PASS, no chore: commit =================
echo ""
echo "=== Case (a): all .sh already clean ==="

SLUG_A="format-test-clean-$$"
build_fixture "${SLUG_A}" stage_clean_sh

commits_before_a=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
exit_a=$(run_format_runner "${SLUG_A}")
commits_after_a=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
result_a="$(cat "${FIXTURE_WORKTREE}/formatting/result.txt" 2>/dev/null || true)"

assert_eq "(a) runner exits 0" "0" "${exit_a}"
assert_contains "(a) result.txt carries PASS" "${result_a}" "PASS"
assert_eq "(a) no new commit added" \
  "${commits_before_a}" "${commits_after_a}"

# === Case (b): misformatted .sh — PASS + one chore: commit ========
echo ""
echo "=== Case (b): misformatted .sh ==="

SLUG_B="format-test-fmt-$$"
build_fixture "${SLUG_B}" stage_misformatted_sh

commits_before_b=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
exit_b=$(run_format_runner "${SLUG_B}")
commits_after_b=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
result_b="$(cat "${FIXTURE_WORKTREE}/formatting/result.txt" 2>/dev/null || true)"
head_subject_b=$(git -C "${FIXTURE_WORKTREE}" log -1 --format='%s')
fmt_diff_b=$(shfmt -i 2 -d "${FIXTURE_WORKTREE}/scripts/badfmt.sh" || true)

assert_eq "(b) runner exits 0" "0" "${exit_b}"
assert_contains "(b) result.txt carries PASS" "${result_b}" "PASS"
assert_eq "(b) exactly one new commit added" \
  "$((commits_before_b + 1))" "${commits_after_b}"
assert_contains "(b) new commit subject starts with chore:" \
  "${head_subject_b}" "chore:"
assert_eq "(b) badfmt.sh now passes shfmt -d" "" "${fmt_diff_b}"

# === Case (c): shellcheck-failing .sh — FAIL + lint output ========
echo ""
echo "=== Case (c): shellcheck-failing .sh ==="

SLUG_C="format-test-sc-$$"
build_fixture "${SLUG_C}" stage_shellcheck_broken_sh

commits_before_c=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
exit_c=$(run_format_runner "${SLUG_C}")
commits_after_c=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
result_c="$(cat "${FIXTURE_WORKTREE}/formatting/result.txt" 2>/dev/null || true)"

assert_nonzero "(c) runner exits non-zero on FAIL" "${exit_c}"
assert_contains "(c) result.txt begins with FAIL" "${result_c}" "FAIL"
assert_contains "(c) result.txt carries shellcheck output" \
  "${result_c}" "SC2068"
assert_eq "(c) no new commit on FAIL" \
  "${commits_before_c}" "${commits_after_c}"

# === Case (d): no .sh changed — PASS, no commit ===================
echo ""
echo "=== Case (d): no .sh files changed on branch ==="

SLUG_D="format-test-empty-$$"
build_fixture "${SLUG_D}" stage_no_sh_changed

commits_before_d=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
exit_d=$(run_format_runner "${SLUG_D}")
commits_after_d=$(git -C "${FIXTURE_WORKTREE}" rev-list --count HEAD)
result_d="$(cat "${FIXTURE_WORKTREE}/formatting/result.txt" 2>/dev/null || true)"

assert_eq "(d) runner exits 0" "0" "${exit_d}"
assert_contains "(d) result.txt carries PASS" "${result_d}" "PASS"
assert_eq "(d) no new commit when nothing to format" \
  "${commits_before_d}" "${commits_after_d}"

# === Summary ======================================================
echo ""
echo "================================"
echo "  PASS: ${PASS}  FAIL: ${FAIL}"
echo "================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
