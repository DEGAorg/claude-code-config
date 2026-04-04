#!/usr/bin/env bash
# Unit tests for scripts/gh-plan-sync.sh
# Tests argument parsing, validation, and comment formatting.
# Does NOT call the real gh CLI — tests that would require a live
# GitHub API are limited to validation/error-path checks.
# Run from repo root: bash tests/test-gh-plan-sync.sh
set -euo pipefail

SCRIPT="scripts/gh-plan-sync.sh"
PASS=0
FAIL=0

check() {
	local id="$1"
	local description="$2"
	local expected="$3"
	local actual="$4"
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

printf 'gh-plan-sync\n'

# --- Validation tests (these fail before any gh API calls) ---

# Test: missing event type
exit_code=0
output="$(bash "${SCRIPT}" 2>&1)" || exit_code=$?
check no-event \
	"fails with no arguments" \
	1 "${exit_code}"
check_contains no-event-msg \
	"error mentions event type" \
	"event type required" "${output}"

# Test: missing slug
exit_code=0
output="$(bash "${SCRIPT}" start 2>&1)" || exit_code=$?
check no-slug \
	"fails with missing slug" \
	1 "${exit_code}"
check_contains no-slug-msg \
	"error mentions slug" \
	"slug required" "${output}"

# Test: missing --issue
exit_code=0
output="$(bash "${SCRIPT}" start my-plan 2>&1)" || exit_code=$?
check no-issue \
	"fails with missing --issue" \
	1 "${exit_code}"
check_contains no-issue-msg \
	"error mentions --issue" \
	"--issue" "${output}"

# Test: unknown event type
exit_code=0
output="$(bash "${SCRIPT}" bogus my-plan --issue 1 2>&1)" || exit_code=$?
check bad-event \
	"fails with unknown event type" \
	1 "${exit_code}"
check_contains bad-event-msg \
	"error mentions unknown event" \
	"unknown event type" "${output}"

# Test: unknown option
exit_code=0
output="$(bash "${SCRIPT}" start my-plan --issue 1 --bogus 2>&1)" || exit_code=$?
check bad-option \
	"fails with unknown option" \
	1 "${exit_code}"
check_contains bad-option-msg \
	"error mentions unknown option" \
	"unknown option" "${output}"

# Test: valid events are accepted (start, review, ship, revise)
# These will fail at the auth check (not at validation), proving they
# pass argument parsing. Auth failure exits with code 1.
for event in start review ship pr_merged revise; do
	exit_code=0
	# Use a fake PATH that has gh (stub returning auth failure) but blocks real API
	STUB_DIR="$(mktemp -d)"
	cat >"${STUB_DIR}/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: auth status fails, everything else succeeds
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
STUB
	chmod +x "${STUB_DIR}/gh"

	output="$(PATH="${STUB_DIR}:${PATH}" bash "${SCRIPT}" "${event}" my-plan \
		--issue 42 2>&1)" || exit_code=$?
	rm -rf "${STUB_DIR}"

	check "valid-event-${event}" \
		"${event} event passes validation (fails at auth)" \
		1 "${exit_code}"
	check_contains "valid-event-${event}-auth" \
		"${event} event fails with auth error, not validation" \
		"not authenticated" "${output}"
done

# --- Test: script is shellcheck clean ---

if command -v shellcheck &>/dev/null; then
	exit_code=0
	shellcheck -x -e SC1091 -e SC2016 "${SCRIPT}" >/dev/null 2>&1 || exit_code=$?
	check shellcheck \
		"passes shellcheck" \
		0 "${exit_code}"
else
	printf '  skip shellcheck: not installed\n'
fi

# --- Test: script is shfmt clean ---

if command -v shfmt &>/dev/null; then
	exit_code=0
	shfmt -d "${SCRIPT}" >/dev/null 2>&1 || exit_code=$?
	check shfmt \
		"passes shfmt" \
		0 "${exit_code}"
else
	printf '  skip shfmt: not installed\n'
fi

# --- Body update tests (update_progress_checkbox, update_body_on_pr) ---

# These tests use a mock gh that stores/returns issue body content.
# The mock captures --body edits to a temp file so we can verify transforms.

printf '\nbody-update\n'

MOCK_DIR="$(mktemp -d)"
MOCK_BODY_FILE="${MOCK_DIR}/body.md"
MOCK_EDITED_BODY="${MOCK_DIR}/edited-body.md"
MOCK_DEGA_CORE="${MOCK_DIR}/dega-core.yaml"

# Minimal dega-core.yaml so provider.sh resolves the repo
cat >"${MOCK_DEGA_CORE}" <<'YAML'
provider: github
github:
  sync: true
  repo: test-owner/test-repo
  labels: false
  comments: false
  close_on_ship: false
YAML

# Write the mock gh script — returns JSON for issue view and handles --jq
cat >"${MOCK_DIR}/gh" <<'GHSTUB'
#!/usr/bin/env bash
set -euo pipefail

MOCK_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
  auth)
    exit 0
    ;;
  repo)
    echo "test-owner/test-repo"
    ;;
  issue)
    case "${2:-}" in
      view)
        # Build a JSON response matching gh's --json output
        body_content=""
        if [[ -f "${MOCK_DIR}/body.md" ]]; then
          body_content="$(cat "${MOCK_DIR}/body.md")"
        fi
        state="OPEN"
        if [[ -f "${MOCK_DIR}/close-called" ]]; then
          state="CLOSED"
        fi
        json_output=$(jq -n \
          --arg body "${body_content}" \
          --arg state "${state}" \
          '{body: $body, state: $state, title: "test", assignees: [], milestone: null, labels: []}')

        # Extract --jq filter if present
        jq_filter=""
        shift 2  # skip "issue view"
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--jq" ]]; then
            jq_filter="$2"
            break
          fi
          shift
        done

        if [[ -n "${jq_filter}" ]]; then
          echo "${json_output}" | jq "${jq_filter}"
        else
          echo "${json_output}"
        fi
        exit 0
        ;;
      edit)
        # Capture the --body argument
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--body" ]]; then
            printf '%s' "$2" > "${MOCK_DIR}/edited-body.md"
            exit 0
          fi
          shift
        done
        exit 0
        ;;
      comment)
        exit 0
        ;;
      close)
        touch "${MOCK_DIR}/close-called"
        exit 0
        ;;
    esac
    ;;
