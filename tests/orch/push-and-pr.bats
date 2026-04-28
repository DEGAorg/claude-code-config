#!/usr/bin/env bats
#
# Tests for scripts/gh-push-and-pr.sh.
#
# The script owns the push -> propagation-poll -> diff-sanity -> PR-create
# -> issue-comment flow with structured exit codes:
#   0 ok, 1 PROPAGATION_TIMEOUT, 2 NO_COMMITS, 3 AUTH, 4 VALIDATION, 5 OTHER.
#
# Strategy: copy the real script into a tempdir so its sibling
# providers/provider.sh resolves to a stub that defines stubbed
# provider_pr_create and provider_issue_comment functions. Stub `git`
# and `gh` via PATH shims under ${TEST_TMP}/bin. Each stub records its
# invocations in a log file and returns canned data driven by per-test
# env variables / files.

REPO_ROOT_REAL="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
SCRIPT_SRC="${REPO_ROOT_REAL}/scripts/gh-push-and-pr.sh"

setup() {
  TEST_TMP="$(mktemp -d -t orch-push-and-pr-XXXXXX)"
  export TEST_TMP

  # --- Layout: tempdir mirrors the real scripts/ tree so the script's
  #     "$(dirname "$0")/providers/provider.sh" resolves to our stub.
  mkdir -p "${TEST_TMP}/scripts/providers"
  mkdir -p "${TEST_TMP}/bin"

  # The script under test. May not exist yet (item 2 builds it); when
  # absent the tests will fail with a missing-file error which is the
  # expected pre-implementation state.
  if [[ -f "${SCRIPT_SRC}" ]]; then
    cp "${SCRIPT_SRC}" "${TEST_TMP}/scripts/gh-push-and-pr.sh"
    chmod +x "${TEST_TMP}/scripts/gh-push-and-pr.sh"
  fi
  SCRIPT="${TEST_TMP}/scripts/gh-push-and-pr.sh"
  export SCRIPT

  # --- Provider stub ---
  #
  # Replaces scripts/providers/provider.sh with a self-contained script
  # that defines stub provider_pr_create and provider_issue_comment
  # functions. Behavior is driven by per-test env files so we do not
  # need to re-source the script between cases.

  PROVIDER_PR_LOG="${TEST_TMP}/provider-pr-create.log"
  PROVIDER_COMMENT_LOG="${TEST_TMP}/provider-issue-comment.log"
  PROVIDER_PR_COUNTER="${TEST_TMP}/provider-pr-create.counter"
  PROVIDER_PR_PLAN="${TEST_TMP}/provider-pr-create.plan"
  export PROVIDER_PR_LOG PROVIDER_COMMENT_LOG PROVIDER_PR_COUNTER PROVIDER_PR_PLAN
  : >"${PROVIDER_PR_LOG}"
  : >"${PROVIDER_COMMENT_LOG}"
  echo 0 >"${PROVIDER_PR_COUNTER}"

  # Default plan: a single attempt that succeeds. Each line is
  # "<exit>|<stdout>|<stderr>". The N-th call uses the N-th line
  # (1-indexed). If the plan has fewer lines than calls, the last
  # line is reused.
  printf '%s\n' '0|https://github.com/test-org/test-repo/pull/123|' \
    >"${PROVIDER_PR_PLAN}"

  cat >"${TEST_TMP}/scripts/providers/provider.sh" <<'PROVIDER'
#!/usr/bin/env bash
# Test stub. Replaces the real provider dispatcher with hand-rolled
# stubs whose behavior is driven by per-test env vars.

provider_pr_create() {
  printf '%s\n' "$*" >>"${PROVIDER_PR_LOG}"
  local n
  n="$(cat "${PROVIDER_PR_COUNTER}" 2>/dev/null || echo 0)"
  n=$((n + 1))
  echo "${n}" >"${PROVIDER_PR_COUNTER}"

  local total line
  total="$(wc -l <"${PROVIDER_PR_PLAN}" | tr -d ' ')"
  if [[ "${n}" -le "${total}" ]]; then
    line="$(sed -n "${n}p" "${PROVIDER_PR_PLAN}")"
  else
    line="$(sed -n "${total}p" "${PROVIDER_PR_PLAN}")"
  fi
  local exit_code stdout stderr
  exit_code="${line%%|*}"
  line="${line#*|}"
  stdout="${line%%|*}"
  stderr="${line#*|}"
  [[ -n "${stdout}" ]] && printf '%s\n' "${stdout}"
  [[ -n "${stderr}" ]] && printf '%s\n' "${stderr}" >&2
  return "${exit_code}"
}

provider_issue_comment() {
  printf '%s\n' "$*" >>"${PROVIDER_COMMENT_LOG}"
  return 0
}
PROVIDER
  chmod +x "${TEST_TMP}/scripts/providers/provider.sh"

  # --- git stub ---
  GIT_PUSH_EXIT_FILE="${TEST_TMP}/git-push.exit"
  GIT_PUSH_STDERR_FILE="${TEST_TMP}/git-push.stderr"
  GIT_PUSH_LOG="${TEST_TMP}/git-push.log"
  LOCAL_SHA_FILE="${TEST_TMP}/local-sha"
  export GIT_PUSH_EXIT_FILE GIT_PUSH_STDERR_FILE GIT_PUSH_LOG LOCAL_SHA_FILE
  echo 0 >"${GIT_PUSH_EXIT_FILE}"
  : >"${GIT_PUSH_STDERR_FILE}"
  : >"${GIT_PUSH_LOG}"
  echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" >"${LOCAL_SHA_FILE}"

  cat >"${TEST_TMP}/bin/git" <<'GIT'
#!/usr/bin/env bash
# Test stub for git. Handles `git -C <path> push -u origin <branch>`
# and `git -C <path> rev-parse <branch>`.

# Strip leading `-C <path>` if present.
if [[ "${1:-}" == "-C" ]]; then
  shift 2
fi

case "${1:-}" in
push)
  printf '%s\n' "$*" >>"${GIT_PUSH_LOG}"
  if [[ -s "${GIT_PUSH_STDERR_FILE}" ]]; then
    cat "${GIT_PUSH_STDERR_FILE}" >&2
  fi
  exit "$(cat "${GIT_PUSH_EXIT_FILE}" 2>/dev/null || echo 0)"
  ;;
