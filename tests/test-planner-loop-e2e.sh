#!/usr/bin/env bash
# End-to-end test for planner-loop.sh: runs with max_plans=1, verifies it
# assesses, plans, and launches the orchestrator.
#
# Stubs out `claude` and `orch-run.sh` so no real AI calls or tmux sessions
# are needed. Validates the full ASSESS → PLAN → EXECUTE → MONITOR cycle.
#
# Usage: bash tests/test-planner-loop-e2e.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0

# --- Helpers ---

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
	if echo "${haystack}" | grep -qF "${needle}"; then
		echo "  PASS: ${label}"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: ${label}"
		echo "    expected to contain: ${needle}"
		FAIL=$((FAIL + 1))
	fi
}

assert_file_exists() {
	local label="$1" path="$2"
	if [[ -f "${path}" ]]; then
		echo "  PASS: ${label}"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: ${label} — file not found: ${path}"
		FAIL=$((FAIL + 1))
	fi
}

# --- Setup temp repo ---

TMPDIR_ROOT=$(mktemp -d)
FAKE_REPO="${TMPDIR_ROOT}/repo"

cleanup() {
	rm -rf "${TMPDIR_ROOT}"
}
trap cleanup EXIT

mkdir -p "${FAKE_REPO}"

# Initialize a git repo so commits work
git -C "${FAKE_REPO}" init -q
git -C "${FAKE_REPO}" config user.email "test@test.com"
git -C "${FAKE_REPO}" config user.name "Test"
# Initial commit so HEAD exists
touch "${FAKE_REPO}/.gitkeep"
git -C "${FAKE_REPO}" add .gitkeep
git -C "${FAKE_REPO}" commit -q -m "init"

# Copy necessary scripts and agents
cp -r "${SCRIPT_DIR}/../scripts" "${FAKE_REPO}/scripts"
cp -r "${SCRIPT_DIR}/../agents" "${FAKE_REPO}/agents"

# Create directories planner-loop expects
mkdir -p "${FAKE_REPO}/docs/exec-plans/active"
mkdir -p "${FAKE_REPO}/docs/exec-plans"

# Create focus.yaml with max_plans=1
cat >"${FAKE_REPO}/focus.yaml" <<'EOF'
version: 1

description: |
  Test focus — fix broken test suites.

areas:
  - area: broken-tests
    priority: high
    source: manual
    context: >
      Test suites need updating.

budget:
  max_plans: 1
  max_consecutive_failures: 2
  cooldown_seconds: 0
EOF

# Create dega-core.yaml for orch_read_config
cat >"${FAKE_REPO}/dega-core.yaml" <<'EOF'
poll_interval_seconds: 1
max_iterations: 3
EOF

# Slug the mock assess agent will return
MOCK_SLUG="fix-broken-tests"
MOCK_DATE_SLUG="$(date +%Y%m%d)-${MOCK_SLUG}"

# --- Create mock `claude` binary ---

MOCK_BIN="${TMPDIR_ROOT}/bin"
mkdir -p "${MOCK_BIN}"

# Track which phase claude is called in via a counter file
CALL_COUNTER="${TMPDIR_ROOT}/claude-call-count"
echo "0" >"${CALL_COUNTER}"

cat >"${MOCK_BIN}/claude" <<MOCKEOF
#!/usr/bin/env bash
# Mock claude — first call returns ASSESS JSON, second writes plan.md
set -euo pipefail

count=\$(cat "${CALL_COUNTER}")
count=\$((count + 1))
echo "\${count}" >"${CALL_COUNTER}"

if [[ \${count} -eq 1 ]]; then
  # ASSESS phase — output wrapped in claude --output-format json structure
  cat <<'ASSESS_JSON'
{"type":"result","subtype":"success","cost_usd":0.01,"duration_ms":500,"duration_api_ms":400,"is_error":false,"num_turns":1,"result":[{"type":"text","text":"{\"action\": \"create_plan\", \"slug\": \"${MOCK_SLUG}\", \"title\": \"Fix broken test suites\", \"rationale\": \"P1 debt item\", \"focus_area\": \"broken-tests\"}"}],"session_id":"test"}
ASSESS_JSON
elif [[ \${count} -eq 2 ]]; then
  # PLAN phase — find and write the plan.md file
  # The prompt contains the plan file path — extract it
  plan_file="${FAKE_REPO}/docs/exec-plans/active/${MOCK_DATE_SLUG}/plan.md"
  cat >"\${plan_file}" <<'PLAN_MD'