esac
exit 0
GHSTUB
chmod +x "${MOCK_DIR}/gh"

# Helper: run gh-plan-sync with mock gh and mock dega-core.yaml
run_sync() {
	(
		cd "${MOCK_DIR}"
		PATH="${MOCK_DIR}:${PATH}" bash "${OLDPWD}/${SCRIPT}" "$@" 2>&1
	)
}
# --- Test: update_progress_checkbox checks off matching item ---

cat >"${MOCK_BODY_FILE}" <<'BODY'
# Plan: Test plan

**Status:** In progress

## Progress log

- [ ] First item — do something
- [ ] Second item — do another thing
- [ ] Third item — finish up

## Completion criteria

- [ ] All items pass
- [ ] Tests pass
BODY

exit_code=0
OLDPWD="$(pwd)" run_sync review test-slug \
	--issue 99 --item-id 1 --item-desc "First item" \
	--item-result SHIP --iterations 1 || exit_code=$?

check progress-1-exit \
	"review SHIP for item 1 succeeds" \
	0 "${exit_code}"

if [[ -f "${MOCK_EDITED_BODY}" ]]; then
	edited="$(cat "${MOCK_EDITED_BODY}")"
	check_contains progress-1-checked \
		"first item checkbox is checked" \
		"- [x] First item" "${edited}"
	check_contains progress-1-others-unchecked \
		"second item checkbox still unchecked" \
		"- [ ] Second item" "${edited}"
	check_contains progress-1-status-unchanged \
		"Status field unchanged after review" \
		'**Status:** In progress' "${edited}"
else
	printf '  FAIL progress-1-checked: no edited body file found\n'
	FAIL=$((FAIL + 1))
fi
rm -f "${MOCK_EDITED_BODY}"

# --- Test: update_progress_checkbox is idempotent ---

# Body already has item 1 checked
cat >"${MOCK_BODY_FILE}" <<'BODY'
# Plan: Test plan

**Status:** In progress

## Progress log

- [x] First item — do something
- [ ] Second item — do another thing

## Completion criteria

- [ ] All items pass
BODY

exit_code=0
OLDPWD="$(pwd)" run_sync review test-slug \
	--issue 99 --item-id 1 --item-desc "First item" \
	--item-result SHIP --iterations 1 || exit_code=$?

check progress-idempotent-exit \
	"review SHIP for already-checked item succeeds" \
	0 "${exit_code}"

# No edit should have been written (nothing changed)
if [[ -f "${MOCK_EDITED_BODY}" ]]; then
	printf '  FAIL progress-idempotent: body was edited when it should not have been\n'
	FAIL=$((FAIL + 1))
