/**
 * POC: Test read-only pmxtjs methods against Polymarket (no auth).
 *
 * Methods tested:
 *   - fetchMarkets
 *   - fetchEvents
 *   - fetchOHLCV
 *   - fetchOrderBook
 *
 * Known SDK bug: fetchOHLCV and fetchTrades use the generated OpenAPI
 * client which clobbers the Content-Type header when merging initOverrides.
 * The sidecar returns 401 because it can't parse the body. Workaround:
 * use callApi("fetchOHLCV", ...) instead.
 */
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { Polymarket } from "pmxtjs";
import type {
  UnifiedMarket,
  UnifiedEvent,
  PriceCandle,
  OrderBook,
} from "pmxtjs";

interface LockData {
  port: number;
  accessToken: string;
}

async function readLockFile(): Promise<LockData> {
  const raw = await readFile(
    join(homedir(), ".pmxt", "server.lock"),
    "utf-8",
  );
  return JSON.parse(raw) as LockData;
}

interface TestResult {
  method: string;
  status: "PASS" | "FAIL";
  duration: number;
  detail: string;
  shape?: Record<string, string>;
  error?: string;
}

const results: TestResult[] = [];

function logShape(label: string, obj: unknown): Record<string, string> {
  if (obj === null || obj === undefined) return { value: String(obj) };
  if (Array.isArray(obj)) {
    if (obj.length === 0) return { type: "empty array" };
    return logShape(label, obj[0]);
  }
  if (typeof obj === "object") {
    const shape: Record<string, string> = {};
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
      shape[k] = Array.isArray(v)
        ? `array(${v.length})`
        : v === null
          ? "null"
          : typeof v;
    }
    return shape;
  }
  return { type: typeof obj };
}

async function testFetchMarkets(
  poly: Polymarket,
): Promise<void> {
  const start = Date.now();
  try {
    const markets: UnifiedMarket[] = await poly.fetchMarkets({
      query: "Trump",
      limit: 5,
    });
    const elapsed = Date.now() - start;

    if (!Array.isArray(markets)) {
      results.push({
        method: "fetchMarkets",
        status: "FAIL",
        duration: elapsed,
        detail: `Expected array, got ${typeof markets}`,
      });
      return;
    }

    const first = markets[0];
    const shape = first ? logShape("market", first) : {};

    console.log(`\n--- fetchMarkets ---`);
    console.log(`  Count: ${markets.length}`);
    if (first) {
      console.log(`  Sample title: ${first.title}`);
      console.log(`  marketId: ${first.marketId}`);
      console.log(`  outcomes: ${first.outcomes?.length ?? 0}`);
      console.log(`  volume24h: ${first.volume24h}`);
      console.log(`  liquidity: ${first.liquidity}`);
      console.log(`  url: ${first.url}`);
      if (first.outcomes?.[0]) {
        console.log(`  outcome[0].outcomeId: ${first.outcomes[0].outcomeId}`);
        console.log(`  outcome[0].label: ${first.outcomes[0].label}`);
        console.log(`  outcome[0].price: ${first.outcomes[0].price}`);
      }
      console.log(`  Shape: ${JSON.stringify(shape)}`);
    }

    results.push({
      method: "fetchMarkets",
      status: markets.length > 0 ? "PASS" : "FAIL",
      duration: elapsed,
      detail: `Returned ${markets.length} markets`,
      shape,
    });
  } catch (err) {
    results.push({
      method: "fetchMarkets",
      status: "FAIL",
      duration: Date.now() - start,
      detail: "Exception thrown",
      error: String(err),
    });
  }
}

