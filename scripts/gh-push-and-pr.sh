#!/usr/bin/env bash
# scripts/gh-push-and-pr.sh
#
# Push a worktree branch to origin and open a pull request, with race-aware
# handling of GitHub's read-replica propagation lag. Owns the full
# push -> propagation-poll -> diff-sanity -> PR-create -> issue-comment
# flow so callers (orch-engine, lifecycle hooks) get a single command and
# structured exit codes.
#
# Exit codes:
#   0  ok
#   1  PROPAGATION_TIMEOUT  — branch never propagated to remote
#   2  NO_COMMITS           — branch has no commits ahead of base
#   3  AUTH                 — auth or permissions failure
#   4  VALIDATION           — bad arguments or input
#   5  OTHER                — unclassified failure
#
# Stdout: PR URL on success.
# Stderr: <CLASS>: <details> on failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/providers/provider.sh"

EXIT_OK=0
EXIT_PROPAGATION_TIMEOUT=1
EXIT_NO_COMMITS=2
EXIT_AUTH=3
EXIT_VALIDATION=4
EXIT_OTHER=5

WORKTREE=""
BRANCH=""
BASE=""
TITLE=""
BODY_FILE=""
ISSUE=""
PLAN_SLUG=""
PROPAGATION_TIMEOUT=30
CREATE_RETRIES=3
CREATE_BACKOFF=3

usage() {
  cat >&2 <<EOF
Usage: $0 --worktree <path> --branch <branch> --base <branch> \\
          --title <string> --body-file <path> [--issue <N>] \\
          [--plan-slug <slug>] \\
          [--propagation-timeout <s>] [--create-retries <n>] \\
          [--create-backoff <s>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --worktree)
    WORKTREE="$2"
    shift 2
    ;;
  --branch)
    BRANCH="$2"
    shift 2
    ;;
  --base)
    BASE="$2"
    shift 2
    ;;
  --title)
    TITLE="$2"
    shift 2
    ;;
  --body-file)
    BODY_FILE="$2"
    shift 2
    ;;
  --issue)
    ISSUE="$2"
    shift 2
    ;;
  --plan-slug)
    PLAN_SLUG="$2"
    shift 2
    ;;
  --propagation-timeout)
    PROPAGATION_TIMEOUT="$2"
    shift 2
    ;;
  --create-retries)
    CREATE_RETRIES="$2"
    shift 2
    ;;
  --create-backoff)
    CREATE_BACKOFF="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit "${EXIT_OK}"
    ;;
  *)
    echo "VALIDATION: unknown arg: $1" >&2
    exit "${EXIT_VALIDATION}"
    ;;
  esac
done

for v in WORKTREE BRANCH BASE TITLE BODY_FILE; do
  if [[ -z "${!v}" ]]; then
    echo "VALIDATION: --${v,,} required" >&2
    exit "${EXIT_VALIDATION}"
  fi
done

if [[ ! -f "${BODY_FILE}" ]]; then
  echo "VALIDATION: body file not found: ${BODY_FILE}" >&2
  exit "${EXIT_VALIDATION}"
fi

# --- Working files ---
PUSH_ERR_FILE="$(mktemp)"
PR_ERR_FILE="$(mktemp)"
trap 'rm -f "${PUSH_ERR_FILE}" "${PR_ERR_FILE}"' EXIT

# --- 1. Push (no retry) ---
set +e
git -C "${WORKTREE}" push -u origin "${BRANCH}" 2>"${PUSH_ERR_FILE}"
push_rc=$?
set -e

if ((push_rc != 0)); then
  push_err="$(cat "${PUSH_ERR_FILE}")"
  case "${push_err}" in
  *"Authentication"* | *"Permission denied"* | *"401"* | *"403"* | *"could not read Username"*)
    echo "AUTH: git push failed: ${push_err}" >&2
    exit "${EXIT_AUTH}"
    ;;
  *)
    echo "OTHER: git push failed (rc=${push_rc}): ${push_err}" >&2
    exit "${EXIT_OTHER}"
    ;;
  esac
fi

# --- 2. Repo discovery ---
REPO=""
if ! REPO="$(cd "${WORKTREE}" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
  echo "OTHER: failed to discover repo from worktree ${WORKTREE}" >&2
  exit "${EXIT_OTHER}"
fi
if [[ -z "${REPO}" ]]; then
  echo "OTHER: empty repo name from gh repo view in ${WORKTREE}" >&2
  exit "${EXIT_OTHER}"
fi

# --- 3. Propagation poll ---
LOCAL_SHA="$(git -C "${WORKTREE}" rev-parse "${BRANCH}")"
elapsed=0
attempt=0
matched=false
while ((elapsed < PROPAGATION_TIMEOUT)); do
  remote_sha="$(gh api "repos/${REPO}/branches/${BRANCH}" --jq .commit.sha 2>/dev/null || true)"
  if [[ -n "${remote_sha}" && "${remote_sha}" == "${LOCAL_SHA}" ]]; then
    matched=true
    break
  fi
  attempt=$((attempt + 1))
  sleep_s=$((attempt < 5 ? attempt : 5))
  if ((elapsed + sleep_s >= PROPAGATION_TIMEOUT)); then
    break
  fi
  sleep "${sleep_s}"
  elapsed=$((elapsed + sleep_s))
