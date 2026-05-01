# Review — Issue #261 / PR #262: ARB-01 live executor gaps

**Reviewer:** Claude (Opus 4.7)
**Date:** 2026-04-30
**Branch:** `orch/261-20260429-arb01-live-executor`
**Verdict:** Do not merge. Three blocking gaps prevent live execution.

---

## Context

PR #262 closes plan issue #261 ("ARB-01 production-ready + shared live
executor layer"). All progress-log items are checked, all 406 tests pass,
`pnpm check` exits 0, both required CI checks (Lint hooks, Test hooks)
are green, and the PR is `MERGEABLE`.

Despite that signal, the strategy will not place a real order with
`--live`. The unit tests pass because they mock the boundary that hides
each gap.

---

## Gap 1 — Token IDs dropped between scan and signal *(blocking)*

**Where:** `canon/templates/strategies/arb-binary/signal.ts:92-101`

`scan.ts` correctly attaches `yesTokenId` and `noTokenId` to each
`MarketData` record. `detectSignals()` then constructs `signal.metadata`
without copying those fields:

```ts
const metadata: Record<string, unknown> = {
  grossEdge,
  totalFees,
  netEdge,
  netReturn,
  cost,
  yesAsk: market.yesAsk,
  noAsk: market.noAsk,
  estimatedSlippage: market.estimatedSlippage,
};
```

In `entry.ts:resolveArbBinaryOrder()` the live executor reads
`meta["yesTokenId"]` and `meta["noTokenId"]`, finds them undefined, and
falls through to:

```ts
const yesTokenId = `${signal.market.market_id}:yes`;
const noTokenId  = `${signal.market.market_id}:no`;
```

Polymarket CLOB token IDs are 77-digit decimal ERC-1155 token IDs. A
string like `0xabc...:yes` is not a valid token ID; `createOrder` will
be rejected by the API before any trade happens.

**Why tests passed:** the entry-point unit test mocks `createOrder`, so
whatever string lands in `params.tokenId` is accepted by the spy. No
test asserts that the token ID looks like a valid CLOB ID, and no test
runs the full `scan → signal → resolveOrder` pipeline.

**Fix:** add the two fields to the metadata object in `signal.ts`
(both signal pushes already spread `{ ...metadata }`):

```ts
const metadata: Record<string, unknown> = {
  // ...existing fields...
  yesTokenId: market.yesTokenId,
  noTokenId: market.noTokenId,
};
```

---

## Gap 2 — Circuit breaker is dead in production *(blocking the plan's own requirement)*

**Where:** `canon/templates/runner.ts` (no caller); `risk.ts:107`

`createRiskChecker` exposes `recordOutcome(won: boolean)`. The unit test
calls it directly to prove the breaker trips after three losses. The
runner — the only caller in production — never calls it.

`runner.ts:processSignal` submits an order via `executor.submit` and
appends an `order_submit` log entry. There is no fill-tracking,
no win/loss attribution, no call to `risk.recordOutcome`. The
`maxConsecutiveLosses=3` constant is therefore an unreachable code
path under live operation; you can lose every trade and the breaker
will never fire.

**Why tests passed:** the breaker test calls `risk.recordOutcome(false)`
directly and then asserts `preTradeCheck` returns `approved: false`. It
does not assert that the runner ever invokes `recordOutcome` for a real
fill outcome.

**Plan requirement violated:** the requirements section of #261 stated
"Risk-checker circuit breaker (`maxConsecutiveLosses=3`) trips and
halts new submissions; verified by test." It is verified in
isolation, not through the runner.

**Fix options:**
- Extend `RunnerDeps` with an optional `onOutcome(signal, result)` hook
  and have the runner call it after `executor.submit` resolves;
  `arb-binary/entry.ts` wires it to `risk.recordOutcome`.
- Or have `executor.submit` return a richer result and let the runner
  compute the win/loss directly.

Either way, the runner needs a path that translates fill state into a
breaker input.

---

## Gap 3 — Allowance hook is unused; order type contradicts plan

**Where:** `canon/templates/strategies/arb-binary/entry.ts:120-129`,
`canon/templates/order-executor.ts:DIRECTION_MAP / urgency mapping`

### 3a — Allowance adapter never injected

`createLiveExecutor` accepts an optional `allowance: AllowanceClient`
and runs `ensureAllowance()` lazily on first submit. `createEntryDeps`
constructs the executor without it:

```ts
const executor = createLiveExecutor({
  resolveOrder: resolveArbBinaryOrder,
  allowanceThreshold: USDC_ALLOWANCE_THRESHOLD,
  allowanceTarget: USDC_ALLOWANCE_TARGET,
});
```

`ensureAllowance()` early-returns when `allowance === undefined`, so the
threshold/target constants are dead. The "idempotent USDC approval"
requirement from the plan is not delivered. Live trading works only if
the wallet was pre-approved by another tool.

**Fix:** ship a concrete `AllowanceClient` (likely an ethers contract
wrapper for USDC's `allowance(owner, CTFExchange)` and `approve`) and
inject it in `createEntryDeps`.

### 3b — Market orders, not FOK limit orders

The plan's decision log explicitly chose **FOK limit orders** for
ARB-01: "ARB requires both legs to fill near-simultaneously; FOK kills
the leg if it can't fully execute, preventing one-sided exposure."

Implementation: signals are emitted with `urgency: "immediate"`
(`signal.ts:116, 127`), and `order-executor.ts` maps:

```ts
const orderType: "market" | "limit" =
  signal.urgency === "immediate" ? "market" : "limit";
```

So immediate → **market**, not FOK limit. A market order on a thinly
quoted leg will fill at whatever depth exists, may slip past the
arbitrage hurdle, and a partial fill on one leg leaves one-sided
exposure — the exact failure mode FOK was chosen to prevent.

**Fix:** either change the urgency mapping to emit FOK limit at the
scanner-detected ask, or add a new urgency tier (`fok`) and map it
explicitly. The order params type must support a `timeInForce: "FOK"`
field.

---

## Summary

| # | Gap | Severity | Plan requirement broken? |
|---|-----|----------|--------------------------|
| 1 | Token IDs dropped in `signal.ts` | Blocking — would 100% fail at first live submit | Yes (live execution) |
| 2 | `recordOutcome` never wired to runner | Blocking — circuit breaker can't trip in production | Yes (verbatim requirement) |
| 3a | Allowance adapter not injected | High — works only with pre-approved wallet | Yes (idempotent USDC approval) |
| 3b | Market orders instead of FOK limit | High — re-introduces one-sided-leg risk | Yes (decision log) |

All three should be addressed before merging or before opening a
follow-up plan.
