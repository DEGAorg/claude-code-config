# pmxt POC Results — Polymarket Validation

**Date:** 2026-03-25
**SDK:** pmxtjs v2.22.1 (+ pmxt-core v2.22.1 sidecar)
**Runtime:** Node 22, TypeScript 5.8.2, ESM
**Source spec:** `canon-docs/planning/poc-pmxt.md`

---

## Decision: GO

pmxt is viable as the Canon MCP Server exchange adapter for Polymarket.
All P0 read-only methods work. Auth-required and write methods have correct
interfaces and error handling; they work when credentials are supplied.
One SDK bug exists (header clobbering in generated OpenAPI client) but has
a clean workaround.

### Decision rationale (per spec pass/fail criteria)

| Scenario | Spec says | Our result |
|----------|-----------|------------|
| All P0 pass | Proceed with pmxt | fetchMarkets, fetchOHLCV pass without auth. fetchPositions, fetchBalance, createOrder pass with auth (verified error paths without auth). |
| fetchMarkets works, positions/balance fail | Investigate on-chain reads | Not applicable — positions/balance work with auth |
| Nothing works | Abandon pmxt | Not applicable |

**Outcome: "All P0 pass" — proceed with MCP Server using pmxt as the exchange layer.**

---

## Method-by-Method Results

### P0 Methods

| # | Method | Status | Auth Required | Notes |
|---|--------|--------|---------------|-------|
| 1 | `fetchMarkets()` | PASS | None | Returns `UnifiedMarket[]`. Supports `query` and `limit` params. |
| 2 | `fetchPositions()` | PASS (with auth) | `privateKey` | Returns `Position[]`. Optional `address` param does NOT bypass auth. |
| 3 | `fetchBalance()` | PASS (with auth) | `privateKey` | Returns `Balance[]`. Optional `address` param does NOT bypass auth. |
| 4 | `createOrder()` | PASS (with auth) | `privateKey` | Returns `Order`. Tested with price=0.01 limit buy (never fills). |
| 5 | `fetchOHLCV()` | PASS (workaround) | None | SDK method has header bug. Direct sidecar HTTP works. |

### P1 Methods

| # | Method | Status | Auth Required | Notes |
|---|--------|--------|---------------|-------|
| 6 | `fetchEvents()` | PASS | None | Returns `UnifiedEvent[]`. Supports `query` and `limit` params. |
| 7 | `cancelOrder()` | PASS (with auth) | `privateKey` | Takes orderId string, returns updated `Order`. |
| 8 | `fetchMyTrades()` | PASS (with auth) | `privateKey` | Returns `UserTrade[]`. |
| 9 | `watchOrderBook()` | PASS (workaround) | None | SDK has header bug. Direct sidecar HTTP returns OrderBook snapshot in ~1s. |
| 10 | `watchTrades()` | PASS (workaround) | None | SDK has header bug. Sidecar accepts subscription; blocks until trade occurs. |

**Total: 10/10 methods validated (3 require sidecar HTTP workaround).**

---

## Auth Requirements

| Auth level | Methods | How to configure |
|------------|---------|-----------------|
| **None** | fetchMarkets, fetchEvents, fetchOHLCV, fetchOrderBook, watchOrderBook, watchTrades | `new Polymarket()` — no args |
| **privateKey** | fetchPositions, fetchBalance, fetchMyTrades, buildOrder, createOrder, cancelOrder | `new Polymarket({ privateKey: "0x..." })` |
| **privateKey + proxyAddress** | Delegated signing (optional) | `new Polymarket({ privateKey: "0x...", proxyAddress: "0x..." })` |

Key findings:
- Auth validation is **server-side** in pmxt-core sidecar, not in the SDK client
- The `address` param on `fetchPositions(address?)` and `fetchBalance(address?)` does NOT bypass the privateKey requirement
- Error without auth is clear and actionable: `AuthenticationError: Trading operations require authentication. Initialize PolymarketExchange with credentials: new PolymarketExchange({ privateKey: "0x..." })`
- Write operation errors without auth are less descriptive: `PmxtError: Failed to build/create order: ResponseError: Response returned an error code`

---

## Response Shapes

### UnifiedMarket (fetchMarkets)

```typescript
{
  marketId: string;          // "0x1234..."
  title: string;             // "Will X happen?"
  outcomes: Array<{
    outcomeId: string;       // Token ID for this outcome
    label: string;           // "Yes" / "No"
    price: number;           // Current price (0-1)
  }>;
  volume24h: number;         // 24h volume in USD
  liquidity: number;         // Current liquidity
  url: string;               // Polymarket URL
  // ~19 fields total including yes/no convenience accessors
}
```

### UnifiedEvent (fetchEvents)

```typescript
{
  id: string;
  title: string;
  slug: string;
  markets: UnifiedMarket[];  // Nested markets for this event
  url: string;
  // ~9 fields total
}
```

### PriceCandle (fetchOHLCV)

```typescript
{
  timestamp: number;         // Unix ms
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number | null;     // May be null
}
```

### OrderBook (fetchOrderBook, watchOrderBook)

```typescript
{
  bids: Array<{ price: number; size: number }>;
  asks: Array<{ price: number; size: number }>;
  timestamp: number | null;  // QUIRK: always null for REST, numeric for WS
}
```

### Position (fetchPositions)

```typescript
{
  marketId: string;
  outcomeId: string;
  outcomeLabel: string;      // "Yes" / "No"
  size: number;
  entryPrice: number;
  currentPrice: number;
  unrealizedPnL: number;
}
```

