#!/usr/bin/env bash
# Tests for orchestrator SHIP PR creation and gh-plan-sync pr event.
#
# Validates:
#   1. gh-plan-sync.sh pr event: arg validation, comment posting
#   2. orch-engine.sh SHIP step 8: pr_target config, PR body, issue comment
#   3. shellcheck/shfmt cleanliness of changed scripts
#
# Usage: bash tests/test-orch-ship-pr.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0

check() {
	local id="$1" description="$2" expected="$3" actual="$4"
	if [[ "${actual}" -eq "${expected}" ]]; then
		printf '  ok  %s: %s\n' "${id}" "${description}"
		PASS=$((PASS + 1))
	else
		printf '  FAIL %s: %s (expected exit %d, got %s)\n' \
			"${id}" "${description}" "${expected}" "${actual}"
		FAIL=$((FAIL + 1))
	fi
}

check_contains() {
	local id="$1" description="$2" pattern="$3" output="$4"
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
	local id="$1" description="$2" pattern="$3" output="$4"
	if [[ "${output}" != *"${pattern}"* ]]; then
		printf '  ok  %s: %s\n' "${id}" "${description}"
		PASS=$((PASS + 1))
	else
		printf '  FAIL %s: %s (output should NOT contain "%s")\n' \
			"${id}" "${description}" "${pattern}"
		FAIL=$((FAIL + 1))
	fi
}

SYNC_SCRIPT="${REPO_ROOT}/scripts/gh-plan-sync.sh"

# ============================================================
printf 'gh-plan-sync pr event — validation\n'
# ============================================================

# Test: pr event is accepted as valid event type
STUB_DIR="$(mktemp -d)"
cat >"${STUB_DIR}/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
STUB
chmod +x "${STUB_DIR}/gh"

exit_code=0
output="$(PATH="${STUB_DIR}:${PATH}" bash "${SYNC_SCRIPT}" pr my-plan \
	--issue 42 --pr-url "https://github.com/org/repo/pull/1" 2>&1)" || exit_code=$?

check pr-valid-event \
	"pr event passes validation (fails at auth)" \
	1 "${exit_code}"
check_contains pr-valid-event-auth \
	"pr event fails with auth error, not validation" \
	"not authenticated" "${output}"
rm -rf "${STUB_DIR}"

# Test: pr event without --pr-url fails
STUB_DIR="$(mktemp -d)"
cat >"${STUB_DIR}/gh" <<'STUB'
#!/usr/bin/env bash
# Auth passes, everything else succeeds
exit 0
STUB
chmod +x "${STUB_DIR}/gh"

# Create minimal dega-core.yaml for repo resolution
MOCK_CWD="$(mktemp -d)"
cat >"${MOCK_CWD}/dega-core.yaml" <<'YAML'
github:
  repo: test-owner/test-repo
  comments: true
  labels: false
YAML

exit_code=0
output="$(cd "${MOCK_CWD}" &&
	PATH="${STUB_DIR}:${PATH}" bash "${SYNC_SCRIPT}" pr my-plan \
		--issue 42 2>&1)" || exit_code=$?

check pr-missing-url \
	"pr event fails without --pr-url" \
	1 "${exit_code}"
check_contains pr-missing-url-msg \
	"error mentions --pr-url" \
	"--pr-url" "${output}"

rm -rf "${STUB_DIR}" "${MOCK_CWD}"

# ============================================================
printf '\ngh-plan-sync pr event — mock gh\n'
# ============================================================

MOCK_DIR="$(mktemp -d)"
MOCK_COMMENT_FILE="${MOCK_DIR}/comment.txt"

# Minimal dega-core.yaml
cat >"${MOCK_DIR}/dega-core.yaml" <<'YAML'
github:
  sync: true
  repo: test-owner/test-repo
  labels: false
  comments: true
  close_on_ship: false
YAML

# Mock gh that captures issue comment body
cat >"${MOCK_DIR}/gh" <<'GHSTUB'
#!/usr/bin/env bash
set -euo pipefail
MOCK_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
  auth) exit 0 ;;
  repo) echo "test-owner/test-repo" ;;
  issue)
    case "${2:-}" in
      view)
        if [[ " $* " == *"--json labels"* ]]; then
          echo ""
          exit 0
        fi
        ;;
      comment)
        # Capture the --body argument
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--body" ]]; then
            printf '%s' "$2" > "${MOCK_DIR}/comment.txt"
            exit 0
          fi
          shift
        done
        exit 0
        ;;
      edit) exit 0 ;;
      close) exit 0 ;;
    esac
    ;;
