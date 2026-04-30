#!/usr/bin/env bash
# orch-reviewer-run.sh
#
# Runs the four behaviour-aware gates from `agents/orch-reviewer.md`
# against a PR. Designed to be called from the orchestrator after the
# worker marks all progress items done, before applying `plan:pr-review`.
#
# Inputs (from environment or args):
#   --plan <file>         path to the plan body (markdown)
#   --diff <file>         path to the unified diff for the PR
#   --repo-root <dir>     repo root for cross-file reads (default: cwd)
#   --out <dir>           output dir for findings.md + verdict.json
#                         (default: a tempdir, printed on stdout)
#
# Output: findings.md and verdict.json written to the chosen out dir.
# Exit code: 0 if aggregate is PASS or WARN, 1 if FAIL or INCONCLUSIVE.
#
# Each gate is implemented as a function returning one of:
#   PASS | FAIL | INCONCLUSIVE | WARN
# plus a one-line reason printed on stderr (captured by the dispatcher).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

PLAN_FILE=""
DIFF_FILE=""
REPO_ROOT="$(pwd)"
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --plan)
    PLAN_FILE="${2:-}"
    shift 2
    ;;
  --diff)
    DIFF_FILE="${2:-}"
    shift 2
    ;;
  --repo-root)
    REPO_ROOT="${2:-}"
    shift 2
    ;;
  --out)
    OUT_DIR="${2:-}"
    shift 2
    ;;
  *)
    echo "error: unknown arg: $1" >&2
    exit 2
    ;;
  esac
done

if [[ -z "${PLAN_FILE}" || -z "${DIFF_FILE}" ]]; then
  echo "usage: orch-reviewer-run.sh --plan <file> --diff <file> [--repo-root <dir>] [--out <dir>]" >&2
  exit 2
fi
if [[ ! -f "${PLAN_FILE}" ]]; then
  echo "error: plan file not found: ${PLAN_FILE}" >&2
  exit 2
fi
if [[ ! -f "${DIFF_FILE}" ]]; then
  echo "error: diff file not found: ${DIFF_FILE}" >&2
  exit 2
fi
if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="$(mktemp -d -t orch-reviewer.XXXXXX)"
fi
mkdir -p "${OUT_DIR}"

FINDINGS="${OUT_DIR}/findings.md"
VERDICT="${OUT_DIR}/verdict.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# List of files changed in the diff (a/ and b/ prefixes stripped).
changed_files() {
  awk '/^diff --git / { print $4 }' "${DIFF_FILE}" | sed 's|^b/||'
}

# True if any changed file matches one of the live-infra path patterns.
is_live_infra_change() {
  changed_files | grep -E \
    -e '^canon/templates/live-executor\.ts$' \
    -e '^canon/templates/live-positions\.ts$' \
    -e '^canon/templates/usdc-allowance\.ts$' \
    -e '^canon/templates/strategies/[^/]+/entry\.ts$' \
    -q
}