# Plan: Fix broken test suites

**Status:** In progress

## Requirements

Fix broken test suites that use the old API.

## Approach

Update test scripts to use the multi-plan directory structure.

## Progress log

- [ ] Update test-orch-e2e.sh to use new API (deps: none)
- [ ] Update test-orch-stale-detection.sh to use new API (deps: none)

## Completion criteria

- [ ] All test scripts pass
PLAN_MD
else
  echo "unexpected claude call \${count}" >&2
  exit 1
fi
MOCKEOF
chmod +x "${MOCK_BIN}/claude"

# --- Create mock orch-run.sh (overwrite the copied one) ---

# The mock orch-run.sh creates a state.json that says "completed"
cat >"${FAKE_REPO}/scripts/orch-run.sh" <<ORCHEOF
#!/usr/bin/env bash
# Mock orch-run.sh — creates a completed state.json
set -euo pipefail

SLUG="\$1"
ORCH_DIR="${FAKE_REPO}/.orchestrator/plans/\${SLUG}"
mkdir -p "\${ORCH_DIR}"

cat >"\${ORCH_DIR}/state.json" <<'STATE'
{
  "status": "completed",
  "items": [
    {"id": 1, "description": "item 1", "status": "done"},
    {"id": 2, "description": "item 2", "status": "done"}
  ]
}
STATE

echo "mock-orch: launched for \${SLUG}"
ORCHEOF
chmod +x "${FAKE_REPO}/scripts/orch-run.sh"

# --- Disable sound playback ---

mkdir -p "${FAKE_REPO}/hooks"
cat >"${FAKE_REPO}/hooks/play-sound.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${FAKE_REPO}/hooks/play-sound.sh"

# --- Run the planner loop ---

echo "=== Running planner-loop.sh with max_plans=1 ==="

# Put mock claude first on PATH
export PATH="${MOCK_BIN}:${PATH}"

# cwd must be FAKE_REPO because create-exec-plan.sh uses relative paths
output=$(cd "${FAKE_REPO}" && bash scripts/planner-loop.sh --background 2>&1) || true

echo ""
echo "=== Output ==="
echo "${output}"
echo ""

# --- Verify phases ---

echo "=== Assertions ==="

# 1. ASSESS phase ran
assert_contains "ASSESS phase logged" "${output}" "ASSESS — spawning assessment agent"
assert_contains "ASSESS result parsed" "${output}" "action=create_plan"

# 2. PLAN phase ran
assert_contains "PLAN phase logged" "${output}" "PLAN — creating plan for ${MOCK_SLUG}"
assert_contains "PLAN completed" "${output}" "PLAN complete"

# 3. Plan file was created
assert_file_exists "plan.md written" \
	"${FAKE_REPO}/docs/exec-plans/active/${MOCK_DATE_SLUG}/plan.md"

# 4. COMMIT phase ran
assert_contains "COMMIT phase logged" "${output}" "COMMIT — committing plan"

# 5. EXECUTE phase ran
assert_contains "EXECUTE phase logged" "${output}" "EXECUTE — launching orchestrator"

# 6. MONITOR phase ran and saw completion
assert_contains "MONITOR completed" "${output}" "completed"

# 7. Budget guard stopped the loop after 1 plan
assert_contains "budget exhausted" "${output}" "budget exhausted"
assert_contains "1 plan completed" "${output}" "1 plans completed"

# 8. Focus config was loaded with max_plans=1
assert_contains "focus loaded" "${output}" "max_plans=1"

# 9. Claude was called exactly 2 times (ASSESS + PLAN)
claude_calls=$(cat "${CALL_COUNTER}")
assert_eq "claude called exactly 2 times" "2" "${claude_calls}"

# --- Summary ---

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
	exit 1
fi
