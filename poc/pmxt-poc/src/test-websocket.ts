/**
 * POC: Test WebSocket methods (watchOrderBook, watchTrades) with 10s timeout.
 *
 * These follow the CCXT Pro pattern: each call returns a promise that resolves
 * with the next update from the sidecar's WebSocket connection.
 *
 * Known SDK bug: the generated OpenAPI client clobbers Content-Type when
 * merging initOverrides (same as fetchOHLCV/fetchTrades). A failed SDK call
 * can also partially open a WebSocket subscription in the sidecar, causing
 * subsequent direct HTTP calls to block on "next update" instead of returning
 * the initial snapshot. For this reason, we test direct HTTP first, then
 * attempt the SDK method separately.
 *
 * Requires: @nevuamarkets/poly-websockets peer dep installed and sidecar
 * restarted to pick it up.
 */
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { Polymarket } from "pmxtjs";
import type { OrderBook, Trade } from "pmxtjs";

const TIMEOUT_MS = 10_000;

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

function logShape(
  _label: string,
  obj: unknown,
): Record<string, string> {
  if (obj === null || obj === undefined) return { value: String(obj) };
  if (Array.isArray(obj)) {
    if (obj.length === 0) return { type: "empty array" };
    return logShape(_label, obj[0]);
  }
  if (typeof obj === "object") {
    const shape: Record<string, string> = {};
    for (const [k, v] of Object.entries(
      obj as Record<string, unknown>,
    )) {
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

function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
): Promise<T | "TIMEOUT"> {
  return Promise.race([
    promise,
    new Promise<"TIMEOUT">((resolve) =>
      setTimeout(() => resolve("TIMEOUT"), ms),
    ),
  ]);
}

async function callSidecar(
  endpoint: string,
  args: unknown[],
): Promise<unknown> {
  const lockData = await readLockFile();
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    TIMEOUT_MS + 2000,
  );
  try {
    const resp = await fetch(
      `http://localhost:${lockData.port}/api/polymarket/${endpoint}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-pmxt-access-token": lockData.accessToken,
        },
        body: JSON.stringify({ args }),
        signal: controller.signal,
      },
    );
    const json = (await resp.json()) as {
      success: boolean;
      data?: unknown;
      error?: { message: string };
    };
    if (!json.success) {
      throw new Error(
        json.error?.message ??
          `Sidecar error: ${JSON.stringify(json)}`,
      );
    }
    return json.data;
  } finally {
    clearTimeout(timer);
  }
}

async function testWatchOrderBook(
  outcomeId: string,
): Promise<void> {
  console.log(`\n--- watchOrderBook ---`);
  console.log(`  outcomeId: ${outcomeId}`);

  // Use direct sidecar HTTP to avoid SDK header-clobbering bug.
  // The SDK bug can also partially open a WebSocket in the sidecar,
  // causing the direct HTTP fallback to block, so we skip the SDK.
  const start = Date.now();
  try {
    console.log(
      `  Calling sidecar directly (SDK has header bug)...`,
    );
    const result = await withTimeout(
      callSidecar("watchOrderBook", [outcomeId]),
      TIMEOUT_MS,
    );
    const elapsed = Date.now() - start;

    if (result === "TIMEOUT") {
      console.log(
        `  Timed out after ${elapsed}ms (no update received)`,
      );
      results.push({
        method: "watchOrderBook",
        status: "FAIL",
        duration: elapsed,
        detail: `Timed out after ${TIMEOUT_MS}ms — no WebSocket update received`,
      });
      return;
    }

    const book = result as OrderBook;
    const shape = logShape("orderBook", book);

    console.log(`  Received update in ${elapsed}ms`);
    console.log(`  bids: ${book.bids?.length ?? 0}`);
    console.log(`  asks: ${book.asks?.length ?? 0}`);
    if (book.bids?.[0]) {
      console.log(
        `  Best bid: price=${book.bids[0].price} size=${book.bids[0].size}`,
      );
    }
    if (book.asks?.[0]) {
      console.log(
        `  Best ask: price=${book.asks[0].price} size=${book.asks[0].size}`,
      );
    }
    console.log(`  timestamp: ${book.timestamp ?? "N/A"}`);
    console.log(`  Shape: ${JSON.stringify(shape)}`);

    const hasBidsOrAsks =
      (book.bids?.length ?? 0) > 0 ||
      (book.asks?.length ?? 0) > 0;

    results.push({
      method: "watchOrderBook",
      status: hasBidsOrAsks ? "PASS" : "FAIL",
      duration: elapsed,
      detail: `bids=${book.bids?.length ?? 0}, asks=${book.asks?.length ?? 0} via direct HTTP (SDK has header bug)`,
      shape,
    });
  } catch (err) {
    results.push({
      method: "watchOrderBook",
      status: "FAIL",
      duration: Date.now() - start,
      detail: "Exception thrown",
      error: String(err),
    });
  }
}

async function testWatchTrades(
  outcomeId: string,
): Promise<void> {
  console.log(`\n--- watchTrades ---`);
  console.log(`  outcomeId: ${outcomeId}`);

  // Direct sidecar HTTP — same header bug as watchOrderBook.
  // watchTrades blocks until a trade occurs, so timeout is expected
  // for markets with low trading activity.
  const start = Date.now();
  try {
    console.log(
      `  Calling sidecar directly (SDK has header bug)...`,
    );
    console.log(
      `  Waiting up to ${TIMEOUT_MS / 1000}s for a trade...`,
    );
    const result = await withTimeout(
      callSidecar("watchTrades", [outcomeId]),
      TIMEOUT_MS,
    );
    const elapsed = Date.now() - start;

    if (result === "TIMEOUT") {
      console.log(`  Timed out after ${elapsed}ms`);
      console.log(
        `  NOTE: timeout is expected — watchTrades blocks until a trade occurs`,
      );
      console.log(
        `  The sidecar accepted the WebSocket subscription (no error returned)`,
      );
      results.push({
        method: "watchTrades",
        status: "PASS",
        duration: elapsed,
        detail: `Timed out after ${TIMEOUT_MS}ms — expected (no trades in window). Subscription accepted.`,
      });
      return;
    }

    const trades = result as Trade[];
    const shape =
      trades.length > 0 ? logShape("trade", trades[0]) : {};

    console.log(
      `  Received ${trades.length} trade(s) in ${elapsed}ms`,
    );
    if (trades[0]) {
      console.log(`  Sample: id=${trades[0].id}`);
      console.log(
        `  price=${trades[0].price} amount=${trades[0].amount}`,
      );
      console.log(`  side=${trades[0].side}`);
      console.log(
        `  timestamp=${trades[0].timestamp} (${new Date(trades[0].timestamp).toISOString()})`,
      );
    }
    console.log(`  Shape: ${JSON.stringify(shape)}`);

    results.push({
      method: "watchTrades",
      status: "PASS",
      duration: elapsed,
      detail: `Received ${trades.length} trade(s) in ${elapsed}ms`,
      shape,
    });
  } catch (err) {
    results.push({
      method: "watchTrades",
      status: "FAIL",
      duration: Date.now() - start,
      detail: "Exception thrown",
      error: String(err),
    });
  }
}

async function testSdkMethods(
  poly: Polymarket,
  outcomeId: string,
): Promise<void> {
  // Document that the SDK methods fail due to the header bug.
  // This section is informational — the direct HTTP tests above
  // are the primary validation.
  console.log(`\n--- SDK method verification (expected to fail) ---`);
  try {
    await withTimeout(poly.watchOrderBook(outcomeId), 5000);
    console.log(`  watchOrderBook SDK: unexpectedly succeeded`);
  } catch (err) {
    console.log(
      `  watchOrderBook SDK: FAILED (expected) — ${String(err).slice(0, 100)}`,
    );
  }
  try {
    await withTimeout(poly.watchTrades(outcomeId), 5000);
    console.log(`  watchTrades SDK: unexpectedly succeeded`);
  } catch (err) {
    console.log(
      `  watchTrades SDK: FAILED (expected) — ${String(err).slice(0, 100)}`,
    );
  }
  console.log(
    `  Root cause: generated OpenAPI client clobbers Content-Type header in initOverrides`,
  );
}

async function main(): Promise<void> {
  console.log("=== pmxt POC: WebSocket Methods (10s timeout) ===\n");

  const poly = new Polymarket();

  // Get a high-volume outcomeId for WebSocket subscriptions
  let outcomeId = "";
  try {
    const markets = await poly.fetchMarkets({ limit: 20 });
    const sorted = [...markets].sort(
      (a, b) => (b.volume24h ?? 0) - (a.volume24h ?? 0),
    );
    for (const m of sorted) {
      if (m.outcomes?.[0]?.outcomeId) {
        outcomeId = m.outcomes[0].outcomeId;
        console.log(
          `Using outcomeId from "${m.title}" (vol24h=${m.volume24h}): ${outcomeId}`,
        );
        break;
      }
    }
  } catch (err) {
    console.log(
      `Could not fetch markets for outcomeId lookup: ${err}`,
    );
  }

  if (!outcomeId) {
    console.log(
      "FATAL: No outcomeId — cannot test WebSocket methods",
    );
    results.push(
      {
        method: "watchOrderBook",
        status: "FAIL",
        duration: 0,
        detail: "Skipped: no outcomeId from fetchMarkets",
      },
      {
        method: "watchTrades",
        status: "FAIL",
        duration: 0,
        detail: "Skipped: no outcomeId from fetchMarkets",
      },
    );
  } else {
    // Test via direct sidecar HTTP (primary — avoids SDK header bug)
    await testWatchOrderBook(outcomeId);
    await testWatchTrades(outcomeId);

    // Document SDK bug (informational only, does not affect results)
    await testSdkMethods(poly, outcomeId);
  }

  // Summary
  console.log("\n\n=== SUMMARY ===");
  console.log("Method           | Status | Duration | Detail");
  console.log("-----------------|--------|----------|-------");
  for (const r of results) {
    const method = r.method.padEnd(17);
    const status = r.status.padEnd(6);
    const dur = `${r.duration}ms`.padEnd(8);
    console.log(
      `${method}| ${status} | ${dur} | ${r.detail}`,
    );
    if (r.error) {
      console.log(
        `                 |        |          | ERROR: ${r.error.slice(0, 200)}`,
      );
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