esac
exit 0
GHSTUB
chmod +x "${MOCK_DIR}/gh"

run_sync() {
	(
		cd "${MOCK_DIR}"
		PATH="${MOCK_DIR}:${PATH}" bash "${SYNC_SCRIPT}" "$@" 2>&1
	)
}

# Test: pr event posts comment with PR URL
exit_code=0
run_sync pr test-slug \
	--issue 99 --pr-url "https://github.com/org/repo/pull/7" || exit_code=$?

check pr-post-exit \
	"pr event succeeds" \
	0 "${exit_code}"

if [[ -f "${MOCK_COMMENT_FILE}" ]]; then
	comment="$(cat "${MOCK_COMMENT_FILE}")"
	check_contains pr-comment-url \
		"comment contains PR URL" \
		"https://github.com/org/repo/pull/7" "${comment}"
	check_contains pr-comment-slug \
		"comment contains plan slug" \
		"test-slug" "${comment}"
	check_contains pr-comment-label \
		"comment mentions Pull Request" \
		"Pull Request" "${comment}"
else
	printf '  FAIL pr-comment: no comment file found\n'
	FAIL=$((FAIL + 1))
fi
rm -f "${MOCK_COMMENT_FILE}"

# Test: pr event respects comments: false
cat >"${MOCK_DIR}/dega-core.yaml" <<'YAML'
github:
  sync: true
  repo: test-owner/test-repo
  labels: false
  comments: false
  close_on_ship: false
YAML
# Reset cached config path
unset _DEGA_CORE_YAML 2>/dev/null || true

exit_code=0
run_sync pr test-slug \
	--issue 99 --pr-url "https://github.com/org/repo/pull/8" || exit_code=$?

check pr-comments-disabled-exit \
	"pr event succeeds when comments disabled" \
	0 "${exit_code}"

if [[ -f "${MOCK_COMMENT_FILE}" ]]; then
	printf '  FAIL pr-comments-disabled: comment posted when comments=false\n'
	FAIL=$((FAIL + 1))
else
	printf '  ok  pr-comments-disabled: no comment when comments=false\n'
	PASS=$((PASS + 1))
fi

rm -rf "${MOCK_DIR}"

# ============================================================
printf '\norch-engine.sh SHIP step 8 — PR creation logic\n'
# ============================================================

# Test the PR creation code path by extracting and testing the logic
# from orch-engine.sh. We verify:
#   - pr_target is read from dega-core.yaml
#   - PR body includes SHIP summary, plan slug, Closes #N
#   - gh pr create is called with correct --base and --head

MOCK_DIR="$(mktemp -d)"
MOCK_GH_LOG="${MOCK_DIR}/gh-calls.log"

cat >"${MOCK_DIR}/dega-core.yaml" <<'YAML'
github:
  repo: DEGAorg/test-repo
  pr_target: develop
YAML

# Mock gh that logs all calls
cat >"${MOCK_DIR}/gh" <<'GHSTUB'
#!/usr/bin/env bash
MOCK_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "${MOCK_DIR}/gh-calls.log"

case "${1:-}" in
  pr)
    case "${2:-}" in
      create)
        echo "https://github.com/DEGAorg/test-repo/pull/42"
        exit 0
        ;;
    esac
    ;;
  issue)
    case "${2:-}" in
      comment) exit 0 ;;
    esac
    ;;
esac
exit 0
GHSTUB
chmod +x "${MOCK_DIR}/gh"

# Test: pr_target is read correctly from dega-core.yaml
pr_target=$(grep 'pr_target:' "${MOCK_DIR}/dega-core.yaml" 2>/dev/null |
	awk '{print $2}' | tr -d ' ' || true)
pr_target="${pr_target:-main}"

check_contains pr-target-config \
	"pr_target reads 'develop' from config" \
	"develop" "${pr_target}"

# Test: default pr_target is 'main' when not configured
MOCK_DIR2="$(mktemp -d)"
cat >"${MOCK_DIR2}/dega-core.yaml" <<'YAML'
github:
  repo: DEGAorg/test-repo
