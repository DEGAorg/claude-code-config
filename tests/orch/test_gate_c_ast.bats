#!/usr/bin/env bats
#
# Tests for Gate C v2 — AST-based wiring detector (gate_c_ast).
#
# Forensics: PR #262 dogfood (2026-05-07) — the v1 grep-based gate_c
# false-passed when a newly exported hook was *referenced* in a type
# position (import, type annotation, re-export) but never *called* from
# any production code path. v2 augments the gate with an ast-grep check
# that requires a call-expression `Name(...)` in non-test `.ts` code.
# Rolled out advisory: the v2 verdict is recorded in
# `${OUT_DIR}/gate-c.ast.verdict` for observation; the aggregate SHIP/FAIL
# still gates on the v1 grep verdict (`gate-c.verdict`).
#
# Contract under test (added by the plan to scripts/orch-reviewer-run.sh):
#
#   gate_c_ast()
#     - For each name from exported_hooks(), search non-test .ts files
#       under REPO_ROOT for a call-expression matching the ast-grep
#       pattern '$NAME($$$)' under --lang ts.
#     - PASS  → every hook has ≥1 call-expression match in production code
#     - FAIL  → ≥1 hook has no call-expression match (type-only references
#               and pure absence both fall here)
#     - SKIP  → ast-grep is not on PATH (fail-open, advisory)
#     - PASS  → no exported hooks introduced (nothing to check)
#     - Writes the verdict to ${OUT_DIR}/gate-c.ast.verdict and a one-line
#       reason to ${OUT_DIR}/gate-c.ast.reason.
#     - Does NOT modify gate-c.verdict (the v1 aggregate input).

setup() {
  TEST_TMP="$(mktemp -d -t orch-gate-c-ast-XXXXXX)"
  export TEST_TMP
  REPO_ROOT_REAL="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  RUNNER="${REPO_ROOT_REAL}/scripts/orch-reviewer-run.sh"
  mkdir -p "${TEST_TMP}/repo" "${TEST_TMP}/out"
}

teardown() {
  if [[ -n "${TEST_TMP:-}" && -d "${TEST_TMP}" ]]; then
    rm -rf "${TEST_TMP}"
  fi
}

# A minimal plan body: no decision-log rows, so gate_b passes trivially
# and the aggregate verdict is determined by gate_a/c/d only.
write_plan() {
  cat >"${TEST_TMP}/plan.md" <<'EOF'
# Plan

## Approach

Adds a hook for downstream wiring.
EOF
}

# Synthesize a unified diff that adds an exported hook in runner.ts.
# The hook name must match the regex in exported_hooks() — the suffix
# (Hook|Callback|Handler|Adapter|Client) or `On<UpperCase>...` prefix.
write_diff_with_hook() {
  local hook_name="$1"
  cat >"${TEST_TMP}/diff.patch" <<EOF
diff --git a/runner.ts b/runner.ts
--- a/runner.ts
+++ b/runner.ts
@@ -10,6 +10,7 @@
+export type ${hook_name} = (input: { value: number }) => void;
EOF
}

# Run the reviewer with the test fixtures in place. Wraps `set +e` so a
# FAIL aggregate (exit 1) does not abort the test — the AST verdict is
# advisory and we only inspect gate-c.ast.verdict.
run_reviewer() {
  set +e
  bash "${RUNNER}" \
    --plan "${TEST_TMP}/plan.md" \
    --diff "${TEST_TMP}/diff.patch" \
    --repo-root "${TEST_TMP}/repo" \
    --out "${TEST_TMP}/out" \
    >/dev/null 2>&1
  set -e
}

# Build a PATH that excludes every directory containing an `ast-grep`
# binary. Used by the SKIP test to simulate ast-grep not being installed
# without actually uninstalling it.
path_without_ast_grep() {
  local sanitized=""
  local IFS=':'
  for d in ${PATH}; do
    [[ -z "${d}" ]] && continue
    if [[ ! -x "${d}/ast-grep" ]]; then
      sanitized="${sanitized}${sanitized:+:}${d}"
    fi
  done
  printf '%s' "${sanitized}"
}

# --- ast-grep available: verdicts driven by detection rule ---

@test "type-only reference produces FAIL on AST verdict" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  write_plan
  write_diff_with_hook "OnSampleHook"
  # Production caller mentions the hook only as a type — never calls it.
  cat >"${TEST_TMP}/repo/wiring.ts" <<'TS'
import type { OnSampleHook } from "./runner.js";

const handler: OnSampleHook = (input) => {
  console.log(input.value);
};
export { handler };
TS
  run_reviewer
  [ -f "${TEST_TMP}/out/gate-c.ast.verdict" ]
  [ "$(cat "${TEST_TMP}/out/gate-c.ast.verdict")" = "FAIL" ]
}

@test "call-expression in non-test code produces PASS on AST verdict" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  write_plan
  write_diff_with_hook "InvokeFooClient"
  # Production caller invokes the symbol as a call expression.
  cat >"${TEST_TMP}/repo/wiring.ts" <<'TS'
