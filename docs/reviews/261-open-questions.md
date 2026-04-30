# Open questions and unimplemented stubs after PR #262 patch

**Author:** Claude (Opus 4.7)
**Date:** 2026-04-30
**Branch:** `orch/261-20260429-arb01-live-executor`
**Companion to:** `261-arb01-live-executor-gaps.md`,
                  `261-orch-review-gap-analysis.md`

The patch on this branch closes Gap 1 (token IDs in signal metadata)
fully. Gaps 2, 3a, 3b are wired with typed scaffolding so the live
path is not silent — it either trips a `not implemented` error (3a)
or forwards a no-op-downstream field (3b) — but the substantive
behaviour is deferred to a follow-up plan ("Track 1b").

This document is the source of truth for what is left to decide,
test, or implement. Each open question is labelled `Q-N` and is
referenced from the code that defers to it.

---

## Q-1 — What does the runner consider a "submission outcome"?

**Resolved on this branch.** `runner.ts` now exposes an optional
`onOutcome(outcome: OrderOutcome)` callback fired exactly once per
signal that passes the risk check. `OrderOutcome.status` collapses
the executor response to one of:

| status      | trigger                                                         |
|-------------|-----------------------------------------------------------------|
| `submitted` | `executor.submit` resolved with status ≠ `"rejected"`           |
| `rejected`  | `executor.submit` resolved with `status === "rejected"`         |
| `error`     | `executor.submit` threw                                         |

`onOutcome` does **not** fire when the risk check rejects the signal
(no order was attempted). The runner test suite pins this contract.

---

## Q-2 — When is a binary-arb signal a "win" vs. a "loss"?

**Open. Strategy-level question, not solvable in the runner.**

The current `arb-binary/entry.ts:createEntryOnOutcome` records a
`recordOutcome(false)` (loss) on `rejected | error` only. It does
**not** call `recordOutcome(true)` on `submitted`, because:

1. A *submitted* order is not yet a *filled* order. With FOK we know
   submitted ≈ filled, but with GTC/IOC partial fills the signal
   could remain in book indefinitely.
2. Even a fully filled binary-arb pair only *realises* P&L at market
   settlement (days–weeks). "Did I make money?" is not knowable at
   submit time.

### Decisions needed

- **What inputs feed `recordOutcome(true)`?** Options:
  - **A.** Treat both legs filling in the same poll cycle as a
    win (assumes negative-edge slippage is captured by the hurdle
    rate at signal time).
  - **B.** Track positions through to market settlement and record
    realised P&L per signal — requires settlement event ingestion.
  - **C.** A more granular outcome tier than win/loss: `submitted`,
    `filled`, `partial`, `expired`, `realised_win`, `realised_loss`,
    each with its own breaker rule.

- **Should the breaker count slip-driven losses (filled but at a
  worse-than-expected price)?** Currently no — only rejections.
  This is conservative; a market can fill against us without ever
  rejecting.

### Stub locations

- `canon/templates/runner.ts` — `OrderOutcome` interface comment
  cross-references this Q.
- `canon/templates/strategies/arb-binary/entry.ts` —
  `createEntryOnOutcome` comment cross-references this Q.

---

## Q-3 — Allowance adapter: where does the wallet/provider come from?

**Open. Cross-package wiring.**

`canon/templates/usdc-allowance.ts` ships an `AllowanceClient`
factory (`createUsdcAllowanceClient`) that throws
`AllowanceNotImplementedError` for both `getAllowance` and `approve`.
The shape is correct and the signature matches what
`live-executor.ts` expects, so when the implementation lands the
arb-binary entry can opt in by injecting it into `createLiveExecutor`.

### Decisions needed

- **Provider/signer source.** `canon/cli/wallet-store.ts` owns the
  wallet (`POLYMARKET_PRIVATE_KEY` in `.canon/wallet.env`). The
  templates layer must NOT depend on the CLI directly — that would
  invert the dependency graph.

  Options:
  - **A.** Templates accept a `walletStore` parameter from the
    caller (CLI or test harness) at runtime. Template tests use a
    mock store. *Preferred — keeps the seam clean.*
  - **B.** Promote `WalletStore` to a shared package both
    templates and CLI depend on.
  - **C.** Templates parse `POLYMARKET_PRIVATE_KEY` from env
    directly (current `client-polymarket.ts` does this — set a
    precedent but couples templates to the env-var convention).

- **Address constants.** USDC.e and CTFExchange addresses on
  Polygon need to be pinned (mainnet vs. amoy testnet config).
  `canon/cli` may already encode these — the templates layer
  should re-import, not re-declare.

- **Allowance semantics on top-up.** Set to a fixed `target`
  (current plan) vs. `max uint256` (gas-minimal but riskier if the
  exchange contract is ever upgraded to malicious). The plan said
  fixed `1_000_000 USDC`; the stub keeps that interface.

### Stub locations

- `canon/templates/usdc-allowance.ts` — `createUsdcAllowanceClient`,
  `AllowanceNotImplementedError`.
