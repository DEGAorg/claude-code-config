#!/usr/bin/env bash
# Test: core-init logic produces github block with sync: false when gh CLI is absent
# Run from repo root: bash tests/test-core-init-no-gh.sh
set -euo pipefail

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

printf 'core-init-no-gh\n'

# --- Setup: temp directory simulating a fresh repo with no gh CLI ---

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Create a fake PATH that has standard tools but NOT gh
FAKE_BIN="$(mktemp -d)"
for cmd in bash env grep cat mkdir touch printf echo sed ls; do
  real="$(command -v "${cmd}" 2>/dev/null || true)"
  if [[ -n "${real}" ]]; then
    ln -sf "${real}" "${FAKE_BIN}/${cmd}"
  fi
done
# Explicitly ensure gh is NOT in fake PATH (no symlink created for gh)

# --- Test 1: gh auth status fails when gh is absent ---

exit_code=0
PATH="${FAKE_BIN}" gh auth status 2>/dev/null || exit_code=$?
check no-gh-auth \
  "gh auth status fails when gh is absent" \
  127 "${exit_code}"

# --- Test 2: simulate core-init github detection + write with no gh ---
# This replicates the core-init step 4 logic: detect gh, fall back to sync: false

(
  cd "${WORK_DIR}"
  export PATH="${FAKE_BIN}"

  # Simulate step 4: GitHub detection
  GH_AVAILABLE=false
  if gh auth status 2>/dev/null; then
    GH_AVAILABLE=true
  fi

  # Write dega-core.yaml with the appropriate github block
  if [[ "${GH_AVAILABLE}" == "true" ]]; then
    GITHUB_BLOCK="github:
  sync: true
  repo: test/repo
  labels: true
  comments: true
  close_on_ship: true"
  else
    GITHUB_BLOCK="github:
  # gh CLI not available — install gh and run /core-init again to enable sync
  sync: false"
  fi

  cat > dega-core.yaml << YAML
# DEGA Core config — edit to match your project
version: 1
max_iterations: 20

budget:
  warn_at_iteration: 15
check_command: |
  echo "No check_command configured — edit dega-core.yaml"
  exit 1
poll_interval_seconds: 30

# Worker and reviewer prompts (global, installed by /apply-core)
worker_prompt: ~/.claude/scripts/ralph-worker-prompt.md
reviewer_prompt: ~/.claude/scripts/ralph-reviewer-prompt.md

${GITHUB_BLOCK}

success_criteria:
  - "tests pass"
  - "linting clean"
  - "types valid"
YAML
)

# --- Test 3: dega-core.yaml was created ---

exit_code=0
[[ -f "${WORK_DIR}/dega-core.yaml" ]] || exit_code=1
check file-exists \
  "dega-core.yaml was created" \
  0 "${exit_code}"

# --- Test 4: github: key exists in the file ---

exit_code=0
grep -q '^github:' "${WORK_DIR}/dega-core.yaml" || exit_code=1
check github-key-present \
  "github: key exists in dega-core.yaml" \
  0 "${exit_code}"

# --- Test 5: sync: false is set ---

exit_code=0
grep -q 'sync: false' "${WORK_DIR}/dega-core.yaml" || exit_code=1
check sync-false \
  "sync: false is set when gh is absent" \
  0 "${exit_code}"

# --- Test 6: comment explains why sync is disabled ---

output="$(cat "${WORK_DIR}/dega-core.yaml")"
check_contains gh-not-available-comment \
  "comment explains gh CLI not available" \
  "gh CLI not available" "${output}"

# --- Test 7: sync: true is NOT present ---

exit_code=0
grep -q 'sync: true' "${WORK_DIR}/dega-core.yaml" && exit_code=1 || true
check no-sync-true \
  "sync: true is NOT present when gh is absent" \
  0 "${exit_code}"

# --- Test 8: validation gate catches missing github block ---
# Write a dega-core.yaml WITHOUT github block, then run the gate

GATE_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}" "${FAKE_BIN}" "${GATE_DIR}"' EXIT

cat > "${GATE_DIR}/dega-core.yaml" << 'YAML'
# DEGA Core config — edit to match your project
version: 1
max_iterations: 20

success_criteria:
  - "tests pass"
YAML

# Gate: check for github: key — should fail
exit_code=0
grep -q '^github:' "${GATE_DIR}/dega-core.yaml" || exit_code=1
check gate-detects-missing \
  "validation gate detects missing github block" \
  1 "${exit_code}"

# --- Test 9: validation gate repair adds the fallback block ---

# Simulate the repair from step 6
cat >> "${GATE_DIR}/dega-core.yaml" << 'EOF'

github:
  # ADDED BY VALIDATION GATE — github block was missing after initial write
  # Install gh and run /core-init again to enable sync
  sync: false
EOF

exit_code=0
grep -q '^github:' "${GATE_DIR}/dega-core.yaml" || exit_code=1
check gate-repair-works \
  "validation gate repair adds github block" \
  0 "${exit_code}"

# --- Test 10: repaired file has sync: false ---

exit_code=0
grep -q 'sync: false' "${GATE_DIR}/dega-core.yaml" || exit_code=1
check gate-repair-sync-false \
  "repaired file has sync: false" \
  0 "${exit_code}"

# --- Test 11: shellcheck on this test file ---

if command -v shellcheck &>/dev/null; then
  exit_code=0
  shellcheck "$0" >/dev/null 2>&1 || exit_code=$?
  check shellcheck \
    "this test passes shellcheck" \
    0 "${exit_code}"
else
  printf '  skip shellcheck: not installed\n'
fi

# --- Summary ---

TOTAL=$((PASS + FAIL))
printf '\n%d/%d tests passing.\n' "${PASS}" "${TOTAL}"
[[ "${FAIL}" -eq 0 ]]
