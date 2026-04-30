# Why these gaps were not caught by the orchestrator review flow

**Author:** Claude (Opus 4.7)
**Date:** 2026-04-30
**Companion to:** `261-arb01-live-executor-gaps.md`
**Subject:** PR #262 / issue #261 reached `plan:pr-review` status with three
blocking gaps. None of the orch's quality gates flagged them.

---

## What the orchestrator did right

The orch + worker chain produced something that *looks* complete:

- All six progress-log items checked.
- 36 new tests authored, all passing.
- Repo-wide `pnpm check` (typecheck + oxlint + 406 vitest tests) exits 0.
- Both required CI checks (Lint hooks, Test hooks) green.
- PR is mergeable, descriptive, and labelled `plan:pr-review`.

The plan-authoring guardrails (rules/exec-plans.md) were honoured:
≤10 items, ≤3 files per item, dep depth ≤5, TDD ordering, shell-verifiable
completion criteria. The plan itself is well-formed.

## What the orchestrator missed

The PR cannot place a real order, but every signal the orch consumes says
"this is done." The breakdown is structural, not random:

### 1. Completion criteria measured the build, not the behaviour

Every completion criterion in #261 was a **command that proves the code
compiles, lints, and that the unit tests pass**:

```
- [ ] `pnpm vitest run __tests__/live-executor.test.ts` exits 0
- [ ] `pnpm vitest run __tests__/live-positions.test.ts` exits 0
- [ ] `pnpm vitest run strategies/arb-binary/__tests__/entry.test.ts` exits 0
- [ ] `pnpm check` exits 0
- [ ] `grep -c "stubExecutor\|stubPositions" entry.ts` returns 0
- [ ] `grep -c "Ported (live"  STRATEGY-INDEX.md` is at least 1
```

None of them test that **the live wiring actually produces a valid CLOB
order**. The closest was the `grep -c "stubExecutor"` check, which only
confirms the *string* "stubExecutor" was deleted — not that what
replaced it works.

This is the most important lesson: **shell-verifiable ≠ behaviour-
verifiable**. The orchestrator currently optimises for the former.

### 2. TDD ordering enforced "tests before code", but the tests were written against the same mocks the implementation uses

The TDD rule in `rules/exec-plans.md` is:

> When a plan touches application code, test items must run before or
> alongside implementation items.

That happened. But the worker authored tests that mock
`client-polymarket.js` at the module boundary — the **same boundary**
where Gaps 1 and 3a hide:

- Gap 1: `createOrder` is mocked to return `{ id: "ord-test", status: "submitted" }` regardless of `params.tokenId`. So a synthetic `cond-001:yes` token ID is indistinguishable from a real 77-digit CLOB ID.
- Gap 3a: nothing inspects allowance behaviour because `getAllowance` was never called (no adapter injected); the mocked `createOrder` doesn't care.

The worker followed TDD correctly. The tests still failed to test the
risky surface, because **the mocks erase the risky surface**.

### 3. Reviewer step did not read upstream into the call graph

`plan:pr-review` implies a reviewer pass exists, but the gaps were
discoverable only by following data flow across files:

- Gap 1: `scan.ts` → `signal.ts` → `entry.ts:resolveArbBinaryOrder`.
- Gap 2: `risk.ts:recordOutcome` → grep across the whole repo for callers → confirm none in `runner.ts`.
- Gap 3b: `signal.ts:urgency = "immediate"` → `order-executor.ts:DIRECTION_MAP / urgency mapping` → cross-reference with the plan's decision log.

The review step appears to have looked at each changed file in
isolation rather than tracing the path a real signal would take from
detection to submission. None of these gaps requires deep domain
knowledge — all three are visible in <5 minutes of grep + read.

### 4. The plan's own decision log was never re-checked against the implementation

The plan committed to "FOK limit orders" in the decision log. The
implementation emits market orders. No step in the orch flow re-reads
the decision log and checks it against the diff. Decision logs in the
plan are aspirational by default; the orch treats progress checkboxes
as the source of truth for "done", and progress checkboxes don't
mention FOK.

### 5. Mocks-only test policy hid two of three gaps

Plan #261 deliberately said:

> Mock client-polymarket at the module boundary; do NOT call live CLOB
> in unit tests.

That is correct supply-chain hygiene — but it means the plan ships
**without** any test that exercises the real wiring once. The `grep -c
"stubExecutor" returns 0` criterion is a substitute, and a weak one.