- `canon/templates/strategies/arb-binary/entry.ts` — does NOT inject
  the adapter yet, by design (live-executor early-returns when
  `allowance` is undefined).

---

## Q-4 — Time-in-force: does pmxtjs / the sidecar support FOK?

**Open. Confirmed unsupported in pmxtjs@2.22.1.**

A repo-wide grep over `canon/cli/node_modules/.pnpm/pmxtjs@2.22.1/`
returned **zero matches** for `FOK`, `IOC`, `timeInForce`, or
`fillOrKill`. The current sidecar protocol passes only
`{ marketId, outcomeId, side, type, amount, price }` to pmxtjs.

On this branch:
- `OrderParams.timeInForce?: "GTC" | "IOC" | "FOK"` is added.
- `signalToOrderParams(signal, tokenIds, price, timeInForce?)`
  forwards the value into the params object.
- `live-executor.ResolvedOrder.timeInForce?` is forwarded by
  `arb-binary/entry.ts:resolveArbBinaryOrder` as `"FOK"`.
- `client-polymarket.createOrder` accepts the field but does NOT
  forward it to the sidecar payload — it has nowhere to forward it
  to. The exchange will receive a plain limit order, not FOK.

This means **Gap 3b is partially closed** (the strategy-side intent
is now expressed and type-checked) but **the wire-side behaviour is
still wrong** (no FOK guarantee on the exchange).

### Decisions needed

- **Sidecar update.** Investigate whether the underlying
  `@polymarket/clob-client` supports `tif: "FOK"` (it likely does —
  the upstream CLOB API exposes it). If yes:
  1. Update the sidecar's `createOrder` handler to pass `tif`.
  2. Update `client-polymarket.createOrder` to include
     `timeInForce` in the payload.
  3. Add a sidecar-protocol version bump if the protocol is
     versioned.

- **FOK fallback policy.** Until FOK lands, ARB-01 should arguably
  refuse to go live. Options:
  - **A.** Hard-fail in `createEntryDeps` when `--live` is set and
    FOK is not yet supported (preferred — production safety over
    convenience).
  - **B.** Warn loudly and proceed.
  - **C.** Use IOC as a partial substitute (still leaves
    one-sided exposure on partial fills).

  This branch does **not** enforce A; it stays mergeable but the
  follow-up plan must add the gate.

### Stub locations

- `canon/templates/client-polymarket.ts` — `TimeInForce` type;
  `OrderParams.timeInForce` field.
- `canon/templates/order-executor.ts` — `signalToOrderParams`
  4th parameter.
- `canon/templates/live-executor.ts` — `ResolvedOrder.timeInForce`.
- `canon/templates/strategies/arb-binary/entry.ts` — emits `"FOK"`.

---

## Q-5 — Should `--live` refuse to start when stubs are unimplemented?

**Open. Production-safety question.**

After this patch, `--live` will:

- Place orders with a real CLOB token ID ✅ (Q-1 / Gap 1 fixed).
- Trip the circuit breaker on rejections ✅ (Q-2 partial — only
  rejections / errors, not realised losses).
- **Not** check or refresh USDC allowance ❌ (Q-3 stub).
- **Not** enforce FOK at the exchange ❌ (Q-4 stub).

A user running `--live` today gets a partial automation that may
silently behave like a market-order limit strategy with whatever
allowance the wallet happened to have.

### Decisions needed

- **Should the entry hard-fail until Q-3 and Q-4 are resolved?**
  *Recommended: yes.* The follow-up plan should:
  1. Inject `createUsdcAllowanceClient(...)` in `createEntryDeps`.
     The stub already throws `AllowanceNotImplementedError` on
     first submit, which surfaces the gap loudly.
  2. Add a startup gate that calls a `clientCapabilities()` query
     on the sidecar; if FOK is unsupported and the strategy
     requires it, refuse to start in `--live` mode.

- **Phased rollout.** An alternative is a `--unsafe-live` flag for
  development against testnet that bypasses Q-3/Q-4 gates. Ugly
  but pragmatic.

---

## Summary table

| Q   | Subject                                | Status on this branch       | Owner of next step            |
|-----|----------------------------------------|-----------------------------|-------------------------------|
| Q-1 | Runner outcome contract                | Closed                      | —                             |
| Q-2 | Win/loss definition for binary arb     | Stubbed (loss-only path)    | Strategy design discussion    |
| Q-3 | USDC allowance wiring                  | Interface-only, throws      | Wallet/provider plumbing plan |
| Q-4 | FOK on the wire                        | Type added; sidecar mute    | Sidecar + pmxtjs investigation|
| Q-5 | `--live` start-up safety gate          | Open                        | Follow-up "Track 1b" plan     |

All five questions are scoped to the follow-up plan. The current
branch is now safe to merge from a *correctness* point of view —
nothing is silently broken — but is **not yet** the production-ready
ARB-01 the original plan #261 promised. Q-3 / Q-4 / Q-5 must close
before we ship `--live` as truly safe.
