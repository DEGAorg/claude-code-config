# Market Client Abstraction — Spec

**Status:** Draft
**Owner:** Alberto
**Source of direction:** Carlos (CEO) — "use pmxt now, design for multi-venue later"

---

## Problem

`canon/templates/client-polymarket.ts` is a flat module of functions hard-coded to `Polymarket` from `pmxtjs`. Strategies import named functions directly (`fetchMarketPrice`, `createOrder`, …). There is no interface, no factory, and no path for a second venue.

Concretely, the current shape blocks multi-venue work because:

- The single `getClient()` returns a concrete `Polymarket` instance.
- Exported types are Polymarket-shaped: `conditionId`, `yesTokenId`, `noTokenId`, prices in 0–1.
- Polygon-specific logic is mixed in: USDC.e swaps via Uniswap v3, on-chain balances on Polygon, EIP-712 signing (`signatureType: "eoa"`).
- Sidecar workarounds for `pmxtjs` v2.22.1 header-clobbering live alongside generic code.

Swapping venues today means rewriting every strategy import. We want to add Kalshi (and later Limitless, Myriad, etc.) without touching strategy code.

## Goal

Refactor `client-polymarket.ts` into:

1. A venue-agnostic **`MarketClient`** interface.
2. A **`PolymarketAdapter`** implementing it (current behaviour, unchanged from the strategy's point of view).
3. A **factory** that returns the active adapter based on config / env.
4. Polymarket-only on-chain helpers kept *off* the interface.

Strategies import from `client-market.ts` only.

## Non-goals

- Implementing the Kalshi adapter. (Future work; the interface must be shaped to support it, but no Kalshi code in this change.)
- Changing strategy logic.
- Migrating off `pmxtjs`. We continue to use it as the underlying SDK.
- Building a router/aggregator across venues simultaneously.
- Removing the sidecar workaround. It stays inside the Polymarket adapter.

## Constraints

- pmxt itself does not ship a shared abstract base in TS. Each venue class (`pmxt.Polymarket`, `pmxt.Kalshi`) has overlapping but not identical method shapes. The abstraction is ours, not pmxt's.
- Funding/auth diverges hard across venues:
  - Polymarket = USDC.e on Polygon, EIP-712 signing.
  - Kalshi = USD bank rails, RSA-PSS signing.
  - These details must NOT leak onto the shared interface.
- Price normalization: all interface methods use **0–1** for binary outcome prices. Adapters convert (Kalshi cents → divide by 100).
- TypeScript only. ESM. Node 22 LTS. Strict mode (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `verbatimModuleSyntax`, etc.).

## Proposed file layout

```
canon/templates/
  client-market.ts             ← MarketClient interface + factory + shared types
  adapters/
    polymarket.ts              ← implements MarketClient using pmxtjs Polymarket
    polymarket-onchain.ts      ← Polygon-only helpers (off the interface)
    kalshi.ts                  ← future, not in this change
  client-polymarket.ts         ← DELETED (no shim, no re-export)
```

`client-polymarket.ts` is removed entirely. No backward-compatible re-exports — strategies are updated in the same change.

## Interface surface

`MarketClient` — venue-agnostic, async methods only:

| Method | Purpose |
|---|---|
| `searchMarkets(query)` | Text search → `MarketMatch[]` |
| `fetchMarketPrice(marketId)` | YES/NO snapshot in 0–1 |
| `fetchOrderBook(tokenId)` | Bids/asks |
| `fetchOHLCV(tokenId, opts?)` | Candles |
| `fetchPositions()` | Open positions |
| `fetchBalance()` | Quote-currency balances |
| `fetchMyTrades(params?)` | Trade history |
| `fetchOpenOrders(marketId?)` | Live orders |
| `createOrder(params)` | Place order |
| `cancelOrder(orderId)` | Cancel order |
| `buildOrder(params)` | Dry-run / signed payload, no submit |
| `watchOrderBook(tokenId)` | Streaming snapshot |
| `watchTrades(tokenId)` | Streaming trades |

Shared types in `client-market.ts` use venue-neutral names: `MarketMatch`, `MarketPrice`, `OrderBook`, `PriceLevel`, `Position`, `Balance`, `OrderParams`, `OrderResponse`, `CancelResult`, `BuildOrderResult`, `Trade`, `PriceCandle`. Field names are normalized (`marketId`, `outcomeId`, `yesPrice`, `noPrice` — no `conditionId`, no `yesTokenId`).

## Off-interface (Polymarket-only)

These stay accessible but are imported from `adapters/polymarket-onchain.ts` directly, never via `MarketClient`:

- `swapToUsdce(from, amountIn)`
- `fetchOnChainBalances()`
- The `SWAP_ROUTES` config and Uniswap router/quoter constants.

Rationale: USDC.e + Polygon + Uniswap is meaningless on Kalshi. Forcing them onto the interface would either (a) require Kalshi to throw `NotSupported`, polluting the interface, or (b) leak Polygon details everywhere.

## Factory

```ts
export type Venue = "polymarket"; // | "kalshi" later

export function getMarketClient(venue?: Venue): MarketClient;
```

Selection order:
1. Explicit `venue` argument.
2. `MARKET_VENUE` env var.
3. Default `"polymarket"`.

The factory caches the instance per venue. Adapter constructors read their own env vars (`POLYMARKET_PRIVATE_KEY`, etc.) — the factory does not pass venue-specific config.

## Adapter responsibilities

`PolymarketAdapter`:
- Owns the `pmxtjs` `Polymarket` instance and its lifecycle.
- Maps `pmxtjs` types → shared types (rename `conditionId` → `marketId`, `yesTokenId` → `outcomeId`, etc.).
- Owns the sidecar workaround for `fetchOHLCV`, `watchOrderBook`, `watchTrades`.
- Validates order params (current `validateOrderParams` logic).

`polymarket-onchain.ts`:
- Functions only, no class. Imported directly by code that knows it's on Polygon.
- Reads `POLYMARKET_PRIVATE_KEY`, `POLYGON_RPC_URL`, `SWAP_SLIPPAGE_BPS`.

## Strategy migration

Every strategy under `canon/templates/strategies/**` that imports from `client-polymarket` is updated to import from `client-market`. Imports change shape:

```ts
// before
import { fetchMarketPrice, createOrder } from "../../client-polymarket.js";

// after
import { getMarketClient } from "../../client-market.js";
const market = getMarketClient();
await market.fetchMarketPrice(id);
await market.createOrder(params);
```

Field renames in strategy code (`conditionId` → `marketId`, `yesTokenId` → `outcomeId`) are part of the same change.

## Testing

- Unit tests for `PolymarketAdapter` mocking `pmxtjs` — verify type mapping (especially the rename from `conditionId`/`yesTokenId` to `marketId`/`outcomeId`).
- Unit test for the factory: caching, env-var selection, default.
- Existing strategy tests must pass unchanged (after import updates).
- Order-param validation tests (price range, size, side, type) carried over verbatim.
- No integration tests against live Polymarket in this change.

## Completion criteria (shell-verifiable)

- [ ] `fd client-polymarket.ts canon/templates/` returns nothing.
- [ ] `rg "from .*client-polymarket" canon/` returns nothing.
- [ ] `rg "conditionId|yesTokenId|noTokenId" canon/templates/strategies/` returns nothing.
- [ ] `cd canon/templates && pnpm tsc --noEmit` exits 0.
- [ ] `cd canon/templates && pnpm vitest run` exits 0.
- [ ] `cd canon/templates && pnpm oxlint` exits 0.

## Risks / open questions

- **pmxtjs version churn.** The sidecar workaround exists because of a v2.22.1 bug. If a newer pmxtjs fixes it, we may want to drop the workaround in a follow-up — not in this change.
- **Order-param shape divergence.** Kalshi uses cents and integer sizes; some validation rules (price 0–1) are Polymarket-specific. The interface validates *normalized* params; each adapter may add its own pre-flight checks.
- **Watch methods.** `watchOrderBook` / `watchTrades` are currently single-shot (return one snapshot). True streaming (AsyncIterable) is a future change; keeping the current shape avoids scope creep.
- **`OrderResponse.price` default.** Today, `createOrder` falls back to `params.price` when the SDK omits it. That behaviour is preserved; consider making it explicit in the interface contract.

## Out of scope (explicit)

- Kalshi adapter implementation.
- Cross-venue arbitrage / routing.
- Real streaming (AsyncIterable / event emitters).
- Replacing pmxtjs with a different SDK.
- Changes to the sidecar binary or its protocol.
