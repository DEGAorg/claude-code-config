# MarketClient smoke test

Post-install verification for the venue-agnostic `MarketClient`
abstraction (PR #251 / Phase 1). Designed to be runnable from a fresh
Claude Code session — no prior context needed.

Run the four tiers in order. Each tier has zero or near-zero risk; only
the final tier touches real capital (capped at ~$1).

| Tier | Risk          | Auth needed? | What it verifies                                              |
|------|---------------|--------------|---------------------------------------------------------------|
| 1    | none          | no           | Read paths through the abstraction (search, price, order book) |
| 2    | none          | yes          | Auth wiring (Safe funder, env getters, `signatureType`)        |
| 3    | none          | yes          | Sign path through `tradingCredentials()` — no submission        |
| 4    | ~$0–1         | yes          | Live `createOrder` / `cancelOrder` end-to-end                   |

If Tier 1 or 2 fails, stop — Tier 3+ will fail the same way. Skip
straight to **Failure handling** below.

---

## Prerequisites

```bash
# 1. canon-cli is installed (post-/apply-core)
~/.degacore/bin/canon-cli --help | head -1
# Expected: "canon-cli vX.Y.Z" (no error)

# 2. Add canon-cli to PATH for the session if not already
export PATH="$HOME/.degacore/bin:$PATH"

# 3. Wallet env (Tiers 2-4 only). Either modern WALLET_* or legacy POLYMARKET_*
#    work — env.ts handles both with a deprecation warning on legacy.
export WALLET_PRIVATE_KEY="0x..."        # required for Tiers 2-4
export WALLET_PROXY_ADDRESS="0x..."      # optional; ensureAccount can discover
```

⚠️ For Tier 4 you need **at least 2 USDC.e** on Polygon at the wallet's
Safe proxy. Verify with `canon-cli balance` before proceeding to Tier 4.

---

## Tier 1 — Read-only, no auth (~2 min, zero risk)

Verifies the read paths through the abstraction: `searchMarkets`,
`fetchMarketPrice`, `fetchOrderBook`, `fetchMarketSnapshots`,
`searchMultiOutcomeMarkets`. These all go through `getMarketClient()`
→ `PolymarketAdapter`.

```bash
# 1.1 — searchMarkets
canon-cli market "NBA" 2>&1 | head -20
```

**Pass:** prints a table of markets with `conditionId`, `question`,
`yesPrice`, `noPrice`. Each `yesPrice` and `noPrice` is between 0 and 1.

**Fail signal:** empty output, error mentioning `pmxtjs`, or prices
outside the 0–1 range.

```bash
# 1.2 — pick a conditionId from the previous output
CID="<paste-a-conditionId-here>"

# fetchMarketPrice
canon-cli market --condition "$CID"
```

**Pass:** prints YES + NO price (both 0–1) and a timestamp.

```bash
# 1.3 — fetchOrderBook (now routes through the sidecar; was through the SDK)
TID="<paste-a-yesTokenId-here>"
canon-cli orderbook "$TID" | head -10
```

**Pass:** prints `bids` and `asks` arrays with `price`/`size` pairs.

**Why this matters:** `fetchOrderBook` was switched from the pmxtjs SDK
to the sidecar in this PR (parity with develop's behavior). Empty bids
+ asks could mean the sidecar isn't running; a TypeError on `book.bids`
means the abstraction broke the call shape.

✅ Tier 1 done if all three commands return well-formed output.

---

## Tier 2 — Auth required, read-only (~2 min, zero risk)

Verifies the wallet/auth wiring: `WALLET_PRIVATE_KEY` →
`getWalletPrivateKey()`, proxy discovery, `signatureType` resolution,
and that `tradingCredentials()` is being assembled correctly for read
paths that need auth.

```bash
# 2.1 — fetchPositions
canon-cli position 2>&1 | head -10
```

**Pass:** prints either "no positions" or a table with `marketId`,
`outcomeLabel`, `size`, `entryPrice`, `currentPrice`, `unrealizedPnL`.

**Fail signal:** "WALLET_PRIVATE_KEY required" (env not set), "Derived
credentials are incomplete" (signatureType wrong — abstraction broke
the gnosis-safe resolution), or HTTP 401/403.

```bash
# 2.2 — fetchBalance + on-chain balances
canon-cli balance 2>&1 | head -20
```

**Pass:** prints USDC.e balance from the Safe proxy AND on-chain
balances for the EOA. Both should be non-zero if you've funded the
wallet for testing.

```bash
# 2.3 — fetchOpenOrders
canon-cli order list 2>&1 | head -10
```

**Pass:** prints either "no open orders" or a list with order IDs and
shapes.

✅ Tier 2 done if all three commands authenticate and return data.

**Why this matters:** Tier 2 proves the abstraction preserved the
develop fixes:
- env getters (`WALLET_PRIVATE_KEY` not `POLYMARKET_PRIVATE_KEY`)
- `signatureType: "gnosis-safe"` when a proxy is present
- `funderAddress` set to the Safe proxy

If any of these regressed, the CLOB matcher would reject reads that
need auth.

---

## Tier 3 — Sign without submit (~1 min, zero risk)

Verifies `buildOrder` — exercises `tradingCredentials()` and the full
sign path, but doesn't submit to the matcher. If Tier 2 passed but
this fails, the issue is specifically in the sign path.

```bash
# Pick a low-priced YES token from Tier 1.3 (anything ≤ 0.10)
TID="<paste-a-cheap-yesTokenId>"

canon-cli order build \
  --token "$TID" \
  --side buy \
  --size 1 \
  --price 0.05
```

**Pass:** prints a JSON object with `exchange`, `params`,
`signedOrder`, and `raw`. The `signedOrder` field should be present
(non-empty object) and contain a signature.

**Fail signal:** "balance: 0" (funder address wrong), "invalid
signature" (sigType wrong), or any error mentioning `pmxt-core`
internals.

✅ Tier 3 done if `signedOrder` is present and looks plausible.

---

## Tier 4 — Live tiny order (~$0–1 risk)

THE smoke test. Places a real `createOrder` against the matcher,
confirms it rests, then cancels.

⚠️ **Stop and reconsider** if any of Tiers 1–3 failed. Tier 4 only
makes sense once the read + sign paths are confirmed.

```bash
# Pre-flight: verify wallet has at least 2 USDC.e
canon-cli balance | grep -i usdc

# Pick a deep, liquid market — buy YES at 5 cents far from market price
# so it stays unfilled. Cheap markets are fine.
TID="<paste-a-yesTokenId>"

# 4.1 — Place the order
canon-cli order create \
  --token "$TID" \
  --side buy \
  --size 1 \
  --price 0.05 \
  --type limit
```

**Pass:** returns an order ID and `status: "open"` (or similar
"resting" status — NOT `"matched"` or `"failed"`).

**Fail signal:** any error referencing `balance`, `funder`, or
`signature`. If you see `"status": "matched"`, the price was too close
to the market — cancel the resulting position with `canon-cli position`
+ a sell order, and retry with a lower bid price.

```bash
# 4.2 — Confirm it's resting in the book
canon-cli order list

# 4.3 — Cancel it
ORDER_ID="<paste-the-order-id-from-4.1>"
canon-cli order cancel "$ORDER_ID"
```

**Pass:** `status: "cancelled"` (or equivalent).

```bash
# 4.4 — Confirm cancellation
canon-cli order list
# Expected: order is gone (or shows status: cancelled)
```

✅ Tier 4 done if the order placed cleanly, was visible resting, and
cancelled cleanly.

---

## Cleanup (always run after Tier 4)

```bash
# Cancel any stragglers
canon-cli order list

# If anything is still open, cancel each by ID
canon-cli order cancel <id>

# Sanity-check final state
canon-cli position
canon-cli balance
```

If you accidentally got filled, `canon-cli position` will show the
position. Close it manually with a sell order at the current ask.

---

## What's being verified

The abstraction in PR #251 introduces:

- A venue-agnostic `MarketClient` interface (`canon/templates/client-market.ts`)
- A `PolymarketAdapter` (`canon/templates/adapters/polymarket.ts`) that wraps `pmxtjs`
- A factory `getMarketClient()` selecting adapter via `MARKET_VENUE` env var
- A backwards-compatible shim (`canon/templates/client-polymarket.ts`) that re-exports the legacy named-function API

Each tier exercises a different layer:

| Tier | Layer                                                                |
|------|----------------------------------------------------------------------|
| 1    | Shim → `getMarketClient()` → `PolymarketAdapter` read methods         |
| 2    | + env-getter chain (`WALLET_PRIVATE_KEY` ↔ legacy `POLYMARKET_*`) and `signatureType` resolution |
| 3    | + `tradingCredentials()` builds correct `funderAddress` for Safe-routed accounts |
| 4    | + CLOB matcher accepts the resulting signed order                     |

A complete green run proves the abstraction preserved every behavior
that develop's monolithic `client-polymarket.ts` had, including the
critical Safe-funder routing fix from develop's
`51fd08e4 fix(client-polymarket): route trading via Safe funder + UA override`.

---

## Failure handling

| Symptom                                                | Likely cause                                                       |
|--------------------------------------------------------|--------------------------------------------------------------------|
| `WALLET_PRIVATE_KEY required`                           | Env var not set in current shell — re-export and retry              |
| `Derived credentials are incomplete`                    | `signatureType` not resolving to `gnosis-safe` — check `WALLET_PROXY_ADDRESS` is set or run `canon-cli onboard` |
| `balance: 0` on createOrder                             | `funderAddress` not being passed — abstraction regression in `tradingCredentials()` |
| Cloudflare bot challenge / 403 on read paths            | UA override missing — `clob-axios-defaults` side-effect import not loading |
| Empty order book / sidecar timeout                      | pmxt sidecar not running — start it via `pmxt server` before retrying |
| TypeError on `book.bids`                                | `fetchOrderBook` shape changed — abstraction regression              |

If any failure is reproducible and looks like an abstraction issue
(not env / sidecar / matcher), the relevant code lives in:

- `canon/templates/adapters/polymarket.ts` (adapter implementation)
- `canon/templates/client-market.ts` (interface + factory)
- `canon/templates/client-polymarket.ts` (shim — should be a thin pass-through)

Compare against the develop version of `canon/templates/client-polymarket.ts`
(prior to PR #251) to spot what got lost in the abstraction.
