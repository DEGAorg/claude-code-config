#!/usr/bin/env bash
# Integration test for orchestrator auto-issue creation and lifecycle sync.
#
# Verifies:
#   1. plan-create.sh creates an issue with plan:draft label (simulates orch-run.sh)
#   2. plan-meta.json written correctly (simulates orch-run.sh)
#   3. gh-plan-sync.sh auto-discovers issue from plan-meta.json (no --issue flag)
#   4. Labels update through lifecycle: draft → active → review → completed
#   5. Issue closed on SHIP when close_on_ship: true
#   6. 01-gh-plan-sync.sh lifecycle hook reads issueNumber from state.json
#   7. Without plan-meta.json or --issue, gh-plan-sync.sh errors gracefully
#   8. shellcheck and shfmt clean on all touched scripts
#
# Requirements:
#   - gh CLI authenticated (gh auth status)
#   - Issues enabled on the target repo
#   - dega-core.yaml with github.sync: true at repo root
#
# Usage: bash tests/test-orch-auto-issue.sh [--repo OWNER/REPO]
#
# Creates a real GitHub Issue, cleans up on exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
ISSUE_NUMBER=""
REPO=""
TEMP_ORCH_DIR=""

# --- Parse args ---

while [[ $# -gt 0 ]]; do
	case "$1" in
	--repo)
		REPO="${2:?--repo requires a value}"
		shift 2
		;;
	*)
		echo "error: unknown option: $1" >&2
		echo "usage: test-orch-auto-issue.sh [--repo OWNER/REPO]" >&2
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
	if [[ -n "${TEMP_ORCH_DIR}" && -d "${TEMP_ORCH_DIR}" ]]; then
		rm -rf "${TEMP_ORCH_DIR}"
	fi
}
trap cleanup EXIT

# --- Preflight ---

printf 'orch-auto-issue\n'
printf '  Preflight checks...\n'

if ! command -v gh &>/dev/null; then
	echo "SKIP: gh CLI not installed" >&2
	exit 0
fi

if ! gh auth status &>/dev/null; then
	echo "SKIP: gh not authenticated (run: gh auth login)" >&2
	exit 0
fi

if ! command -v jq &>/dev/null; then
	echo "SKIP: jq not installed" >&2
	exit 0
fi

# Resolve repo
if [[ -z "${REPO}" ]]; then
	cd "${REPO_ROOT}"
	# shellcheck source=../scripts/read-github-config.sh
	source "${REPO_ROOT}/scripts/read-github-config.sh"
	REPO="$(gh_resolve_repo "")"
fi

printf '  Using repo: %s\n' "${REPO}"

SLUG="auto-issue-test-$$-$(date +%s)"

# ============================================================
# Test 1: Simulate orch-run.sh auto-issue creation
# ============================================================

printf '\n  --- Step 1: Auto-create issue (simulating orch-run.sh) ---\n'

PLAN_BODY="$(
	cat <<'PLAN'
# Plan: Auto-Issue Test Plan

**Status:** Draft
**Created:** 2026-03-20

## Requirements

- Test plan created by test-orch-auto-issue.sh
- Verifies auto-issue creation and lifecycle sync

## Approach

Automated test — no real work to do.

## Progress log

- [ ] Task A — first item
- [ ] Task B — second item (deps: 1)

## Completion criteria

- [ ] Both tasks marked done
PLAN
)"

# Create the issue (what orch-run.sh does via plan-create.sh)
exit_code=0
ISSUE_NUMBER="$(bash "${REPO_ROOT}/scripts/plan-create.sh" \
	--title "[Auto-Issue Test] ${SLUG}" \
	--body "${PLAN_BODY}" \
	--repo "${REPO}" 2>/dev/null)" || exit_code=$?

check create-exit \
	"plan-create.sh exits 0" \
	0 "${exit_code}"

if [[ ! "${ISSUE_NUMBER}" =~ ^[0-9]+$ ]]; then
	printf '  FAIL create-number: expected numeric issue number, got "%s"\n' \
		"${ISSUE_NUMBER}"
	FAIL=$((FAIL + 1))
	echo "ABORT: cannot continue without a valid issue number" >&2
	exit 1