# True if any test file in the diff has an integration-trace shape:
# imports `signal.js` AND the order-params helper AND has a CLOB
# token-id regex assertion.
has_integration_trace_test() {
  awk '
    /^diff --git / {
      file = $4
      sub(/^b\//, "", file)
      keep = (file ~ /\/__tests__\// || file ~ /\.test\.ts$/)
    }
    keep && /^\+/ { print }
  ' "${DIFF_FILE}" |
    grep -q 'signal\.js' ||
    return 1
  awk '
    /^diff --git / {
      file = $4
      sub(/^b\//, "", file)
      keep = (file ~ /\/__tests__\// || file ~ /\.test\.ts$/)
    }
    keep && /^\+/ { print }
  ' "${DIFF_FILE}" |
    grep -qE 'signalToOrderParams|order-executor\.js' ||
    return 1
  awk '
    /^diff --git / {
      file = $4
      sub(/^b\//, "", file)
      keep = (file ~ /\/__tests__\// || file ~ /\.test\.ts$/)
    }
    keep && /^\+/ { print }
  ' "${DIFF_FILE}" |
    grep -qE '\\d\{60' ||
    return 1
  return 0
}

# ---------------------------------------------------------------------------
# Gate A — Integration trace
# ---------------------------------------------------------------------------

gate_a() {
  if ! is_live_infra_change; then
    echo "PASS" >"${OUT_DIR}/gate-a.verdict"
    echo "no live-infra files changed" >"${OUT_DIR}/gate-a.reason"
    return
  fi
  if has_integration_trace_test; then
    echo "PASS" >"${OUT_DIR}/gate-a.verdict"
    echo "integration-trace test present" >"${OUT_DIR}/gate-a.reason"
  else
    echo "FAIL" >"${OUT_DIR}/gate-a.verdict"
    echo "live-infra files changed but no test asserts on CLOB token-id shape (digit pattern)" >"${OUT_DIR}/gate-a.reason"
  fi
}

# ---------------------------------------------------------------------------
# Gate B — Decision-log audit
# ---------------------------------------------------------------------------

gate_b() {
  local decisions_file="${OUT_DIR}/decisions.jsonl"
  bash "${SCRIPT_DIR}/orch-gate-decision-audit.sh" "${PLAN_FILE}" >"${decisions_file}" 2>/dev/null || true

  if [[ ! -s "${decisions_file}" ]]; then
    echo "PASS" >"${OUT_DIR}/gate-b.verdict"
    echo "no decision-log rows to audit" >"${OUT_DIR}/gate-b.reason"
    return
  fi

  local missing=""
  local inconclusive=""
  local total=0

  while IFS= read -r row; do
    total=$((total + 1))
    local decision keywords
    decision=$(printf '%s' "${row}" | sed -n 's/.*"decision":"\([^"]*\)".*/\1/p')
    keywords=$(printf '%s' "${row}" | sed -n 's/.*"keywords":\[\([^]]*\)\].*/\1/p' |
      tr ',' '\n' | tr -d '"' | sed '/^$/d')

    if [[ -z "${keywords}" ]]; then
      inconclusive="${inconclusive}${decision}; "
      continue
    fi

    local found=0
    while IFS= read -r kw; do
      [[ -z "${kw}" ]] && continue
      if grep -qF -- "${kw}" "${DIFF_FILE}"; then
        found=1
        break
      fi
    done <<<"${keywords}"

    if [[ "${found}" -eq 0 ]]; then
      missing="${missing}${decision}; "
    fi
  done <"${decisions_file}"

  if [[ -n "${missing}" ]]; then
    echo "FAIL" >"${OUT_DIR}/gate-b.verdict"
    echo "decisions without diff evidence: ${missing}" >"${OUT_DIR}/gate-b.reason"
  elif [[ -n "${inconclusive}" ]]; then
    echo "INCONCLUSIVE" >"${OUT_DIR}/gate-b.verdict"
    echo "decisions with no extractable keywords: ${inconclusive}" >"${OUT_DIR}/gate-b.reason"
  else
    echo "PASS" >"${OUT_DIR}/gate-b.verdict"
    echo "all ${total} decisions have evidence in diff" >"${OUT_DIR}/gate-b.reason"
  fi
}

# ---------------------------------------------------------------------------
# Gate C — Wiring graph
# ---------------------------------------------------------------------------

# Extract names of newly exported types/interfaces matching the
# hook/adapter/callback regex from the diff.
exported_hooks() {
  awk '
    /^\+export type / || /^\+export interface / {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[A-Z][A-Za-z0-9_]*(Hook|Callback|Handler|Adapter|Client)$/ ||
            $i ~ /^On[A-Z][A-Za-z0-9_]+$/) {
          print $i
        }
      }
    }
  ' "${DIFF_FILE}" | sort -u
}

# True if `name` has a production caller (any .ts file outside __tests__
# and not ending in .test.ts) that mentions the symbol.
has_production_caller() {
  local name="$1"
  # Search both repo root and the diff itself (in case a new caller is
  # being added in the same PR).
  local hits
  hits=$(grep -rln --include='*.ts' "${name}" "${REPO_ROOT}" 2>/dev/null |
    grep -v '/__tests__/' |
    grep -cv '\.test\.ts$' |
    tr -d ' ')
  # Also count diff-only callers added in this PR.
  local diff_hits
  diff_hits=$(awk '
    /^diff --git / {
      file = $4
      sub(/^b\//, "", file)
      keep = (file ~ /\.ts$/ && file !~ /\/__tests__\// && file !~ /\.test\.ts$/)
    }
    keep && /^\+/ { print }
  ' "${DIFF_FILE}" | grep -c "${name}" || true)
  if [[ "${hits}" -gt 0 || "${diff_hits}" -gt 1 ]]; then
    return 0
  fi
  return 1
}

gate_c() {
  local hooks unwired=""
  hooks=$(exported_hooks || true)
  if [[ -z "${hooks}" ]]; then
    echo "PASS" >"${OUT_DIR}/gate-c.verdict"
    echo "no new hooks/adapters introduced" >"${OUT_DIR}/gate-c.reason"
    return
  fi
  while IFS= read -r name; do
    [[ -z "${name}" ]] && continue
    if ! has_production_caller "${name}"; then
      unwired="${unwired}${name}; "
    fi
  done <<<"${hooks}"

  if [[ -n "${unwired}" ]]; then
    echo "FAIL" >"${OUT_DIR}/gate-c.verdict"
    echo "exported but not wired into production: ${unwired}" >"${OUT_DIR}/gate-c.reason"
  else
    echo "PASS" >"${OUT_DIR}/gate-c.verdict"
    echo "all new hooks have production callers" >"${OUT_DIR}/gate-c.reason"
  fi
}

# ---------------------------------------------------------------------------
# Gate D — Mock-coverage delta (advisory)
# ---------------------------------------------------------------------------

gate_d() {
  local mocked_paths
  mocked_paths=$(awk '
    /^diff --git / {
      file = $4
      sub(/^b\//, "", file)
      keep = (file ~ /\.test\.ts$/)
    }
    keep && /^\+/ {
      if (match($0, /vi\.mock\(["'"'"'][^"'"'"']+["'"'"']/)) {
        s = substr($0, RSTART, RLENGTH)
        gsub(/.*vi\.mock\(["'"'"']/, "", s)
        gsub(/["'"'"'].*/, "", s)
        print s
      }
    }
  ' "${DIFF_FILE}" | sort -u)

  if [[ -z "${mocked_paths}" ]]; then
    echo "PASS" >"${OUT_DIR}/gate-d.verdict"
    echo "no new mocks introduced" >"${OUT_DIR}/gate-d.reason"
    return
  fi

  # Has any test file in the diff a shape-style assertion?
  local has_shape_assertion=0
  if awk '
    /^diff --git / {
      file = $4
      sub(/^b\//, "", file)
      keep = (file ~ /\.test\.ts$/)
    }
    keep && /^\+/ { print }
  ' "${DIFF_FILE}" |
    grep -qE 'expect\.objectContaining|expect\.stringMatching|toHaveBeenCalledWith.*expect\.'; then
    has_shape_assertion=1
  fi

  if [[ "${has_shape_assertion}" -eq 1 ]]; then
    echo "PASS" >"${OUT_DIR}/gate-d.verdict"
    echo "mocked modules have shape assertions" >"${OUT_DIR}/gate-d.reason"
  else
    echo "WARN" >"${OUT_DIR}/gate-d.verdict"
    echo "client-polymarket is mocked but no test asserts on the mocked module's argument shapes" >"${OUT_DIR}/gate-d.reason"
  fi
}

# ---------------------------------------------------------------------------
# Dispatch + aggregate
# ---------------------------------------------------------------------------

gate_a
gate_b
gate_c
gate_d

a=$(cat "${OUT_DIR}/gate-a.verdict")
b=$(cat "${OUT_DIR}/gate-b.verdict")
c=$(cat "${OUT_DIR}/gate-c.verdict")
d=$(cat "${OUT_DIR}/gate-d.verdict")

aggregate="PASS"
blocking=()
for label in A:${a} B:${b} C:${c}; do
  case "${label}" in
  *FAIL)
    aggregate="FAIL"
    blocking+=("gate${label%%:*}")
    ;;
  *INCONCLUSIVE)
    [[ "${aggregate}" != "FAIL" ]] && aggregate="INCONCLUSIVE"
    blocking+=("gate${label%%:*}")
    ;;
  esac
done

# Lowercase the gate labels for the JSON keys.
blocking_json=$(printf '"%s",' "${blocking[@]:-}" | sed 's/,$//')
[[ -z "${blocking_json}" ]] && blocking_json=""

cat >"${VERDICT}" <<JSON
{
  "gateA": "${a}",
  "gateB": "${b}",
  "gateC": "${c}",
  "gateD": "${d}",
  "aggregate": "${aggregate}",
  "blocking_gates": [${blocking_json}]
}
JSON

cat >"${FINDINGS}" <<MD
# Reviewer findings

## Gate A — Integration trace
**Verdict:** ${a}
$(cat "${OUT_DIR}/gate-a.reason")

## Gate B — Decision-log audit
**Verdict:** ${b}
$(cat "${OUT_DIR}/gate-b.reason")

## Gate C — Wiring graph
**Verdict:** ${c}
$(cat "${OUT_DIR}/gate-c.reason")

## Gate D — Mock-coverage delta (advisory)
**Verdict:** ${d}
$(cat "${OUT_DIR}/gate-d.reason")

## Aggregate: ${aggregate}
MD

echo "${OUT_DIR}"

case "${aggregate}" in
PASS) exit 0 ;;
*) exit 1 ;;
esac