import { InvokeFooClient } from "./runner.js";

InvokeFooClient({ value: 42 });
TS
  run_reviewer
  [ -f "${TEST_TMP}/out/gate-c.ast.verdict" ]
  [ "$(cat "${TEST_TMP}/out/gate-c.ast.verdict")" = "PASS" ]
}

@test "call-expression only in __tests__ does not count → FAIL on AST verdict" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  write_plan
  write_diff_with_hook "OrphanHandler"
  # The only call site is under __tests__/ — must be ignored by the AST
  # detector, leaving zero production callers.
  mkdir -p "${TEST_TMP}/repo/__tests__"
  cat >"${TEST_TMP}/repo/__tests__/runner.test.ts" <<'TS'
import { OrphanHandler } from "../runner.js";

OrphanHandler({ value: 1 });
TS
  run_reviewer
  [ -f "${TEST_TMP}/out/gate-c.ast.verdict" ]
  [ "$(cat "${TEST_TMP}/out/gate-c.ast.verdict")" = "FAIL" ]
}

@test "no references anywhere produces FAIL on AST verdict" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  write_plan
  write_diff_with_hook "OnUnreferencedHook"
  # Repo has a non-test .ts file that does not mention the hook at all.
  cat >"${TEST_TMP}/repo/unrelated.ts" <<'TS'
export const noop = () => {};
TS
  run_reviewer
  [ -f "${TEST_TMP}/out/gate-c.ast.verdict" ]
  [ "$(cat "${TEST_TMP}/out/gate-c.ast.verdict")" = "FAIL" ]
}

# --- ast-grep missing: SKIP (fail-open, advisory) ---

@test "ast-grep missing from PATH produces SKIP on AST verdict" {
  write_plan
  write_diff_with_hook "OnSkipHook"
  # Even with a "good" production caller, a missing ast-grep binary
  # forces SKIP — the gate cannot answer, so it must not emit FAIL.
  cat >"${TEST_TMP}/repo/wiring.ts" <<'TS'
import { OnSkipHook } from "./runner.js";

OnSkipHook({ value: 1 });
TS
  local sanitized
  sanitized="$(path_without_ast_grep)"
  set +e
  PATH="${sanitized}" bash "${RUNNER}" \
    --plan "${TEST_TMP}/plan.md" \
    --diff "${TEST_TMP}/diff.patch" \
    --repo-root "${TEST_TMP}/repo" \
    --out "${TEST_TMP}/out" \
    >/dev/null 2>&1
  set -e
  [ -f "${TEST_TMP}/out/gate-c.ast.verdict" ]
  [ "$(cat "${TEST_TMP}/out/gate-c.ast.verdict")" = "SKIP" ]
}

@test "ast-grep missing → reason mentions ast-grep so logs are diagnosable" {
  write_plan
  write_diff_with_hook "OnSkipHook"
  cat >"${TEST_TMP}/repo/wiring.ts" <<'TS'
import { OnSkipHook } from "./runner.js";
OnSkipHook({ value: 1 });
TS
  local sanitized
  sanitized="$(path_without_ast_grep)"
  set +e
  PATH="${sanitized}" bash "${RUNNER}" \
    --plan "${TEST_TMP}/plan.md" \
    --diff "${TEST_TMP}/diff.patch" \
    --repo-root "${TEST_TMP}/repo" \
    --out "${TEST_TMP}/out" \
    >/dev/null 2>&1
  set -e
  [ -f "${TEST_TMP}/out/gate-c.ast.reason" ]
  grep -q 'ast-grep' "${TEST_TMP}/out/gate-c.ast.reason"
}

# --- aggregate isolation: AST verdict is advisory only ---

@test "AST FAIL does not flip aggregate when v1 grep gate_c PASSes" {
  command -v ast-grep >/dev/null 2>&1 || skip "ast-grep not installed"
  write_plan
  write_diff_with_hook "OnAdvisoryHook"
  # Type-only reference: v1 grep finds the symbol → gate-c.verdict=PASS.
  # v2 ast-grep finds no call expression → gate-c.ast.verdict=FAIL.
  # Aggregate must remain PASS because Gate C v2 is advisory.
  cat >"${TEST_TMP}/repo/wiring.ts" <<'TS'
import type { OnAdvisoryHook } from "./runner.js";

const handler: OnAdvisoryHook = (input) => {
  console.log(input.value);
};
export { handler };
TS
  run_reviewer
  [ "$(cat "${TEST_TMP}/out/gate-c.verdict")" = "PASS" ]
  [ "$(cat "${TEST_TMP}/out/gate-c.ast.verdict")" = "FAIL" ]
  # verdict.json's aggregate must not be FAIL just because AST FAILed.
  grep -q '"aggregate": "PASS"' "${TEST_TMP}/out/verdict.json"
}