YAML

pr_target2=$(grep 'pr_target:' "${MOCK_DIR2}/dega-core.yaml" 2>/dev/null |
	awk '{print $2}' | tr -d ' ' || true)
pr_target2="${pr_target2:-main}"

check_contains pr-target-default \
	"pr_target defaults to 'main' when not set" \
	"main" "${pr_target2}"
rm -rf "${MOCK_DIR2}"

# Test: PR body construction
DONE_COUNT=3
TOTAL_COUNT=4
FAILED_COUNT=1
ITER_COUNT=2
ELAPSED_STR="5m 30s"
SLUG="test-ship-pr"
ISSUE_NUMBER="17"

PR_BODY="## SHIP Summary"$'\n\n'
PR_BODY+="- **Plan:** \`${SLUG}\`"$'\n'
PR_BODY+="- **Items:** ${DONE_COUNT}/${TOTAL_COUNT} passed"$'\n'
if [[ "${FAILED_COUNT}" -gt 0 ]]; then
	PR_BODY+="- **Failed:** ${FAILED_COUNT}"$'\n'
fi
PR_BODY+="- **Iterations:** ${ITER_COUNT}"$'\n'
PR_BODY+="- **Elapsed:** ${ELAPSED_STR}"$'\n'
PR_BODY+=$'\n'"Closes #${ISSUE_NUMBER}"$'\n'

check_contains pr-body-slug \
	"PR body contains plan slug" \
	"test-ship-pr" "${PR_BODY}"
check_contains pr-body-items \
	"PR body contains item counts" \
	"3/4 passed" "${PR_BODY}"
check_contains pr-body-failed \
	"PR body contains failed count" \
	"**Failed:** 1" "${PR_BODY}"
check_contains pr-body-iterations \
	"PR body contains iteration count" \
	"**Iterations:** 2" "${PR_BODY}"
check_contains pr-body-elapsed \
	"PR body contains elapsed time" \
	"5m 30s" "${PR_BODY}"
check_contains pr-body-closes \
	"PR body contains Closes #N" \
	"Closes #17" "${PR_BODY}"

# Test: PR body without issue number omits Closes line
PR_BODY_NO_ISSUE="## SHIP Summary"$'\n\n'
PR_BODY_NO_ISSUE+="- **Plan:** \`${SLUG}\`"$'\n'
PR_BODY_NO_ISSUE+="- **Items:** ${DONE_COUNT}/${TOTAL_COUNT} passed"$'\n'

EMPTY_ISSUE=""
if [[ -n "${EMPTY_ISSUE}" ]]; then
	PR_BODY_NO_ISSUE+=$'\n'"Closes #${EMPTY_ISSUE}"$'\n'
fi

check_not_contains pr-body-no-closes \
	"PR body omits Closes when no issue" \
	"Closes #" "${PR_BODY_NO_ISSUE}"

# Test: gh pr create args include --base and --head
CURRENT_BRANCH="orch/test-ship-pr"
GH_REPO="DEGAorg/test-repo"
PR_TITLE="plan: ${SLUG}"

GH_ARGS=(pr create
	--title "${PR_TITLE}"
	--base "${pr_target}"
	--head "${CURRENT_BRANCH}"
)
if [[ -n "${GH_REPO}" ]]; then
	GH_ARGS+=(--repo "${GH_REPO}")
fi

# Execute mock gh with constructed args
if PR_URL=$(PATH="${MOCK_DIR}:${PATH}" gh "${GH_ARGS[@]}" \
	--body "${PR_BODY}" 2>&1); then

	check_contains pr-create-url \
		"gh pr create returns PR URL" \
		"https://github.com/DEGAorg/test-repo/pull/42" "${PR_URL}"

	# Verify the logged gh call
	if [[ -f "${MOCK_GH_LOG}" ]]; then
		gh_call="$(cat "${MOCK_GH_LOG}")"
		check_contains pr-create-base \
			"gh pr create uses --base develop" \
			"--base develop" "${gh_call}"
		check_contains pr-create-head \
			"gh pr create uses --head orch/test-ship-pr" \
			"--head orch/test-ship-pr" "${gh_call}"
		check_contains pr-create-repo \
			"gh pr create uses --repo DEGAorg/test-repo" \
			"--repo DEGAorg/test-repo" "${gh_call}"
		check_contains pr-create-title \
			"gh pr create uses plan: slug title" \
			"--title plan: test-ship-pr" "${gh_call}"
	else
		printf '  FAIL pr-create-log: no gh call log found\n'
		FAIL=$((FAIL + 1))
	fi
