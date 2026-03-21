#!/usr/bin/env bash
# End-to-end test for the GitHub Issues plan workflow.
#
# Exercises the full lifecycle:
#   1. plan-create.sh creates a GitHub Issue with plan:draft label
#   2. gh-plan-fetch.sh fetches the issue body back to a local file
#   3. gh-plan-sync.sh start  → label plan:active, start comment posted
#   4. gh-plan-sync.sh review → label plan:review, review comment posted
#   5. gh-plan-sync.sh ship   → label plan:completed, ship comment posted, issue closed
#
# Requirements:
#   - gh CLI authenticated (gh auth status)
#   - Issues enabled on the target repo
#
# Usage: bash tests/test-gh-plan-e2e.sh [--repo OWNER/REPO]
#
# The test creates a real GitHub Issue and cleans it up on exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
ISSUE_NUMBER=""
REPO=""
TEMP_DIR=""

# --- Parse args ---

while [[ $# -gt 0 ]]; do
	case "$1" in
	--repo)
		REPO="${2:?--repo requires a value}"
		shift 2
		;;
	*)
		echo "error: unknown option: $1" >&2
		echo "usage: test-gh-plan-e2e.sh [--repo OWNER/REPO]" >&2
		exit 1
		;;
	esac
done

# --- Helpers ---

check() {
	local id="$1"
	local description="$2"
	local expected="$3"
	local actual="$4"
	if [[ "${actual}" -eq "${expected}" ]]; then
		printf '  ok  %s: %s\n' "${id}" "${description}"
		PASS=$((PASS + 1))
	else
		printf '  FAIL %s: %s (expected %d, got %s)\n' \
			"${id}" "${description}" "${expected}" "${actual}"
		FAIL=$((FAIL + 1))
	fi
}

check_contains() {
	local id="$1"
	local description="$2"
	local pattern="$3"
	local output="$4"
	if [[ "${output}" == *"${pattern}"* ]]; then
		printf '  ok  %s: %s\n' "${id}" "${description}"
		PASS=$((PASS + 1))
	else
		printf '  FAIL %s: %s (expected output to contain "%s")\n' \
			"${id}" "${description}" "${pattern}"
		FAIL=$((FAIL + 1))
	fi
}

check_not_contains() {
	local id="$1"
	local description="$2"
	local pattern="$3"
	local output="$4"
	if [[ "${output}" != *"${pattern}"* ]]; then
		printf '  ok  %s: %s\n' "${id}" "${description}"
		PASS=$((PASS + 1))
	else
		printf '  FAIL %s: %s (output should NOT contain "%s")\n' \
			"${id}" "${description}" "${pattern}"
		FAIL=$((FAIL + 1))
	fi
}

get_issue_labels() {
	gh issue view "${ISSUE_NUMBER}" --repo "${REPO}" \
		--json labels -q '[.labels[].name] | join(",")'
}

get_issue_state() {
	gh issue view "${ISSUE_NUMBER}" --repo "${REPO}" \
		--json state -q '.state'
}

get_issue_comments() {
	gh issue view "${ISSUE_NUMBER}" --repo "${REPO}" \
		--json comments -q '[.comments[].body] | join("\n---\n")'
}

# --- Cleanup on exit ---

cleanup() {
	if [[ -n "${ISSUE_NUMBER}" ]]; then
		echo "Cleaning up: closing and locking test issue #${ISSUE_NUMBER}..." >&2
		gh issue close "${ISSUE_NUMBER}" --repo "${REPO}" 2>/dev/null || true
		gh issue lock "${ISSUE_NUMBER}" --repo "${REPO}" 2>/dev/null || true
	fi
	if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
		rm -rf "${TEMP_DIR}"
	fi
}
trap cleanup EXIT

# --- Preflight ---

printf 'gh-plan-e2e\n'
printf '  Preflight checks...\n'

if ! command -v gh &>/dev/null; then
	echo "SKIP: gh CLI not installed" >&2
	exit 0