else
	printf '  ok  progress-idempotent: no edit when item already checked\n'
	PASS=$((PASS + 1))
fi
rm -f "${MOCK_EDITED_BODY}"

# --- Test: update_progress_checkbox skips REVISE results ---

cat >"${MOCK_BODY_FILE}" <<'BODY'
## Progress log

- [ ] First item — do something
BODY

exit_code=0
OLDPWD="$(pwd)" run_sync review test-slug \
	--issue 99 --item-id 1 --item-desc "First item" \
	--item-result REVISE --iterations 1 \
	--feedback "needs fix" || exit_code=$?

check progress-revise-exit \
	"review REVISE does not check off item" \
	0 "${exit_code}"

if [[ -f "${MOCK_EDITED_BODY}" ]]; then
	printf '  FAIL progress-revise: body was edited on REVISE\n'
	FAIL=$((FAIL + 1))
else
	printf '  ok  progress-revise: no edit on REVISE\n'
	PASS=$((PASS + 1))
fi
rm -f "${MOCK_EDITED_BODY}"

# --- Test: update_body_on_pr sets Status to "PR Review" (not "Completed") ---

cat >"${MOCK_BODY_FILE}" <<'BODY'
# Plan: Test plan

**Status:** In progress

## Progress log

- [x] First item — do something
- [x] Second item — do another thing

## Completion criteria

- [ ] All items pass
- [ ] Tests pass
- [ ] Linting clean
BODY

exit_code=0
OLDPWD="$(pwd)" run_sync ship test-slug \
	--issue 99 --items 2 --passed 2 \
	--elapsed "1m30s" || exit_code=$?

check ship-exit \
	"ship event succeeds" \
	0 "${exit_code}"

if [[ -f "${MOCK_EDITED_BODY}" ]]; then
	edited="$(cat "${MOCK_EDITED_BODY}")"
	check_contains ship-status \
		"Status updated to PR Review" \
		'**Status:** PR Review' "${edited}"
	# Completion criteria should NOT be checked on SHIP (deferred to PR merge)
	check_contains ship-criteria-unchecked-1 \
		"first completion criterion still unchecked on ship" \
		"- [ ] All items pass" "${edited}"
	check_contains ship-criteria-unchecked-2 \
		"second completion criterion still unchecked on ship" \
		"- [ ] Tests pass" "${edited}"
	check_contains ship-criteria-unchecked-3 \
		"third completion criterion still unchecked on ship" \
		"- [ ] Linting clean" "${edited}"
	# Progress log items should remain checked (not modified)
	check_contains ship-progress-preserved \
		"progress log checkboxes preserved" \
		"- [x] First item" "${edited}"
else
	printf '  FAIL ship-body: no edited body file found\n'
	FAIL=$((FAIL + 1))
fi
rm -f "${MOCK_EDITED_BODY}"

# --- Test: ship does NOT close the issue ---

# Reset the mock to track close calls
MOCK_CLOSE_FILE="${MOCK_DIR}/close-called"
rm -f "${MOCK_CLOSE_FILE}"

cat >"${MOCK_BODY_FILE}" <<'BODY'
# Plan: Test plan

**Status:** In progress

## Completion criteria

- [ ] All items pass
BODY

exit_code=0
OLDPWD="$(pwd)" run_sync ship test-slug \
	--issue 99 --items 1 --passed 1 || exit_code=$?

check ship-no-close-exit \
	"ship succeeds without closing issue" \
	0 "${exit_code}"

if [[ -f "${MOCK_CLOSE_FILE}" ]]; then
	printf '  FAIL ship-no-close: gh issue close was called on ship\n'
	FAIL=$((FAIL + 1))
else
	printf '  ok  ship-no-close: issue not closed on ship\n'
	PASS=$((PASS + 1))
fi
rm -f "${MOCK_EDITED_BODY}" "${MOCK_CLOSE_FILE}"

# --- Test: update_body_on_pr is idempotent ---

cat >"${MOCK_BODY_FILE}" <<'BODY'
# Plan: Test plan

**Status:** PR Review

## Completion criteria

- [ ] All items pass
- [ ] Tests pass
BODY

exit_code=0
OLDPWD="$(pwd)" run_sync ship test-slug \
	--issue 99 --items 2 --passed 2 || exit_code=$?

check ship-idempotent-exit \
	"ship on already-PR-Review body succeeds" \
	0 "${exit_code}"

if [[ -f "${MOCK_EDITED_BODY}" ]]; then
	printf '  FAIL ship-idempotent: body was edited when already PR Review\n'
	FAIL=$((FAIL + 1))