async function testFetchEvents(
  poly: Polymarket,
): Promise<void> {
  const start = Date.now();
  try {
    const events: UnifiedEvent[] = await poly.fetchEvents({
      query: "election",
      limit: 5,
    });
    const elapsed = Date.now() - start;

    if (!Array.isArray(events)) {
      results.push({
        method: "fetchEvents",
        status: "FAIL",
        duration: elapsed,
        detail: `Expected array, got ${typeof events}`,
      });
      return;
    }

    const first = events[0];
    const shape = first ? logShape("event", first) : {};

    console.log(`\n--- fetchEvents ---`);
    console.log(`  Count: ${events.length}`);
    if (first) {
      console.log(`  Sample title: ${first.title}`);
      console.log(`  id: ${first.id}`);
      console.log(`  slug: ${first.slug}`);
      console.log(`  markets count: ${first.markets?.length ?? 0}`);
      console.log(`  url: ${first.url}`);
      console.log(`  Shape: ${JSON.stringify(shape)}`);
    }

    results.push({
      method: "fetchEvents",
      status: events.length > 0 ? "PASS" : "FAIL",
      duration: elapsed,
      detail: `Returned ${events.length} events`,
      shape,
    });
  } catch (err) {
    results.push({
      method: "fetchEvents",
      status: "FAIL",
      duration: Date.now() - start,
      detail: "Exception thrown",
      error: String(err),
    });
  }
}

async function testFetchOHLCV(
  poly: Polymarket,
  outcomeId: string,
): Promise<void> {
  // SDK fetchOHLCV has a header-clobbering bug in the generated OpenAPI
  // client. Try the SDK method first, then fall back to callApi workaround.
  const start = Date.now();

  // Attempt 1: SDK method
  try {
    const candles: PriceCandle[] = await poly.fetchOHLCV(outcomeId, {
      resolution: "1d",
      limit: 10,
    });
    const elapsed = Date.now() - start;
    logOHLCVResult(outcomeId, candles, elapsed, "sdk");
    return;
  } catch (sdkErr) {
    console.log(`\n--- fetchOHLCV (SDK) ---`);
    console.log(`  SDK method failed: ${String(sdkErr).slice(0, 120)}`);
    console.log(`  BUG: generated client clobbers Content-Type header in initOverrides`);
    console.log(`  Falling back to callApi workaround...`);
  }

  // Attempt 2: direct sidecar HTTP call (bypasses broken generated client)
  const start2 = Date.now();
  try {
    const lockData = await readLockFile();
    const baseUrl = `http://localhost:${lockData.port}`;
    const resp = await fetch(`${baseUrl}/api/polymarket/fetchOHLCV`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-pmxt-access-token": lockData.accessToken,
      },
      body: JSON.stringify({
        args: [outcomeId, { resolution: "1d", limit: 10 }],
      }),
    });
    const json = await resp.json() as { success: boolean; data?: PriceCandle[] };
    const elapsed = Date.now() - start2;
    if (!json.success || !json.data) {
      throw new Error(`Sidecar returned: ${JSON.stringify(json)}`);
    }
    logOHLCVResult(outcomeId, json.data, elapsed, "direct HTTP workaround");
  } catch (err) {
    results.push({
      method: "fetchOHLCV",
      status: "FAIL",
      duration: Date.now() - start2,
      detail: "Both SDK and direct HTTP failed",
      error: String(err),
    });
  }
}

function logOHLCVResult(
  outcomeId: string,
  candles: PriceCandle[],
  elapsed: number,
  via: string,
): void {
  const first = candles[0];
  const shape = first ? logShape("candle", first) : {};

  console.log(`\n--- fetchOHLCV (${via}) ---`);
  console.log(`  outcomeId used: ${outcomeId}`);
  console.log(`  Count: ${candles.length}`);
  if (first) {
    console.log(`  Sample: O=${first.open} H=${first.high} L=${first.low} C=${first.close} V=${first.volume ?? "N/A"}`);
    console.log(`  timestamp: ${first.timestamp} (${new Date(first.timestamp).toISOString()})`);
    console.log(`  Shape: ${JSON.stringify(shape)}`);
  }

  results.push({
    method: "fetchOHLCV",
    status: candles.length > 0 ? "PASS" : "FAIL",
    duration: elapsed,
    detail: `Returned ${candles.length} candles via ${via}`,
    shape,
  });
}