fi

if ! gh auth status &>/dev/null; then
	echo "SKIP: gh not authenticated (run: gh auth login)" >&2
	exit 0
fi

# Resolve repo: --repo flag > dega-core.yaml > git remote
if [[ -z "${REPO}" ]]; then
	cd "${REPO_ROOT}"
	# shellcheck source=scripts/read-github-config.sh
	source "${REPO_ROOT}/scripts/read-github-config.sh"
	REPO="$(gh_resolve_repo "")"
fi

printf '  Using repo: %s\n' "${REPO}"

# Create temp working directory for fetched plan files
TEMP_DIR="$(mktemp -d)"
SLUG="e2e-test-$$-$(date +%s)"

# --- Plan content for the test issue ---

PLAN_BODY="$(
	cat <<'PLAN'
# Plan: E2E Test Plan

**Status:** Draft
**Created:** 2026-03-20

## Requirements

- This is a test plan created by test-gh-plan-e2e.sh
- It verifies the full GitHub Issues plan lifecycle

## Approach

Automated test — no real work to do.

## Progress log

- [ ] Step 1 — first task
- [ ] Step 2 — second task (deps: 1)

## Completion criteria

- [ ] Both steps marked done
PLAN
)"

# ============================================================
# Test 1: plan-create.sh creates an issue with plan:draft label
# ============================================================

printf '\n  --- Step 1: plan-create.sh ---\n'

exit_code=0
ISSUE_NUMBER="$(bash "${REPO_ROOT}/scripts/plan-create.sh" \
	--title "[E2E Test] ${SLUG}" \
	--body "${PLAN_BODY}" \
	--repo "${REPO}" 2>/dev/null)" || exit_code=$?

check create-exit \
	"plan-create.sh exits 0" \
	0 "${exit_code}"