fi
printf '  ok  create-number: issue number is numeric (%s)\n' "${ISSUE_NUMBER}"
PASS=$((PASS + 1))

# Verify plan:draft label at creation
labels="$(get_issue_labels)"
check_contains create-draft-label \
	"issue has plan:draft label at creation" \
	"plan:draft" "${labels}"

# Write plan-meta.json (what orch-run.sh does after plan-create.sh)
TEMP_ORCH_DIR="$(mktemp -d)"
PLAN_META_DIR="${TEMP_ORCH_DIR}/.orchestrator/plans/${SLUG}"
mkdir -p "${PLAN_META_DIR}"

PLAN_META_FILE="${PLAN_META_DIR}/plan-meta.json"
jq -n \
	--argjson issue "${ISSUE_NUMBER}" \
	--arg repo "${REPO}" \
	--arg slug "${SLUG}" \
	--arg createdAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
	'{
		issue_number: $issue,
		repo: $repo,
		slug: $slug,
		created_at: $createdAt
	}' >"${PLAN_META_FILE}"

# Verify plan-meta.json content
meta_issue=$(jq -r '.issue_number' "${PLAN_META_FILE}")
meta_repo=$(jq -r '.repo' "${PLAN_META_FILE}")
meta_slug=$(jq -r '.slug' "${PLAN_META_FILE}")

check meta-issue \
	"plan-meta.json has correct issue number" \
	"${ISSUE_NUMBER}" "${meta_issue}"
check_contains meta-repo \
	"plan-meta.json has correct repo" \
	"${REPO}" "${meta_repo}"
check_contains meta-slug \
	"plan-meta.json has correct slug" \
	"${SLUG}" "${meta_slug}"

# ============================================================
# Test 2: gh-plan-sync.sh auto-discovers issue from plan-meta.json
# ============================================================

printf '\n  --- Step 2: gh-plan-sync.sh start (auto-discover from plan-meta.json) ---\n'

# Copy plan-meta.json into repo's .orchestrator dir for auto-discovery
REAL_META_DIR="${REPO_ROOT}/.orchestrator/plans/${SLUG}"
mkdir -p "${REAL_META_DIR}"
cp "${PLAN_META_FILE}" "${REAL_META_DIR}/plan-meta.json"

# gh-plan-sync.sh start WITHOUT --issue (should auto-discover from plan-meta.json)
exit_code=0
cd "${REPO_ROOT}"
output="$(bash "${REPO_ROOT}/scripts/gh-plan-sync.sh" \
	start "${SLUG}" \
	--repo "${REPO}" \
	--items 2 \
	--max-workers 1 2>&1)" || exit_code=$?

check start-exit \
	"gh-plan-sync.sh start exits 0 (auto-discover)" \
	0 "${exit_code}"

labels="$(get_issue_labels)"
check_contains start-active-label \
	"label is plan:active after start" \
	"plan:active" "${labels}"
check_not_contains start-no-draft \
	"plan:draft removed after start" \
	"plan:draft" "${labels}"

comments="$(get_issue_comments)"
check_contains start-comment \
	"start comment posted" \
	"Plan started" "${comments}"

# ============================================================
# Test 3: gh-plan-sync.sh review (auto-discover)
# ============================================================

printf '\n  --- Step 3: gh-plan-sync.sh review (auto-discover) ---\n'

exit_code=0
output="$(bash "${REPO_ROOT}/scripts/gh-plan-sync.sh" \
	review "${SLUG}" \
	--repo "${REPO}" \
	--item-id 1 \
	--item-desc "first item" \
	--item-result SHIP \
	--iterations 1 2>&1)" || exit_code=$?

check review-exit \
	"gh-plan-sync.sh review exits 0 (auto-discover)" \
	0 "${exit_code}"

labels="$(get_issue_labels)"
check_contains review-label \
	"label is plan:review after review" \
	"plan:review" "${labels}"
check_not_contains review-no-active \
	"plan:active removed after review" \
	"plan:active" "${labels}"

# ============================================================
# Test 4: Lifecycle hook auto-discovers from state.json
# ============================================================