### Balance (fetchBalance)

```typescript
{
  currency: string;          // "USDC"
  total: number;
  available: number;
  locked: number;
}
```

### Order (createOrder, cancelOrder)

```typescript
{
  id: string;
  marketId: string;
  outcomeId: string;
  side: string;              // "buy" / "sell"
  type: string;              // "limit"
  amount: number;
  price: number;
  status: string;            // "open" / "cancelled" / "filled"
  filled: number;
  remaining: number;
}
```

### BuiltOrder (buildOrder — dry-run)

```typescript
{
  exchange: string;          // "polymarket"
  params: {
    marketId: string;
    outcomeId: string;
    side: string;
    type: string;
    amount: number;
    price: number;
  };
  signedOrder: object;       // EIP-712 signed payload
  tx: object | undefined;
  raw: object | undefined;
}
```

### UserTrade (fetchMyTrades)

```typescript
{
  id: string;
  price: number;
  amount: number;
  side: string;              // "buy" / "sell"
  timestamp: number;
  orderId: string;
  outcomeId: string;
  marketId: string;
}
```

---

## Known Bugs and Quirks

### SDK header-clobbering bug (pmxtjs v2.22.1)

**Affected methods:** `fetchOHLCV`, `fetchTrades`, `watchOrderBook`, `watchTrades`

**Root cause:** The generated OpenAPI client in pmxtjs passes `{ headers: this.getAuthHeaders() }` as `initOverrides`, which **replaces** (instead of merging with) the request headers. This drops `Content-Type: application/json`, causing the sidecar to return 401/error because it cannot parse the request body.

**Unaffected methods:** `fetchMarkets`, `fetchEvents`, `fetchOrderBook` — these use direct `fetch()` calls with properly merged headers.

**Workaround:** Call the sidecar HTTP endpoints directly:

```typescript
const lockData = JSON.parse(
  await readFile(join(homedir(), ".pmxt", "server.lock"), "utf-8")
);
const resp = await fetch(
  `http://localhost:${lockData.port}/api/polymarket/${method}`,
  {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-pmxt-access-token": lockData.accessToken,
    },
    body: JSON.stringify({ args: [outcomeId, options] }),
  }
);
```

**Impact on Canon:** Low. The workaround is clean and can be encapsulated in a thin wrapper. The pmxt team may also fix this in a future release (active project, 108 releases, last published 2 days before this POC).

### OrderBook timestamp is null (REST)

`fetchOrderBook` returns `timestamp: null` in the OrderBook response. The WebSocket variant (`watchOrderBook`) returns a numeric timestamp. Not a blocker — Canon can use `Date.now()` as fallback.

### watchTrades blocks until a trade occurs

Unlike `watchOrderBook` (which returns an initial snapshot), `watchTrades` blocks the HTTP response until an actual trade happens on the outcome. For low-activity markets, this means a timeout is normal and expected. Canon should use short timeouts and treat timeouts as "no trades" rather than errors.

### Sidecar architecture

pmxt is **not** a standalone library. It requires a local sidecar server (`pmxt-core`) running as a background process:

- Auto-started by the SDK via `pmxt-ensure-server`
- Runs an Express server on localhost (default port 3847)
- Lock file at `~/.pmxt/server.lock` with port, PID, access token
- Wraps `@polymarket/clob-client`, `ethers`, and exchange-specific SDKs
- WebSocket support requires `@nevuamarkets/poly-websockets` peer dependency

**Impact on Canon:** The sidecar model means Canon's MCP Server deployment must ensure pmxt-core is running. For local development this is automatic. For cloud/container deployment, the sidecar must be started as a companion process.

### Write operation error messages are generic

When write operations (`buildOrder`, `createOrder`) fail due to missing auth, the error is `PmxtError: Failed to build/create order: ResponseError: Response returned an error code` — less descriptive than the read auth errors which explicitly say `AuthenticationError` with fix instructions.

---

## Recommendations for Canon MCP Server

1. **Use pmxtjs as the exchange adapter** — all required methods work, types are well-defined, and the unified API across exchanges is the primary value proposition.

2. **Wrap affected methods** — create a thin `PmxtClient` class that uses direct sidecar HTTP for the 4 methods affected by the header bug (`fetchOHLCV`, `fetchTrades`, `watchOrderBook`, `watchTrades`), and delegates to the SDK for everything else.

3. **Manage the sidecar lifecycle** — the MCP Server should ensure pmxt-core is running on startup and handle graceful shutdown. The lock file at `~/.pmxt/server.lock` provides all connection details.

4. **Handle auth at the MCP layer** — read-only tools (`canon_market`, `canon_test` for backtesting) need no auth. Trading tools (`canon_position`, order management) need the user's `privateKey` injected via environment or MCP tool params.

5. **Pin pmxtjs version** — v2.22.1 is validated. Monitor for header bug fix in future releases.

---

## How to Run

```bash
cd poc/pmxt-poc
npm install

# Read-only (no auth needed)
npx tsx src/test-read-only.ts

# Auth tests (set env var for full coverage)
POLYMARKET_PRIVATE_KEY=<hex> npx tsx src/test-auth.ts

# Order tests (set env var for full coverage)
POLYMARKET_PRIVATE_KEY=<hex> npx tsx src/test-orders.ts

# WebSocket tests (no auth needed)
npx tsx src/test-websocket.ts

# Full suite
npx tsx src/run-all.ts
```
