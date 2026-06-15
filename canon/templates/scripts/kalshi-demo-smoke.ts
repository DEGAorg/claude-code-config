/**
 * Live smoke harness for the Kalshi adapter against the demo environment.
 *
 * Drives the full `MarketClient` surface against `demo-api.kalshi.co`:
 * public-read (search/snapshot/orderbook/OHLCV) with no creds, and the
 * authenticated portfolio endpoints with RSA-PSS signed headers. The
 * order-placement leg is opt-in (`RUN_ORDER=1`) so the default smoke is
 * read-only safe to run from any machine that holds the demo PEM.
 *
 * Skipped by default. Set `RUN_LIVE=1` to opt in. Filename lives under
 * `scripts/` (not `__tests__/*.test.ts`) so vitest excludes it from CI.
 *
 * Required env (only when `RUN_LIVE=1`):
 *   - `KALSHI_API_KEY_ID`        — Kalshi demo API key UUID.
 *   - `KALSHI_PRIVATE_KEY_PATH`  — absolute path to PEM-encoded RSA
 *                                  private key for that key UUID.
 *
 * Optional env:
 *   - `KALSHI_API_BASE`          — REST base URL. Defaults to
 *                                  `https://demo-api.kalshi.co/trade-api/v2`.
 *                                  Set to the prod URL to verify against
 *                                  live (NOT recommended — this script
 *                                  posts a real order when `RUN_ORDER=1`).
 *   - `KALSHI_SMOKE_QUERY`       — search term for the test market.
 *                                  Defaults to `KXNAMEDSTORM`.
 *   - `RUN_ORDER`                — set to `1` to place a 1-contract YES
 *                                  limit @ $0.01 and immediately cancel.
 *
 * Manual run:
 *   RUN_LIVE=1 KALSHI_API_KEY_ID=... KALSHI_PRIVATE_KEY_PATH=... \
 *     pnpm --filter canon-templates exec tsx scripts/kalshi-demo-smoke.ts
 */

import { KalshiAdapter } from "../adapters/kalshi.js";

if (process.env["RUN_LIVE"] !== "1") {
  console.log(
    "kalshi-demo-smoke: skipped (set RUN_LIVE=1 to opt in; signs requests with the configured PEM)",
  );
  process.exit(0);
}

const apiKeyId = process.env["KALSHI_API_KEY_ID"];
const privateKeyPath = process.env["KALSHI_PRIVATE_KEY_PATH"];
if (!apiKeyId || !privateKeyPath) {
  console.error(
    "kalshi-demo-smoke: KALSHI_API_KEY_ID and KALSHI_PRIVATE_KEY_PATH are required when RUN_LIVE=1",
  );
  process.exit(1);
}

const query = process.env["KALSHI_SMOKE_QUERY"] ?? "KXNAMEDSTORM";
const runOrder = process.env["RUN_ORDER"] === "1";

async function main(): Promise<void> {
  const adapter = new KalshiAdapter();
  const base = process.env["KALSHI_API_BASE"] ?? "https://demo-api.kalshi.co/trade-api/v2";
  console.log(`=== kalshi-demo-smoke (base=${base}) ===`);

  console.log("=== public read ===");
  const matches = await adapter.searchMarkets(query);
  console.log(`searchMarkets("${query}"): ${matches.length} matches`);
  const market = matches[0];
  if (!market) {
    throw new Error(
      `no markets matched "${query}" — set KALSHI_SMOKE_QUERY to a series with open markets`,
    );
  }
  console.log(`  marketId: ${market.marketId}`);
  console.log(`  question: ${market.question}`);
  console.log(`  yes/no:   ${String(market.yesPrice)} / ${String(market.noPrice)}`);

  const price = await adapter.fetchMarketPrice(market.marketId);
  console.log(
    `fetchMarketPrice: yes=${String(price.yesPrice)} no=${String(price.noPrice)}`,
  );

  const book = await adapter.fetchOrderBook(market.yesOutcomeId);
  console.log(
    `fetchOrderBook: bids=${String(book.bids.length)} asks=${String(book.asks.length)}`,
  );

  const candles = await adapter.fetchOHLCV(market.yesOutcomeId, { timeframe: "1h" });
  console.log(`fetchOHLCV: ${String(candles.length)} candles`);

  const snapshots = await adapter.fetchMarketSnapshots(query);
  console.log(`fetchMarketSnapshots: ${String(snapshots.length)} snapshots`);

  const caps = await adapter.getCapabilities();
  console.log(`getCapabilities: supportsTif=${String(caps.supportsTif)}`);

  console.log("=== authenticated ===");
  const ready = await adapter.ensureAccount();
  console.log(`ensureAccount: ready=${String(ready.ready)}`);

  const balances = await adapter.fetchBalance();
  for (const b of balances) {
    console.log(
      `fetchBalance: ${b.currency} total=${String(b.total)} ` +
        `available=${String(b.available)} locked=${String(b.locked)}`,
    );
  }

  const positions = await adapter.fetchPositions();
  console.log(`fetchPositions: ${String(positions.length)} open positions`);

  const trades = await adapter.fetchMyTrades({ limit: 5 });
  console.log(`fetchMyTrades: ${String(trades.length)} recent fills`);

  const open = await adapter.fetchOpenOrders();
  console.log(`fetchOpenOrders: ${String(open.length)} resting`);

  if (!runOrder) {
    console.log("=== smoke OK (read-only — set RUN_ORDER=1 to test create+cancel) ===");
    return;
  }

  console.log("=== order place + cancel ===");
  const order = await adapter.createOrder({
    marketId: market.marketId,
    outcomeId: market.yesOutcomeId,
    side: "buy",
    size: 1,
    price: 0.01,
    orderType: "limit",
    timeInForce: "GTC",
  });
  console.log(
    `createOrder: id=${order.id} status=${order.status} ` +
      `filled=${String(order.filled)} remaining=${String(order.remaining)}`,
  );

  const cancel = await adapter.cancelOrder(order.id);
  console.log(`cancelOrder: id=${cancel.id} status=${cancel.status}`);

  console.log("=== smoke OK ===");
}

try {
  await main();
  process.exit(0);
} catch (err) {
  const msg = err instanceof Error ? (err.stack ?? err.message) : String(err);
  console.error(`kalshi-demo-smoke: FAIL — ${msg}`);
  process.exit(1);
}