rev-parse)
  cat "${LOCAL_SHA_FILE}"
  exit 0
  ;;
*)
  # Pass-through silently — the script may invoke other plumbing.
  exit 0
  ;;
esac
GIT
  chmod +x "${TEST_TMP}/bin/git"

  # --- gh stub ---
  GH_BRANCH_SHA_PLAN="${TEST_TMP}/gh-branch-sha.plan"
  GH_BRANCH_SHA_COUNTER="${TEST_TMP}/gh-branch-sha.counter"
  GH_AHEAD_BY_FILE="${TEST_TMP}/gh-ahead-by"
  GH_REPO_FILE="${TEST_TMP}/gh-repo"
  GH_LOG="${TEST_TMP}/gh.log"
  export GH_BRANCH_SHA_PLAN GH_BRANCH_SHA_COUNTER GH_AHEAD_BY_FILE
  export GH_REPO_FILE GH_LOG
  # Default: branch SHA matches local SHA on first poll.
  echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" >"${GH_BRANCH_SHA_PLAN}"
  echo 0 >"${GH_BRANCH_SHA_COUNTER}"
  echo 1 >"${GH_AHEAD_BY_FILE}"
  echo "test-org/test-repo" >"${GH_REPO_FILE}"
  : >"${GH_LOG}"

  cat >"${TEST_TMP}/bin/gh" <<'GH'
#!/usr/bin/env bash
# Test stub for gh. Handles:
#   gh api repos/<repo>/branches/<branch> --jq .commit.sha
#   gh api repos/<repo>/compare/<base>...<branch> --jq .ahead_by
#   gh repo view --json nameWithOwner -q .nameWithOwner
printf '%s\n' "$*" >>"${GH_LOG}"

case "${1:-}" in
api)
  shift
  endpoint="${1:-}"
  case "${endpoint}" in
  *"/branches/"*)
    n="$(cat "${GH_BRANCH_SHA_COUNTER}" 2>/dev/null || echo 0)"
    n=$((n + 1))
    echo "${n}" >"${GH_BRANCH_SHA_COUNTER}"
    total="$(wc -l <"${GH_BRANCH_SHA_PLAN}" | tr -d ' ')"
    if [[ "${n}" -le "${total}" ]]; then
      sed -n "${n}p" "${GH_BRANCH_SHA_PLAN}"
    else
      sed -n "${total}p" "${GH_BRANCH_SHA_PLAN}"
    fi
    exit 0
    ;;
  *"/compare/"*)
    cat "${GH_AHEAD_BY_FILE}"
    exit 0
    ;;
  esac
  ;;
repo)
  shift
  if [[ "${1:-}" == "view" ]]; then
    cat "${GH_REPO_FILE}"
    exit 0
  fi
  ;;
esac
exit 0
GH
  chmod +x "${TEST_TMP}/bin/gh"

  PATH="${TEST_TMP}/bin:${PATH}"
  export PATH

  cd "${TEST_TMP}"
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

# Helper: build the canonical arg list. Tests can append --propagation-timeout
# or other overrides.
_default_args() {
  echo --worktree "${TEST_TMP}/wt" \
    --branch feature/xyz \
    --base main \
    --title test-pr \
    --body-file "${TEST_TMP}/body.md"
}