# Validate issue number is numeric
if [[ "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
	printf '  ok  create-number: issue number is numeric (%s)\n' "${ISSUE_NUMBER}"
	PASS=$((PASS + 1))
else
	printf '  FAIL create-number: expected numeric issue number, got "%s"\n' "${ISSUE_NUMBER}"
	FAIL=$((FAIL + 1))
	echo "ABORT: cannot continue without a valid issue number" >&2
	exit 1
fi

# Check label is plan:draft
labels="$(get_issue_labels)"
check_contains create-label \
	"issue has plan:draft label" \
	"plan:draft" "${labels}"

# Check issue state is OPEN
state="$(get_issue_state)"
check_contains create-state \
	"issue is OPEN after creation" \
	"OPEN" "${state}"

# ============================================================
# Test 2: gh-plan-fetch.sh fetches the issue body
# ============================================================

printf '\n  --- Step 2: gh-plan-fetch.sh ---\n'

exit_code=0
cd "${TEMP_DIR}"
bash "${REPO_ROOT}/scripts/gh-plan-fetch.sh" \
	"${ISSUE_NUMBER}" "${SLUG}" \
	--repo "${REPO}" >/dev/null 2>&1 || exit_code=$?

check fetch-exit \
	"gh-plan-fetch.sh exits 0" \
	0 "${exit_code}"

fetched_plan="${TEMP_DIR}/.orchestrator/plans/${SLUG}/plan.md"
if [[ -f "${fetched_plan}" ]]; then
	printf '  ok  fetch-file: plan.md written to expected path\n'
	PASS=$((PASS + 1))
else
	printf '  FAIL fetch-file: expected %s to exist\n' "${fetched_plan}"
	FAIL=$((FAIL + 1))
fi

# Verify fetched content matches what we sent
if [[ -f "${fetched_plan}" ]]; then
	fetched_body="$(cat "${fetched_plan}")"
	check_contains fetch-content \
		"fetched plan contains progress log" \
		"Step 1" "${fetched_body}"
	check_contains fetch-content-2 \
		"fetched plan contains completion criteria" \
		"Completion criteria" "${fetched_body}"
fi

cd "${REPO_ROOT}"

# ============================================================
# Test 3: gh-plan-sync.sh start — label active, comment posted
# ============================================================

printf '\n  --- Step 3: gh-plan-sync.sh start ---\n'

exit_code=0
bash "${REPO_ROOT}/scripts/gh-plan-sync.sh" \
	start "${SLUG}" \
	--issue "${ISSUE_NUMBER}" \
	--repo "${REPO}" \
	--items 2 \
	--max-workers 1 >/dev/null 2>&1 || exit_code=$?

check start-exit \
	"gh-plan-sync.sh start exits 0" \
	0 "${exit_code}"

labels="$(get_issue_labels)"
check_contains start-label \
	"label is plan:active after start" \
	"plan:active" "${labels}"
check_not_contains start-no-draft \
	"plan:draft removed after start" \
	"plan:draft" "${labels}"

comments="$(get_issue_comments)"
check_contains start-comment \
	"start comment mentions plan started" \
	"Plan started" "${comments}"
check_contains start-comment-items \
	"start comment mentions item count" \
	"2 items" "${comments}"

# ============================================================
# Test 4: gh-plan-sync.sh review — label review, comment posted
# ============================================================

printf '\n  --- Step 4: gh-plan-sync.sh review ---\n'

exit_code=0
bash "${REPO_ROOT}/scripts/gh-plan-sync.sh" \
	review "${SLUG}" \
	--issue "${ISSUE_NUMBER}" \
	--repo "${REPO}" \
	--item-id 1 \
	--item-desc "first task" \
	--item-result SHIP \
	--iterations 1 >/dev/null 2>&1 || exit_code=$?

check review-exit \
	"gh-plan-sync.sh review exits 0" \
	0 "${exit_code}"

labels="$(get_issue_labels)"
check_contains review-label \
	"label is plan:review after review" \
	"plan:review" "${labels}"
check_not_contains review-no-active \
	"plan:active removed after review" \
	"plan:active" "${labels}"

comments="$(get_issue_comments)"
check_contains review-comment \
	"review comment mentions item 1" \
	"Item 1" "${comments}"
check_contains review-comment-ship \
	"review comment contains SHIP result" \
	"SHIP" "${comments}"
check_contains review-comment-iter \
	"review comment mentions iteration count" \
	"1 iteration" "${comments}"

# ============================================================
# Test 5: gh-plan-sync.sh ship — label completed, comment, closed
# ============================================================

printf '\n  --- Step 5: gh-plan-sync.sh ship ---\n'

exit_code=0
bash "${REPO_ROOT}/scripts/gh-plan-sync.sh" \
	ship "${SLUG}" \
	--issue "${ISSUE_NUMBER}" \
	--repo "${REPO}" \
	--items 2 \
	--passed 2 \
	--rework-count 0 \
	--total-reviews 2 \
	--elapsed "1m 23s" >/dev/null 2>&1 || exit_code=$?

check ship-exit \
	"gh-plan-sync.sh ship exits 0" \
	0 "${exit_code}"

labels="$(get_issue_labels)"
check_contains ship-label \
	"label is plan:completed after ship" \
	"plan:completed" "${labels}"
check_not_contains ship-no-review \
	"plan:review removed after ship" \
	"plan:review" "${labels}"

state="$(get_issue_state)"
check_contains ship-closed \
	"issue is CLOSED after ship" \
	"CLOSED" "${state}"

comments="$(get_issue_comments)"
check_contains ship-comment \
	"ship comment mentions Plan SHIP" \
	"Plan SHIP" "${comments}"
check_contains ship-comment-passed \
	"ship comment mentions 2/2 items passed" \
	"2/2 items passed" "${comments}"
check_contains ship-comment-elapsed \
	"ship comment mentions elapsed time" \
	"1m 23s" "${comments}"

# ============================================================
# Summary
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