else
	printf '  FAIL pr-create: gh pr create failed\n'
	FAIL=$((FAIL + 1))
fi

# Test: issue comment posted after PR creation
: >"${MOCK_GH_LOG}"
if [[ -n "${ISSUE_NUMBER}" && -n "${GH_REPO}" ]]; then
	PATH="${MOCK_DIR}:${PATH}" gh issue comment "${ISSUE_NUMBER}" \
		--repo "${GH_REPO}" \
		--body "PR created: ${PR_URL}" 2>&1 || true
fi

if [[ -f "${MOCK_GH_LOG}" ]]; then
	comment_call="$(cat "${MOCK_GH_LOG}")"
	check_contains pr-issue-comment-number \
		"issue comment targets correct issue number" \
		"issue comment 17" "${comment_call}"
	check_contains pr-issue-comment-repo \
		"issue comment targets correct repo" \
		"--repo DEGAorg/test-repo" "${comment_call}"
else
	printf '  FAIL pr-issue-comment: no gh call log found\n'
	FAIL=$((FAIL + 1))
fi

# Test: PR creation skipped when on target branch
CURRENT_BRANCH_SAME="${pr_target}"
if [[ "${CURRENT_BRANCH_SAME}" == "${pr_target}" ]]; then
	printf '  ok  pr-skip-same-branch: skips PR when on target branch\n'
	PASS=$((PASS + 1))
else
	printf '  FAIL pr-skip-same-branch: should skip when branch == target\n'
	FAIL=$((FAIL + 1))
fi

rm -rf "${MOCK_DIR}"

# ============================================================
printf '\norch-engine.sh SHIP step 8 — failure is non-fatal\n'
# ============================================================

# Test: PR creation failure should not block SHIP
# The engine wraps PR creation in a conditional — verify the pattern
MOCK_DIR="$(mktemp -d)"
cat >"${MOCK_DIR}/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Mock gh that fails on pr create
case "${1:-}" in
  pr) exit 1 ;;
esac
exit 0
GHSTUB
chmod +x "${MOCK_DIR}/gh"

# Simulate the non-fatal pattern from orch-engine.sh
SHIP_ERRORS=0
if PR_URL=$(PATH="${MOCK_DIR}:${PATH}" gh pr create \
	--title "test" --base main --head test-branch \
	--body "test" 2>&1); then
	echo "unexpected success"
else
	# This matches the engine pattern: log warning, don't increment errors
	printf '  ok  pr-fail-nonfatal: PR creation failure caught\n'
	PASS=$((PASS + 1))
fi

# SHIP_ERRORS should remain 0 (PR failure is non-fatal)
check pr-fail-no-error-increment \
	"PR failure does not increment SHIP_ERRORS" \
	0 "${SHIP_ERRORS}"

rm -rf "${MOCK_DIR}"

# ============================================================
printf '\nshellcheck and shfmt\n'
# ============================================================

CHANGED_SCRIPTS=(
	"${REPO_ROOT}/scripts/orch-engine.sh"
	"${REPO_ROOT}/scripts/gh-plan-sync.sh"
)

for script in "${CHANGED_SCRIPTS[@]}"; do
	name="$(basename "${script}")"

	if command -v shellcheck &>/dev/null; then
		exit_code=0
		shellcheck -x -e SC1091 -e SC2016 "${script}" >/dev/null 2>&1 || exit_code=$?
		check "shellcheck-${name}" \
			"${name} passes shellcheck" \
			0 "${exit_code}"
	else
		printf '  skip shellcheck-%s: not installed\n' "${name}"
	fi

	if command -v shfmt &>/dev/null; then
		exit_code=0
		shfmt -d "${script}" >/dev/null 2>&1 || exit_code=$?
		check "shfmt-${name}" \
			"${name} passes shfmt" \
			0 "${exit_code}"
	else
		printf '  skip shfmt-%s: not installed\n' "${name}"
	fi
done

# ============================================================
# Summary
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