A "smoke test that constructs a signal end-to-end and asserts
`createOrder` was called with a token ID matching the CLOB pattern
`/^\d{60,}$/`" would have caught Gap 1 immediately.

---

## How I (the human-side reviewer) found the gaps

I'm including this so the orch's reviewer agent can replicate the
process programmatically.

1. **Read the executor first** — `live-executor.ts`. Saw it expects
   `tokenIds.yes/no` from `resolveOrder(signal)`.
2. **Followed `resolveOrder` upstream** — `entry.ts:resolveArbBinaryOrder`.
   Saw `meta["yesTokenId"]` reads with a string-fallback. Asked: **does
   the metadata actually contain that key?**
3. **Read `signal.ts`** — saw the metadata literal. Token IDs absent.
   Confirmed Gap 1.
4. **Searched for the circuit-breaker wiring** —
   `grep -n "recordOutcome" runner.ts risk.ts entry.ts`. Two hits in
   `risk.ts` (definition) and zero in `runner.ts` or `entry.ts`.
   Confirmed Gap 2.
5. **Searched for the allowance adapter injection** — read
   `createEntryDeps` for `allowance:` key. Absent. Confirmed Gap 3a.
6. **Cross-checked plan decisions against implementation** — read the
   plan's decision log row by row. "FOK limit orders" → grep
   `order-executor.ts` for `FOK` or `timeInForce`. No matches; urgency
   maps to market. Confirmed Gap 3b.

Total time: about 8 minutes. None of this required tooling beyond
`grep`, `cat`, and reading 5 files.

---

## Concrete improvements for the orchestrator review step

These map directly to the failure modes above.

### A. Add an "integration trace" gate to plans that wire live infra

For any plan that touches an executor / position / wallet path, require
**one** completion-criterion test that constructs a real `TradeSignal`,
runs it through the full chain (`scan` → `signal` → `resolveOrder` →
`signalToOrderParams`), and asserts on the **shape** of the params
that would be sent to the API — token ID format, side, orderType,
size > 0, price ∈ [0,1].

This catches Gap 1 with one assertion: the token ID matches the CLOB
ID format.

### B. Add a "decision-log audit" step to the reviewer agent

After progress items are marked done, the reviewer agent should:
1. Parse the plan's decision log table.
2. For each decided choice (e.g. "FOK limit orders"), grep the diff
   for evidence (`FOK`, `timeInForce`, etc.).
3. If no evidence, flag the row as "decision not reflected in code"
   and require a justification or a fix.

Catches Gap 3b.

### C. Add a "wiring graph" step to the reviewer agent

For every named hook the plan introduces (`recordOutcome`, `allowance`,
`onOutcome`, etc.), the reviewer agent should:
1. Find its definition.
2. Grep the repo for callers.
3. If the only callers are unit tests, flag the hook as "exposed but
   unwired in production" and require either a caller or an explicit
   "intentionally unwired in this phase" note in the plan.

Catches Gaps 2 and 3a.

### D. Add a "mock-coverage delta" check

When tests mock a module, the reviewer agent should compare:
- The set of arguments the test passed to the mock.
- The set of arguments the **production caller** passes.

If the production caller passes shapes the test never exercises (e.g.
a synthetic `cond-001:yes` token ID instead of a 77-digit number), the
gap is flagged.

This is harder, but the simpler version — "diff the test's arg shape
against the production type's stricter constraints" — would catch
many of these.

### E. Strengthen the meaning of `plan:pr-review`

Currently `plan:pr-review` means "tests pass, PR opened, awaiting
human merge." It should mean "all of A–D have run, with reviewer
findings either resolved or explicitly waived."

A separate `plan:tests-pass` status could mark the intermediate state
so the existing label still has a meaning during transition.

---

## Closing observation

The orchestrator is a strong **execution** engine and a weak **review**
engine. Plan-authoring guardrails caught structural mistakes
(too-deep dep chains, vague criteria, files-per-item) — that's
visible, valuable work. The review gap is symmetric: review needs its
own enforced rule set, not just "the worker was diligent." The four
gates above (A–D) are concrete enough to implement as a single
reviewer-agent skill that runs before `plan:pr-review` is applied.

Until that exists, every plan whose acceptance is "tests pass" is at
risk of looking complete while being inert.
