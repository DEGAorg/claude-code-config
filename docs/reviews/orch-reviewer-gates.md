# Orchestrator reviewer gates — reference

The `orch-reviewer` agent runs once per PR after the worker finishes,
before the orchestrator applies the `plan:pr-review` label. It enforces
four behaviour-aware gates derived from the failure modes recorded in
`docs/reviews/261-orch-review-gap-analysis.md`.

This document is the operator-facing reference: what each gate checks,
how to read its output, how to waive it, and how to extend it.

For the agent prompt itself, see `agents/orch-reviewer.md`. For the
runner, see `scripts/orch-reviewer-run.sh`.

---

## Gate matrix

| Gate | Subject                                          | Verdict on miss      | Blocks merge? |
|------|--------------------------------------------------|----------------------|---------------|
| A    | Integration-trace test for live-infra changes    | FAIL                 | Yes           |
| B    | Decision-log audit (each decision has evidence)  | FAIL or INCONCLUSIVE | Yes           |
| C    | Named hooks/adapters have production callers     | FAIL                 | Yes           |
| D    | Mock-coverage delta vs. production caller shape  | WARN                 | No (advisory) |

A PR is mergeable when the reviewer's `aggregate` is `PASS` or `WARN`.
`FAIL` and `INCONCLUSIVE` block.

---

## Gate A — Integration trace

**Triggers when:** the PR diff touches any of:

- `canon/templates/live-executor.ts`
- `canon/templates/live-positions.ts`
- `canon/templates/usdc-allowance.ts`
- `canon/templates/strategies/*/entry.ts`

**Pass criteria:** at least one new/modified test file in the diff:

1. Imports the strategy's `signal.js` and `signalToOrderParams` (or the
   equivalent module at `canon/templates/order-executor.js`).
2. Constructs a `TradeSignal` from a real `detectSignals(...)` call
   (not a hand-built literal).
3. Asserts on the **shape** of the resulting `OrderParams`:
   - `tokenId` matches `/^\d{60,}$/` (real CLOB token IDs).
   - `price` is `0 ≤ p ≤ 1`.
   - `size > 0`.
   - `orderType` is `"market"` or `"limit"`.

**Why this gate:** plan #261 shipped a "live" arb-binary that fell back
to synthetic `<conditionId>:yes` token IDs. Unit tests mocked
`createOrder` and accepted any string. Only a shape-level assertion
catches it.

**Failure example:**

```
Gate A — Integration trace
Verdict: FAIL
Reason: live-infra files changed but no test asserts on CLOB token-id shape (digit pattern)
```

**Fix:** add one test that runs the chain `detectSignals → resolveOrder
→ signalToOrderParams` and checks `params.tokenId` against
`/^\d{60,}$/`. The test can still mock `createOrder`; the assertion is
on the params object passed to it.

---

## Gate B — Decision-log audit

**Pass criteria:** every row in the plan's `## Decision log` table has
at least one keyword that appears literally in the PR diff.

The reviewer extracts keywords with a heuristic (capitalised words,
ALL-CAPS acronyms, back-tick tokens) via
`scripts/orch-gate-decision-audit.sh`. If a row has no extractable
keywords, the gate reports `INCONCLUSIVE` for that row — not `FAIL`.

**Why this gate:** plan #261's decision log committed to "FOK limit
orders" but the implementation emitted market orders. No step
re-checked the decision log against the diff.

**Failure example:**

```
Gate B — Decision-log audit
Verdict: FAIL
Reason: decisions without diff evidence: FOK limit orders for ARB-01 fills;
```

**Fix:** either implement the decision (FOK) or update the plan body to
remove or rewrite the decision row to match what was actually built.

**Inconclusive example:**

```
Gate B — Decision-log audit
Verdict: INCONCLUSIVE
Reason: decisions with no extractable keywords: prefer simpler over clever;
```

The decision text was prose without ALL-CAPS or back-ticks. Either
rewrite the decision to include a code-pattern keyword, or waive the
row (see Waivers below).

---

## Gate C — Wiring graph

**Pass criteria:** every newly exported type/interface matching the
hook/adapter/callback regex (`*Hook | *Callback | *Handler | *Adapter |
*Client | On*`) has at least one production caller — i.e. a reference
in any `.ts` file outside `**/__tests__/**` and not ending in
`*.test.ts`.