else
	printf '  ok  ship-idempotent: no edit when body already PR Review\n'
	PASS=$((PASS + 1))
fi
rm -f "${MOCK_EDITED_BODY}"

# --- Test: pr_merged sets Status to "Completed" and checks completion criteria ---

printf '\npr_merged\n'

# pr_merged closes the issue when close_on_ship: true
cat >"${MOCK_DEGA_CORE}" <<'YAML'
provider: github
github:
  sync: true
  repo: test-owner/test-repo
  labels: false
  comments: false
  close_on_ship: true
YAML

cat >"${MOCK_BODY_FILE}" <<'BODY'
# Plan: Test plan

**Status:** PR Review

## Progress log

- [x] First item — do something
- [x] Second item — do another thing

## Completion criteria

- [ ] All items pass
- [ ] Tests pass
- [ ] Linting clean
BODY

rm -f "${MOCK_CLOSE_FILE:-${MOCK_DIR}/close-called}"

exit_code=0
OLDPWD="$(pwd)" run_sync pr_merged test-slug \
	--issue 99 || exit_code=$?

check merge-exit \
	"pr_merged event succeeds" \
	0 "${exit_code}"

if [[ -f "${MOCK_EDITED_BODY}" ]]; then
	edited="$(cat "${MOCK_EDITED_BODY}")"
	check_contains merge-status \
		"Status updated to Completed on merge" \
		'**Status:** Completed' "${edited}"
	check_contains merge-criteria-1 \
		"first completion criterion checked on merge" \
		"- [x] All items pass" "${edited}"
	check_contains merge-criteria-2 \
		"second completion criterion checked on merge" \
		"- [x] Tests pass" "${edited}"
	check_contains merge-criteria-3 \
		"third completion criterion checked on merge" \
		"- [x] Linting clean" "${edited}"
	# Progress log items should remain checked
	check_contains merge-progress-preserved \
		"progress log checkboxes preserved on merge" \
		"- [x] First item" "${edited}"
else
	printf '  FAIL merge-body: no edited body file found\n'
	FAIL=$((FAIL + 1))
fi

# pr_merged should close the issue if not auto-closed (mock returns OPEN)
if [[ -f "${MOCK_DIR}/close-called" ]]; then
	printf '  ok  merge-closes-issue: pr_merged closes issue when not auto-closed\n'
	PASS=$((PASS + 1))
else
	printf '  FAIL merge-closes-issue: pr_merged did not close the issue\n'
	FAIL=$((FAIL + 1))
fi
rm -f "${MOCK_EDITED_BODY}" "${MOCK_DIR}/close-called"

# --- Test: pr_merged is idempotent ---

cat >"${MOCK_BODY_FILE}" <<'BODY'
# Plan: Test plan

**Status:** Completed

## Completion criteria

- [x] All items pass
- [x] Tests pass
BODY

# Simulate already-closed issue
touch "${MOCK_DIR}/close-called"

exit_code=0
OLDPWD="$(pwd)" run_sync pr_merged test-slug \
	--issue 99 || exit_code=$?

check merge-idempotent-exit \
	"pr_merged on already-completed body succeeds" \
	0 "${exit_code}"

# Body should NOT have been edited (already up to date)
if [[ -f "${MOCK_EDITED_BODY}" ]]; then
	printf '  FAIL merge-idempotent: body was edited when already complete\n'
	FAIL=$((FAIL + 1))
else
	printf '  ok  merge-idempotent: no edit when body already complete\n'
	PASS=$((PASS + 1))
fi
rm -f "${MOCK_EDITED_BODY}" "${MOCK_DIR}/close-called"

# --- Test: body parse failure is graceful ---

# Restore close_on_ship: false for remaining tests
cat >"${MOCK_DEGA_CORE}" <<'YAML'
provider: github
github:
  sync: true
  repo: test-owner/test-repo
  labels: false
  comments: false
  close_on_ship: false
YAML

# Return empty body to simulate parse failure
: >"${MOCK_BODY_FILE}"

exit_code=0
output="$(OLDPWD="$(pwd)" run_sync ship test-slug \
	--issue 99 --items 1 --passed 1 2>&1)" || exit_code=$?

check parse-fail-exit \
	"ship with empty body still succeeds" \
	0 "${exit_code}"
check_contains parse-fail-warn \
	"logs warning about empty body" \
	"empty body" "${output}"

rm -f "${MOCK_EDITED_BODY}"

# --- Cleanup mock dir ---
rm -rf "${MOCK_DIR}"

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
