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
