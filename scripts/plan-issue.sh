#!/usr/bin/env bash
# Create a GitHub Issue for an execution plan and write plan-meta.json.
#
# Idempotent: if plan-meta.json already exists, prints the issue number
# and exits 0 without creating a duplicate.
#
# Usage: plan-issue.sh <slug>
#
# Requires:
#   - gh CLI authenticated
#   - dega-core.yaml with github.sync: true
#   - plan.md at docs/exec-plans/active/<slug>/plan.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# shellcheck source=ensure-gh.sh
source "${SCRIPT_DIR}/ensure-gh.sh"
# shellcheck source=read-github-config.sh
source "${SCRIPT_DIR}/read-github-config.sh"

# --- Parse args ---

SLUG="${1:-}"
if [[ -z "${SLUG}" ]]; then
  echo "error: usage: plan-issue.sh <slug>" >&2
  exit 1
fi

PLAN_DIR="${REPO_ROOT}/docs/exec-plans/active/${SLUG}"
PLAN_FILE="${PLAN_DIR}/plan.md"
PLAN_META_DIR="${REPO_ROOT}/.orchestrator/plans/${SLUG}"
PLAN_META_FILE="${PLAN_META_DIR}/plan-meta.json"

# --- Idempotency: if plan-meta.json exists, print issue number and exit ---

if [[ -f "${PLAN_META_FILE}" ]]; then
  existing_issue=$(jq -r '.issue_number // empty' "${PLAN_META_FILE}")
  if [[ -n "${existing_issue}" ]]; then
    echo "${existing_issue}"
    exit 0
  fi
fi

# --- Validate plan exists ---

if [[ ! -f "${PLAN_FILE}" ]]; then
  echo "error: plan not found: ${PLAN_FILE}" >&2
  exit 1
fi

# --- Check github.sync is enabled ---

if ! gh_config_bool sync; then
  echo "error: github.sync is not enabled in dega-core.yaml" >&2
  exit 1
fi

# --- Ensure gh is available and authenticated ---

ensure_gh
if ! gh auth status &>/dev/null; then
  echo "error: gh is not authenticated. Run: gh auth login" >&2
  exit 2
fi

# --- Extract plan title ---

plan_title=$(grep -m1 '^# Plan:' "${PLAN_FILE}" 2>/dev/null |
  sed 's/^# Plan:[[:space:]]*//' || true)
if [[ -z "${plan_title}" ]]; then
  plan_title="${SLUG}"
fi

# --- Create the issue ---

echo "plan-issue: creating GitHub Issue for plan '${SLUG}'..." >&2
issue_number=$("${SCRIPT_DIR}/plan-create.sh" \
  --title "${plan_title}" \
  --body-file "${PLAN_FILE}")

# --- Write plan-meta.json ---

mkdir -p "${PLAN_META_DIR}"
jq -n \
  --argjson issue "${issue_number}" \
  --arg repo "$(gh_resolve_repo "")" \
  --arg slug "${SLUG}" \
  --arg createdAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{
    issue_number: $issue,
    repo: $repo,
    slug: $slug,
    created_at: $createdAt
  }' >"${PLAN_META_FILE}"

echo "plan-issue: created issue #${issue_number}, wrote ${PLAN_META_FILE}" >&2
echo "${issue_number}"
