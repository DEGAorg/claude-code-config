#!/usr/bin/env bash
# Tests for canon/skills/canon-new.md structural contract.
#
# Asserts that the skill file exists and contains the required markers:
#   - A top-level `# ` markdown title
#   - An `@description` line (cross-agent skill metadata)
#   - Natural-language trigger keywords for pre-init intent capture
#   - A `/apply-core` hand-off string for the bootstrap path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_FILE="$REPO_ROOT/canon/skills/canon-new.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "ok: $1"
}

# 1. File exists
[ -f "$SKILL_FILE" ] || fail "skill file missing: $SKILL_FILE"
pass "skill file exists"

# 2. Has a top-level markdown title
grep -Eq '^# [^[:space:]]' "$SKILL_FILE" || fail "missing top-level '# Title' heading"
pass "has top-level title"

# 3. Has an @description line (cross-agent metadata marker)
grep -q '@description' "$SKILL_FILE" || fail "missing @description marker"
pass "has @description"

# 4. Recognizes NL trigger keywords for pre-init intent
#    At least one of each category must be present.
grep -Eiq 'prediction[- ]market' "$SKILL_FILE" ||
  fail "missing 'prediction-market' trigger keyword"
pass "has prediction-market trigger"

grep -Eiq 'new (project|strategy)|start (a )?new|try (an )?idea' "$SKILL_FILE" ||
  fail "missing new-project/strategy/try-idea trigger phrasing"
pass "has new-project trigger phrasing"

grep -Eiq 'polymarket|kalshi' "$SKILL_FILE" ||
  fail "missing venue keywords (Polymarket/Kalshi)"
pass "has venue keywords"

# 5. Has /apply-core hand-off string for bootstrap path
grep -q '/apply-core' "$SKILL_FILE" || fail "missing /apply-core hand-off"
pass "has /apply-core hand-off"

echo "all canon-new.test.sh assertions passed"