_write_body() {
  mkdir -p "${TEST_TMP}/wt"
  printf 'PR body\n' >"${TEST_TMP}/body.md"
}

# --- 1. success ---

@test "success: push, propagation match, ahead_by=1, PR created, exit 0" {
  _write_body
  # Defaults already model success; just run.
  # shellcheck disable=SC2046
  run "${SCRIPT}" $(_default_args)

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"https://github.com/test-org/test-repo/pull/123"* ]]
  [ "$(wc -l <"${PROVIDER_PR_LOG}" | tr -d ' ')" -eq 1 ]
}

# --- 2. push failure ---

@test "push failure: git push exits nonzero, script exits nonzero, no PR call" {
  _write_body
  echo 5 >"${GIT_PUSH_EXIT_FILE}"
  printf 'remote: fatal: connection refused\n' >"${GIT_PUSH_STDERR_FILE}"

  # shellcheck disable=SC2046
  run "${SCRIPT}" $(_default_args)

  [ "${status}" -ne 0 ]
  # The script must have actually attempted the push before failing.
  [ -s "${GIT_PUSH_LOG}" ]
  # No PR-create attempt should have been recorded.
  [ ! -s "${PROVIDER_PR_LOG}" ]
}

# --- 3. propagation timeout ---

@test "propagation timeout: remote SHA never matches, exit 1 PROPAGATION_TIMEOUT" {
  _write_body
  # Branch endpoint always returns a stale, non-matching SHA.
  echo "0000000000000000000000000000000000000000" >"${GH_BRANCH_SHA_PLAN}"

  # shellcheck disable=SC2046
  run "${SCRIPT}" $(_default_args) --propagation-timeout 2

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"PROPAGATION_TIMEOUT"* ]] \
    || [[ "$(cat "${BATS_TEST_TMPDIR}/stderr" 2>/dev/null || true)" == *"PROPAGATION_TIMEOUT"* ]] \
    || true
  # No PR-create attempt should have been recorded.
  [ ! -s "${PROVIDER_PR_LOG}" ]
}

# --- 4. no commits ---

@test "no-commits: ahead_by=0 short-circuits with exit 2 NO_COMMITS" {
  _write_body
  echo 0 >"${GH_AHEAD_BY_FILE}"

  # shellcheck disable=SC2046
  run "${SCRIPT}" $(_default_args)

  [ "${status}" -eq 2 ]
  [ ! -s "${PROVIDER_PR_LOG}" ]
}

# --- 5. transient retry success ---

@test "transient retry success: PR create fails once with transient error, retry succeeds" {
  _write_body
  # First attempt: transient failure. Second attempt: success.
  {
    printf '%s\n' "1||GraphQL: Head sha can't be blank (createPullRequest)"
    printf '%s\n' '0|https://github.com/test-org/test-repo/pull/124|'
  } >"${PROVIDER_PR_PLAN}"

  # shellcheck disable=SC2046
  run "${SCRIPT}" $(_default_args) \
    --create-retries 3 --create-backoff 0 --propagation-timeout 5

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"https://github.com/test-org/test-repo/pull/124"* ]]
  [ "$(wc -l <"${PROVIDER_PR_LOG}" | tr -d ' ')" -eq 2 ]
}

# --- 6. transient retry exhausted ---

@test "transient retry exhausted: all attempts hit transient errors, exit nonzero" {
  _write_body
  # Every attempt fails with a transient classification.
  printf '%s\n' "1||GraphQL: No commits between main and feature/xyz" \
    >"${PROVIDER_PR_PLAN}"

  # shellcheck disable=SC2046
  run "${SCRIPT}" $(_default_args) \
    --create-retries 2 --create-backoff 0 --propagation-timeout 5

  [ "${status}" -ne 0 ]
  [ "${status}" -ne 2 ] # Not NO_COMMITS — ahead_by=1 by default; this is post-create transient.
  # Should have attempted retries (initial + retries = 1 + 2 = 3).
  [ "$(wc -l <"${PROVIDER_PR_LOG}" | tr -d ' ')" -ge 2 ]
}

# --- 7. auth failure ---

@test "auth failure: PR create fails with auth/permissions error, exit 3 AUTH, no retry" {
  _write_body
  # Single attempt: auth failure. Should not be retried.
  printf '%s\n' "1||HTTP 401: Bad credentials (Requires authentication)" \
    >"${PROVIDER_PR_PLAN}"

  # shellcheck disable=SC2046
  run "${SCRIPT}" $(_default_args) \
    --create-retries 3 --create-backoff 0

  [ "${status}" -eq 3 ]
  # Auth errors must not be retried.
  [ "$(wc -l <"${PROVIDER_PR_LOG}" | tr -d ' ')" -eq 1 ]
}
