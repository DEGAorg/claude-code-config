#!/usr/bin/env bash
# run-fixtures.sh — assert each fixture's expected gate verdict matches
# what `scripts/orch-reviewer-run.sh` actually produces.
#
# Each fixture lives under fixtures/gate-{a,b,c,d}-{pass,fail}/ and has:
#   plan.md        — plan body input
#   diff.patch     — synthetic PR diff
#   expected.txt   — first line: PASS | FAIL | INCONCLUSIVE | WARN
#                    expected for the fixture's target gate.
#
# The fixture name encodes which gate is the subject. We assert that the
# corresponding gate verdict in `verdict.json` matches expected.txt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"
RUNNER="${REPO_ROOT}/scripts/orch-reviewer-run.sh"

if [[ ! -x "${RUNNER}" ]]; then
  echo "error: runner not executable: ${RUNNER}" >&2
  exit 2
fi

pass_count=0
fail_count=0
failed_fixtures=()

for fixture in "${FIXTURES_DIR}"/gate-*; do
  name=$(basename "${fixture}")
  gate_letter=$(echo "${name}" | sed -n 's/^gate-\([abcd]\)-.*/\1/p')
  if [[ -z "${gate_letter}" ]]; then
    continue
  fi
  expected=$(head -n 1 "${fixture}/expected.txt")

  out_dir=$(mktemp -d -t orch-fixture-"${name}".XXXXXX)
  set +e
  bash "${RUNNER}" \
    --plan "${fixture}/plan.md" \
    --diff "${fixture}/diff.patch" \
    --repo-root "${REPO_ROOT}" \
    --out "${out_dir}" \
    >/dev/null 2>&1
  set -e

  gate_key="gate${gate_letter^^}"
  actual=$(sed -n "s/.*\"${gate_key}\": \"\\([^\"]*\\)\".*/\\1/p" "${out_dir}/verdict.json")

  if [[ "${actual}" == "${expected}" ]]; then
    pass_count=$((pass_count + 1))
    printf 'OK   %-20s %s\n' "${name}" "${actual}"
  else
    fail_count=$((fail_count + 1))
    failed_fixtures+=("${name}")
    printf 'FAIL %-20s expected=%s actual=%s\n' "${name}" "${expected}" "${actual}"
  fi
  rm -rf "${out_dir}"
done

echo ""
echo "passed: ${pass_count}, failed: ${fail_count}"
if [[ "${fail_count}" -gt 0 ]]; then
  printf 'failures: %s\n' "${failed_fixtures[*]}"
  exit 1
fi
