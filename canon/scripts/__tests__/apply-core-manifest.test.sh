#!/usr/bin/env bash
# Asserts that commands/apply-core.md installs canon skills,
# canon/scripts/*.sh, and injects a canon persona block into the
# installed AGENTS.md / CLAUDE.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
MANIFEST="${REPO_ROOT}/commands/apply-core.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "${MANIFEST}" ]] || fail "manifest not found: ${MANIFEST}"

assert_grep() {
  local pattern="$1"
  local desc="$2"
  if ! grep -qE "${pattern}" "${MANIFEST}"; then
    fail "expected apply-core.md to reference ${desc} (pattern: ${pattern})"
  fi
}

# Canon skills (top-level + new-skill author) must appear in the manifest.
assert_grep 'canon/skills/canon\.md' 'canon/skills/canon.md'
assert_grep 'canon/skills/canon-new\.md' 'canon/skills/canon-new.md'

# At least one of the converted sub-skills from plan #197 must be listed,
# proving the sub-skill block was added rather than only the two umbrellas.
assert_grep 'canon/skills/(canon-start|canon-stop|canon-conventions|discover|develop|register|orchestrator)\.md' \
  'a canon sub-skill from plan #197'

# Canon scripts install block.
assert_grep 'canon/scripts/' 'canon/scripts/ install block'
assert_grep 'canon/scripts/.*\.sh' 'canon/scripts/*.sh shell scripts'

# Persona + skill-list injection into installed AGENTS.md.
if ! grep -qiE 'canon (agent )?persona' "${MANIFEST}"; then
  fail "expected apply-core.md to declare a canon persona block for installed AGENTS.md"
fi
assert_grep 'AGENTS\.md' 'AGENTS.md persona injection target'

echo "ok: apply-core.md manifest lists canon skills, scripts, and persona block"
