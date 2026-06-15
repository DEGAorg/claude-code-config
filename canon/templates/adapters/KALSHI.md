# Kalshi adapter

A TypeScript reference implementation of Canon's venue-agnostic
[`MarketClient`](../client-market.ts) interface against
[Kalshi's](https://kalshi.com) demo trading API.

Shipped 2026-05-15 in [#345](https://github.com/DEGAorg/claude-code-config/pull/345).

## Status

| Surface | Today | Planned |
|---|---|---|
| Transport | **REST only** (HTTP/JSON over `fetch`) | WebSocket for `watch*` (Phase 2) |
| Environment | Demo (`demo-api.kalshi.co`) | Prod via env-var flip |
| Order placement | Live-verified end-to-end (place + cancel) on demo | — |

Read this before reading the code: **`watchOrderBook` and `watchTrades`
are REST snapshot calls, not WebSocket subscriptions.** The method names
come from the shared `MarketClient` interface, which is shaped to allow a
future switch to `AsyncIterable<OrderBook>` once a real WS subscriber
lands. Today both methods do a single REST call and return. See
[Capability matrix](#capability-matrix) below.

## File map

```
canon/templates/
├── adapters/
│   ├── kalshi.ts                 ← Adapter; 14 MarketClient methods
│   └── kalshi-auth.ts            ← RSA-PSS signer + header builder
├── __tests__/
│   ├── adapters/
│   │   ├── kalshi.test.ts        ← Adapter unit tests (fixture-driven)
│   │   └── kalshi-auth.test.ts   ← Signer unit tests
│   └── fixtures/kalshi/          ← 11 captured demo responses, sanitized
├── scripts/
│   └── kalshi-demo-smoke.ts      ← Env-gated live smoke against demo
└── client-market.ts              ← Interface; Kalshi registered in VENUE_FACTORIES
```

## Quickstart

The adapter is exposed through the venue factory in
[`client-market.ts`](../client-market.ts):

```ts
import { getMarketClient } from "./client-market.js";

const client = getMarketClient("kalshi");

// Public read — no credentials needed
const matches = await client.searchMarkets("KXNAMEDSTORM");
const book = await client.fetchOrderBook(`${matches[0].marketId}:YES`);

// Authenticated — requires KALSHI_API_KEY_ID + KALSHI_PRIVATE_KEY_PATH
const balance = await client.fetchBalance();
const placed = await client.createOrder({
  marketId: `${matches[0].marketId}:YES`,
  side: "buy",
  price: 0.05,
  size: 1,
  orderType: "limit",
  timeInForce: "GTC",
});
```

## Environment variables

| Var | Required | Default | Purpose |
|---|---|---|---|
| `KALSHI_API_KEY_ID` | Auth calls only | — | Kalshi API key UUID |
| `KALSHI_PRIVATE_KEY_PATH` | Auth calls only | — | Absolute path to PEM-encoded RSA private key |
| `KALSHI_API_BASE` | No | `https://demo-api.kalshi.co/trade-api/v2` | REST base URL. Set to `https://api.elections.kalshi.com/trade-api/v2` for prod. |

Auth calls without credentials throw a typed `KalshiAuthError` with a
clear message. Public-read methods work with no env vars set.

To generate an API key: Kalshi web app → Settings → API Keys. The UUID
goes into `KALSHI_API_KEY_ID`; the downloaded PEM file's path goes into
`KALSHI_PRIVATE_KEY_PATH`. Demo and prod use separate keys.

## Authentication

Kalshi authenticates each REST call with three headers, built by
[`kalshi-auth.ts`](kalshi-auth.ts):

```
KALSHI-ACCESS-KEY        UUID identifying the API key
KALSHI-ACCESS-TIMESTAMP  Milliseconds since epoch (string)
KALSHI-ACCESS-SIGNATURE  base64(RSA-PSS(timestamp + METHOD + path))
```

- Signature payload: `timestamp` + uppercase HTTP method + request path
  (no query string, no host).
- Algorithm: RSA-PSS with SHA-256, MGF1-SHA-256, salt length = 32 bytes.
- The signer caches loaded PEMs by path to avoid re-reading on every
  call. No session tokens — every request is independently signed.

## Capability matrix

All 14 methods of [`MarketClient`](../client-market.ts) are implemented.

| Method | Transport | Auth | Notes |
|---|---|---|---|
| `searchMarkets` | REST | No | `GET /markets?status=open&limit=100&event_ticker=…` |
| `fetchMarketPrice` | REST | No | `GET /markets/{ticker}` — dollar strings → 0–1 numbers |
| `fetchOrderBook` | REST | No | `GET /markets/{ticker}/orderbook` |
| `fetchOHLCV` | REST | No | `GET /series/{series}/markets/{ticker}/candlesticks` |
| `fetchMarketSnapshots` | REST | No | Composite — search + per-market snapshot |
| `searchMultiOutcomeMarkets` | REST | No | `GET /events?with_nested_markets=true` |
| `getCapabilities` | local | No | Returns `{ supportsTif: true }` |
| `fetchBalance` | REST | Yes | `GET /portfolio/balance` |
| `fetchPositions` | REST | Yes | `GET /portfolio/positions` |
| `fetchMyTrades` | REST | Yes | `GET /portfolio/fills` |
| `fetchOpenOrders` | REST | Yes | `GET /portfolio/orders?status=resting` |
| `createOrder` | REST | Yes | `POST /portfolio/orders` — see [order shape](#order-shape) |
| `cancelOrder` | REST | Yes | `DELETE /portfolio/orders/{id}` |
| `buildOrder` | local | No | Validates + shapes the body, no HTTP call |
| `ensureAccount` | REST | Yes | `GET /portfolio/balance` — auth probe |
| **`watchOrderBook`** | **REST snapshot** | No | Single `fetchOrderBook` call + timestamp. **Not a WS subscription.** |
| **`watchTrades`** | **REST snapshot** | No | Single `GET /markets/trades?limit=100`. **Not a WS subscription.** |

### Order shape

`createOrder` / `buildOrder` translate the interface's `OrderParams`
into Kalshi's `POST /portfolio/orders` body:

| Interface | Kalshi |
|---|---|
| `marketId` ending in `:YES` or `:NO` | `ticker`, `side` (`yes` / `no`) |
| `side: "buy" \| "sell"` | `action: "buy" \| "sell"` |
| `price` (0–1 number) | `yes_price_dollars` / `no_price_dollars` (`"0.0500"` string, 4 decimals) |
| `size` (integer contracts) | `count` |
| `orderType` | `type` (`limit` / `market`) |
| `timeInForce` `GTC` / `IOC` / `FOK` | `time_in_force` `good_till_canceled` / `immediate_or_cancel` / `fill_or_kill` |

The TIF snake_case mapping and the dollar-string price format are
**required**: Kalshi removed the legacy integer-cent fields (`yes_price`
as integer) in March 2026, and rejects the interface's TIF enums
verbatim.

## Identifier conventions

- `marketId` — the Kalshi market ticker (e.g. `KXNAMEDSTORM-26DEC01CPACTOT-2`).
- `outcomeId` — the same ticker suffixed with `:YES` or `:NO`. Kalshi
  contracts trade both sides on a single ticker; the suffix carries the
  side through the venue-neutral interface.
- Prices — all interface methods use 0–1 normalized numbers. The
  adapter parses Kalshi's dollar strings (`"0.6500"` → `0.65`) on the
  way in and emits 4-decimal dollar strings on the way out.

## Verifying it works

### Unit tests (no credentials)

```bash
cd canon/templates
pnpm install
pnpm exec vitest run __tests__/adapters/kalshi.test.ts __tests__/adapters/kalshi-auth.test.ts
pnpm exec tsc --noEmit
```

67 tests pass against the 11 sanitized demo fixtures in
`__tests__/fixtures/kalshi/`.

### Live demo smoke (requires credentials)

The opt-in smoke script drives the full surface — public read, signed
portfolio reads, and optionally a real order place + cancel — against
the demo environment.

```bash
# Public read + signed reads only (default)
RUN_LIVE=1 \
  KALSHI_API_KEY_ID=<uuid> \
  KALSHI_PRIVATE_KEY_PATH=/absolute/path/to/key.pem \
  pnpm --filter canon-templates exec tsx scripts/kalshi-demo-smoke.ts

# Place + cancel a real 1-contract order @ $0.01
RUN_LIVE=1 RUN_ORDER=1 \
  KALSHI_API_KEY_ID=<uuid> \
  KALSHI_PRIVATE_KEY_PATH=/absolute/path/to/key.pem \
  pnpm --filter canon-templates exec tsx scripts/kalshi-demo-smoke.ts
```

The script defaults to the `KXNAMEDSTORM` series; override with
`KALSHI_SMOKE_QUERY=…`.

Without `RUN_LIVE=1`, the script exits cleanly and does nothing —
safe to run from any machine.

## Caveats

- **REST only.** `watchOrderBook` / `watchTrades` are single-shot REST
  calls. For live updates today, poll on an interval. A future revision
  may switch the interface to `AsyncIterable<OrderBook>` and add a real
  WS subscriber.
- **Demo verified, prod not exercised.** All live verification ran
  against `demo-api.kalshi.co`. Switching to prod is a one-env-var
  change but has not been driven end-to-end through this adapter. The
  smoke script's `RUN_ORDER=1` against prod would post a real order.
- **Sub-penny ticks.** Some Kalshi markets support 0.001 increments
  (since March 2026). `OrderParams.price` is `number` and the adapter
  emits 4-decimal dollar strings, so `0.0001` ticks round-trip cleanly.
- **Fixtures are sanitized.** Account UUIDs, order IDs, and any value
  tied to a real demo account are replaced with placeholder UUIDs
  (`AAAAAAAA-BBBB-CCCC-DDDD-…`) before commit.

## Related

- [`docs/specs/market-client-abstraction.md`](../../../docs/specs/market-client-abstraction.md)
  — the multi-venue abstraction spec; explains why the interface looks
  the way it does.
- [`docs/canon-architecture.md`](../../../docs/canon-architecture.md)
  — broader Canon architecture; the adapter is one piece of the venue
  layer.
- [`adapters/polymarket.ts`](polymarket.ts) — the sibling adapter
  (same interface, also REST-snapshot-backed for `watch*`).