The defining file does not count as a caller.

**Why this gate:** plan #261 added `risk.recordOutcome(boolean)` for
the circuit-breaker requirement, but the runner never called it. Tests
passed because tests called it directly.

**Failure example:**

```
Gate C — Wiring graph
Verdict: FAIL
Reason: exported but not wired into production: OnOutcome; AllowanceClient;
```

**Fix:** call the hook from the appropriate production module, or
mark it `Deferred (Q-N)` in the plan body to signal intentional
exposure-without-wiring.

---

## Gate D — Mock-coverage delta (advisory)

**Pass criteria:** every test file in the diff that uses `vi.mock(...)`
contains at least one shape-level assertion on the mock arguments
(`expect.objectContaining`, `expect.stringMatching`, etc.).

**Why this gate:** mocks erase the very interface you most want to
protect. A shape assertion forces the test to encode the production
type's stricter constraints, surfacing divergences (Gap 1 in #261) loud.

**v1 status:** advisory. A miss reports `WARN` and does not block.
After we have data on the false-positive rate, the gate is upgraded
to a blocker (see plan #263 decision log).

---

## Waivers

A blocking gate (A, B, or C) can be waived by adding a `## Waivers`
section to the plan body, with one entry per waived finding:

```markdown
## Waivers

- **Gate C — `OnOutcome`** — intentionally exposed without a
  runner-side caller; production wiring lands in follow-up plan #264.
  See `docs/reviews/261-open-questions.md` Q-2.
```

A waiver requires:

1. The gate name and the specific finding being waived.
2. A pointer to the follow-up plan or open-questions doc that closes it.

When a waiver is honoured, the reviewer marks the gate `WAIVED` in
`verdict.json`. `WAIVED` is treated as `PASS` for aggregate purposes.

Do not use waivers as a routine escape hatch. Each one is a debt that
must be tracked to a closing plan; if the debt is open for two cycles
without a follow-up plan, the gate becomes non-waivable for that
strategy.

---

## Reading reviewer output

The runner writes two files:

- `findings.md` — human-readable per-gate report (posted as a PR
  comment by the orch).
- `verdict.json` — machine-readable aggregate:

```json
{
  "gateA": "PASS",
  "gateB": "FAIL",
  "gateC": "PASS",
  "gateD": "WARN",
  "aggregate": "FAIL",
  "blocking_gates": ["gateB"]
}
```

Aggregate rules:

- Any of `gateA | gateB | gateC` is `FAIL` → `aggregate: FAIL`.
- Else any is `INCONCLUSIVE` → `aggregate: INCONCLUSIVE`.
- Else → `aggregate: PASS`.

`gateD` never affects the aggregate in v1.

---

## Known limitations (v1)

These are deliberate trade-offs in the v1 heuristics. Each one is
documented with the failure shape it cannot detect and what a v2 would
need to do.

### Gate B — keyword extractor is heuristic

The decision-log audit relies on extracting keywords from each
decision row. The current heuristic keeps:

- ALL-CAPS acronyms (≥2 chars): `FOK`, `USDC`, `CTF`.
- Back-tick tokens: `` `live-executor` ``, `` `OrderParams` ``.
- Capitalised proper nouns ≥4 chars NOT in a stop-word list.

Stop-words filter generic sentence-starters (`Separate`, `Either`,
`Default`, etc.) so they don't fail-flag every decision that begins
with one. The full list lives in
`scripts/orch-gate-decision-audit.sh`.

**What this misses.** A decision phrased entirely in lowercase prose
("we keep the existing handler shape") produces zero keywords and is
reported `INCONCLUSIVE` for that row. The aggregate then becomes
`INCONCLUSIVE` unless another decision row provides evidence.

**Fix shape for v2.** Either (a) require plan authors to wrap the
load-bearing identifier in back-ticks (already supported, just
underused), or (b) replace the heuristic with an LLM-extracted
keyword set — at the cost of non-determinism in the gate.

### Gate C — wiring detector cannot tell "referenced" from "called"

The current heuristic for "is this newly exposed hook actually wired
into production?" is: `grep` for the symbol name across all `.ts`
files outside `__tests__` and `*.test.ts`. If any non-test file
references the symbol, the gate passes.

**What this misses.** A symbol that's *defined* in one production
file and *referenced* (in a type signature, an export, a comment) in
another production file passes — even if no production code path
actually *calls* the function. The dogfood on PR #262 illustrated
this: `risk.recordOutcome(boolean)` was defined in `risk.ts` and
exposed through the strategy's risk interface, so it had non-test
"references." But the runner never *called* it. Gate C reported
PASS; the bug was real.

**Fix shape for v2.** Distinguish:

- *Reference* — the symbol name appears on the right of an `import`,
  in a type position, in `as`-cast, in a comment, etc.
- *Call site* — the symbol appears as the head of a call expression
  (`name(`) or as a method invocation (`.name(`) inside an executable
  function body, not in a type-only context.

Reliable distinction needs AST analysis (ts-morph, ast-grep with TS
support) rather than text search. Tracked as a v2 enhancement —
shipped as `gate_c_ast` in plan #266 and documented in the next
subsection.

**Mitigation today.** Gate A often catches the same class of failure
from a different angle: an unwired hook usually means the production
path is missing something testable. The aggregate verdict on PR #262
was FAIL via Gate A even though Gate C false-passed — defence in depth
worked.

### Gate C v2 — AST-based detector (advisory)

Plan #266 ships a second pass for Gate C that uses
`ast-grep --pattern '$NAME($$$)' --lang ts` to look for actual
call-expression matches rather than text references. It runs
alongside the v1 grep detector on every PR.

**Where the v2 verdict lives:**

- `${OUT_DIR}/gate-c.ast.verdict` — `PASS`, `FAIL`, or `SKIP`.
- `${OUT_DIR}/gate-c.ast.reason` — human-readable reason string.
- `verdict.json` — exposed as the `gateCAst` field for observation.
- `findings.md` — section `## Gate C v2 — Wiring graph (AST-based, advisory)`.

**Advisory until the aggregate flip.** The aggregate verdict still
gates on the v1 grep result (`gate-c.verdict`). The AST verdict is
recorded but does **not** influence aggregate `PASS`/`FAIL`/`INCONCLUSIVE`
in this release. Once observation across real plans shows the AST
detector is reliable, a follow-up plan flips the aggregate to read
`gate-c.ast.verdict` instead of (or alongside) `gate-c.verdict`.

**Fail-open when `ast-grep` is missing.** If `ast-grep` is not on
`PATH` at run time, the v2 gate writes `SKIP` with reason
`ast-grep not installed`. The aggregate is unaffected — `SKIP` is
treated the same as a missing v2 verdict.

**What this changes for plan authors today.** Nothing yet. Watch the
`findings.md` "Gate C v2" section and the `verdict.json` `gateCAst`
field for divergence from the v1 grep verdict, and report surprising
PASS-vs-FAIL splits on the v2 follow-up issue so the aggregate flip
lands with calibration data.

### Gate D — advisory in v1, by design

Gate D ships as `WARN`-only. Mock-coverage delta has the highest
false-positive rate of the four gates because:

- Some mocks legitimately don't need shape assertions (e.g. an entire
  external SDK stubbed for unrelated reasons).
- Some shape assertions are written in helper files, not the test
  file itself.

We need data on real PRs before deciding the threshold. After ~10
PRs of observed signal, the gate is upgraded to a blocker (or the
heuristic refined first).

## Extending the gates

Each gate is a function in `scripts/orch-reviewer-run.sh`. To add a
fifth gate:

1. Add a fixture pair under `__tests__/orch-reviewer/fixtures/gate-e-{pass,fail}/`.
2. Add a `gate_e()` function in the runner that writes
   `${OUT_DIR}/gate-e.verdict` and `${OUT_DIR}/gate-e.reason`.
3. Add the gate to the dispatch + aggregate block at the bottom of
   the runner.
4. Update `agents/orch-reviewer.md` with the gate's prompt and
   pass/fail criteria.
5. Update this document with the gate's row in the matrix above.
6. `bash __tests__/orch-reviewer/run-fixtures.sh` must still pass.

Keep new gates *deterministic*. Heuristics with a high false-positive
rate ship as `WARN` (advisory, like Gate D), not `FAIL`, until the rate
is measured. A flapping blocker erodes trust faster than a missing one.