async function testFetchOrderBook(
  poly: Polymarket,
  outcomeId: string,
): Promise<void> {
  const start = Date.now();
  try {
    const book: OrderBook = await poly.fetchOrderBook(outcomeId);
    const elapsed = Date.now() - start;

    const shape = logShape("orderBook", book);

    console.log(`\n--- fetchOrderBook ---`);
    console.log(`  outcomeId used: ${outcomeId}`);
    console.log(`  bids: ${book.bids?.length ?? 0}`);
    console.log(`  asks: ${book.asks?.length ?? 0}`);
    if (book.bids?.[0]) {
      console.log(`  Best bid: price=${book.bids[0].price} size=${book.bids[0].size}`);
    }
    if (book.asks?.[0]) {
      console.log(`  Best ask: price=${book.asks[0].price} size=${book.asks[0].size}`);
    }
    console.log(`  timestamp: ${book.timestamp ?? "N/A"}`);
    console.log(`  Shape: ${JSON.stringify(shape)}`);

    const hasBidsOrAsks =
      (book.bids?.length ?? 0) > 0 || (book.asks?.length ?? 0) > 0;

    results.push({
      method: "fetchOrderBook",
      status: hasBidsOrAsks ? "PASS" : "FAIL",
      duration: elapsed,
      detail: `bids=${book.bids?.length ?? 0}, asks=${book.asks?.length ?? 0}`,
      shape,
    });
  } catch (err) {
    results.push({
      method: "fetchOrderBook",
      status: "FAIL",
      duration: Date.now() - start,
      detail: "Exception thrown",
      error: String(err),
    });
  }
}

async function main(): Promise<void> {
  console.log("=== pmxt POC: Read-Only Methods (no auth) ===\n");

  const poly = new Polymarket();

  // 1. fetchMarkets
  await testFetchMarkets(poly);

  // Get a high-volume outcomeId for OHLCV and OrderBook tests
  let outcomeId = "";
  try {
    const markets = await poly.fetchMarkets({ limit: 20 });
    const sorted = [...markets].sort(
      (a, b) => (b.volume24h ?? 0) - (a.volume24h ?? 0),
    );
    for (const m of sorted) {
      if (m.outcomes?.[0]?.outcomeId) {
        outcomeId = m.outcomes[0].outcomeId;
        console.log(`\n  Using outcomeId from "${m.title}" (vol24h=${m.volume24h}): ${outcomeId}`);
        break;
      }
    }
  } catch {
    console.log("\n  Could not fetch markets for outcomeId lookup");
  }

  // 2. fetchEvents
  await testFetchEvents(poly);

  // 3. fetchOHLCV (needs an outcomeId)
  if (outcomeId) {
    await testFetchOHLCV(poly, outcomeId);
  } else {
    results.push({
      method: "fetchOHLCV",
      status: "FAIL",
      duration: 0,
      detail: "Skipped: no outcomeId available from fetchMarkets",
    });
  }

  // 4. fetchOrderBook (needs an outcomeId)
  if (outcomeId) {
    await testFetchOrderBook(poly, outcomeId);
  } else {
    results.push({
      method: "fetchOrderBook",
      status: "FAIL",
      duration: 0,
      detail: "Skipped: no outcomeId available from fetchMarkets",
    });
  }

  // Summary
  console.log("\n\n=== SUMMARY ===");
  console.log("Method           | Status | Duration | Detail");
  console.log("-----------------|--------|----------|-------");
  for (const r of results) {
    const method = r.method.padEnd(17);
    const status = r.status.padEnd(6);
    const dur = `${r.duration}ms`.padEnd(8);
    console.log(`${method}| ${status} | ${dur} | ${r.detail}`);
    if (r.error) {
      console.log(`                 |        |          | ERROR: ${r.error.slice(0, 200)}`);
    }
  }

  const passed = results.filter((r) => r.status === "PASS").length;
  const total = results.length;
  console.log(`\nResult: ${passed}/${total} passed`);

  await poly.close();

  if (passed < total) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