done

if [[ "${matched}" != true ]]; then
  echo "PROPAGATION_TIMEOUT: branch ${BRANCH} did not propagate to ${REPO} within ${PROPAGATION_TIMEOUT}s" >&2
  exit "${EXIT_PROPAGATION_TIMEOUT}"
fi

# --- 4. Diff sanity ---
AHEAD_BY="$(gh api "repos/${REPO}/compare/${BASE}...${BRANCH}" --jq .ahead_by 2>/dev/null || echo 0)"
if ! [[ "${AHEAD_BY}" =~ ^[0-9]+$ ]]; then
  AHEAD_BY=0
fi
if ((AHEAD_BY < 1)); then
  echo "NO_COMMITS: branch ${BRANCH} has no commits ahead of ${BASE}" >&2
  exit "${EXIT_NO_COMMITS}"
fi

# --- 5. PR create with classified retry ---
BODY="$(cat "${BODY_FILE}")"
attempts_total=$((CREATE_RETRIES + 1))
i=0
PR_URL=""
last_err=""
while ((i < attempts_total)); do
  i=$((i + 1))
  : >"${PR_ERR_FILE}"
  set +e
  out="$(provider_pr_create \
    --title "${TITLE}" \
    --body "${BODY}" \
    --base "${BASE}" \
    --head "${BRANCH}" 2>"${PR_ERR_FILE}")"
  pr_rc=$?
  set -e
  err_out="$(cat "${PR_ERR_FILE}")"
  if ((pr_rc == 0)); then
    PR_URL="${out}"
    break
  fi
  last_err="${err_out}"
  case "${err_out}" in
  *"HTTP 401"* | *"HTTP 403"* | *"Bad credentials"* | *"Requires authentication"* | *"Permission denied"* | *"must have admin rights"*)
    echo "AUTH: ${err_out}" >&2
    exit "${EXIT_AUTH}"
    ;;
  *"Head sha can't be blank"* | *"Base sha can't be blank"* | *"No commits between"* | *"Head ref must be a branch"* | *"Base ref must be a branch"*)
    if ((i < attempts_total)); then
      sleep_s=$((i * CREATE_BACKOFF))
      if ((sleep_s > 0)); then
        sleep "${sleep_s}"
      fi
      continue
    fi
    echo "OTHER: PR create exhausted ${CREATE_RETRIES} retries on transient class: ${err_out}" >&2
    exit "${EXIT_OTHER}"
    ;;
  *"Validation Failed"* | *"Unprocessable Entity"* | *"422"*)
    echo "VALIDATION: ${err_out}" >&2
    exit "${EXIT_VALIDATION}"
    ;;
  *)
    echo "OTHER: PR create failed: ${err_out}" >&2
    exit "${EXIT_OTHER}"
    ;;
  esac
done

if [[ -z "${PR_URL}" ]]; then
  echo "OTHER: PR create returned no URL: ${last_err}" >&2
  exit "${EXIT_OTHER}"
fi

printf '%s\n' "${PR_URL}"

# --- 6. Optional issue comment (idempotent via posted.json) ---
#
# Mirrors the pattern used by hooks/orch-lifecycle/01-gh-plan-sync.sh:
# a JSON object keyed by "<plan-slug>:pr-link" records that the comment
# was posted. The key is written only after provider_issue_comment exits
# 0, so a transient failure leaves the key absent and the next run
# retries.
if [[ -n "${ISSUE}" ]]; then
  if [[ -z "${PLAN_SLUG}" ]]; then
    PLAN_SLUG="$(basename "${WORKTREE}")"
  fi
  POSTED_JSON="${ORCH_STATE_DIR:-.orchestrator}/posted.json"
  POSTED_LOCK="${POSTED_JSON}.lock"
  POSTED_KEY="${PLAN_SLUG}:pr-link"

  already_posted=false
  if [[ -f "${POSTED_JSON}" ]] &&
    jq -e --arg k "${POSTED_KEY}" 'has($k)' "${POSTED_JSON}" >/dev/null 2>&1; then
    already_posted=true
  fi

  if [[ "${already_posted}" != true ]]; then
    if provider_issue_comment --issue "${ISSUE}" --body "PR created: ${PR_URL}" >/dev/null 2>&1; then
      mkdir -p "$(dirname "${POSTED_JSON}")"
      (
        if command -v flock >/dev/null 2>&1; then
          flock 9 || true
        fi
        existing='{}'
        if [[ -s "${POSTED_JSON}" ]]; then
          existing="$(cat "${POSTED_JSON}")"
        fi
        now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '%s' "${existing}" |
          jq --arg k "${POSTED_KEY}" --arg t "${now}" \
            '. + {($k): {"postedAt": $t}}' \
            >"${POSTED_JSON}.tmp"
        mv "${POSTED_JSON}.tmp" "${POSTED_JSON}"
      ) 9>"${POSTED_LOCK}"
    else
      echo "OTHER: failed to post issue comment on #${ISSUE}" >&2
    fi
  fi
fi

exit "${EXIT_OK}"