printf '\n  --- Step 4: 01-gh-plan-sync.sh lifecycle hook (state.json + plan-meta.json) ---\n'

# Write a minimal state.json with issueNumber (what orch-run.sh init_state writes)
STATE_FILE="${REAL_META_DIR}/state.json"
jq -n \
	--argjson issueNumber "${ISSUE_NUMBER}" \
	--arg plan "${SLUG}" \
	'{
		version: 1,
		plan: $plan,
		issueNumber: $issueNumber,
		items: [
			{ id: 1, description: "first item", iteration: 1, lastResult: "SHIP", status: "done" },
			{ id: 2, description: "second item", iteration: 0, lastResult: null, status: "queued" }
		]
	}' >"${STATE_FILE}"

# Call the lifecycle hook directly for review event
exit_code=0
output="$(bash "${REPO_ROOT}/hooks/orch-lifecycle/01-gh-plan-sync.sh" \
	review "${SLUG}" 2>&1)" || exit_code=$?

check hook-review-exit \
	"lifecycle hook review exits 0" \
	0 "${exit_code}"

# The hook should have posted a review comment for item 1 (which has lastResult)
comments="$(get_issue_comments)"
check_contains hook-review-comment \
	"lifecycle hook posted review comment for item 1" \
	"Item 1" "${comments}"

# ============================================================
# Test 5: gh-plan-sync.sh ship — label completed, issue closed
# ============================================================

printf '\n  --- Step 5: gh-plan-sync.sh ship (auto-discover, close issue) ---\n'

exit_code=0
output="$(bash "${REPO_ROOT}/scripts/gh-plan-sync.sh" \
	ship "${SLUG}" \
	--repo "${REPO}" \
	--items 2 \
	--passed 2 \
	--elapsed "0m 42s" 2>&1)" || exit_code=$?

check ship-exit \
	"gh-plan-sync.sh ship exits 0 (auto-discover)" \
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
check_contains ship-passed \
	"ship comment mentions 2/2 items passed" \
	"2/2 items passed" "${comments}"

# ============================================================
# Test 6: Without plan-meta.json, gh-plan-sync.sh fails gracefully
# ============================================================

printf '\n  --- Step 6: No plan-meta.json — graceful failure ---\n'

exit_code=0
output="$(bash "${REPO_ROOT}/scripts/gh-plan-sync.sh" \
	start "nonexistent-slug-$$" 2>&1)" || exit_code=$?

check no-meta-exit \
	"fails with exit 1 when no plan-meta.json" \
	1 "${exit_code}"
check_contains no-meta-msg \
	"error mentions --issue or plan-meta.json" \
	"--issue" "${output}"

# ============================================================
# Test 7: shellcheck and shfmt clean on all involved scripts
# ============================================================

printf '\n  --- Step 7: Lint checks ---\n'

SCRIPTS_TO_LINT=(
	"scripts/orch-run.sh"
	"scripts/gh-plan-sync.sh"
	"scripts/plan-create.sh"
	"scripts/read-github-config.sh"
	"hooks/orch-lifecycle/01-gh-plan-sync.sh"
)

if command -v shellcheck &>/dev/null; then
	for script in "${SCRIPTS_TO_LINT[@]}"; do
		exit_code=0
		shellcheck -x -e SC1091 "${REPO_ROOT}/${script}" >/dev/null 2>&1 || exit_code=$?
		check "shellcheck-$(basename "${script}" .sh)" \
			"shellcheck ${script}" \
			0 "${exit_code}"
	done
else
	printf '  skip shellcheck: not installed\n'
fi

if command -v shfmt &>/dev/null; then
	for script in "${SCRIPTS_TO_LINT[@]}"; do
		exit_code=0
		shfmt -d "${REPO_ROOT}/${script}" >/dev/null 2>&1 || exit_code=$?
		check "shfmt-$(basename "${script}" .sh)" \
			"shfmt ${script}" \
			0 "${exit_code}"
	done
else
	printf '  skip shfmt: not installed\n'
fi

# ============================================================
# Cleanup: remove test plan-meta.json from repo .orchestrator dir
# ============================================================

rm -rf "${REAL_META_DIR}"

# ============================================================
# Summary
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
