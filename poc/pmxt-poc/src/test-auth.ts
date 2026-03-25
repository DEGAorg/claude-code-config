/**
 * POC: Test auth-required pmxtjs methods against Polymarket.
 *
 * Methods tested:
 *   - fetchPositions (optional address param)
 *   - fetchBalance (optional address param)
 *   - fetchMyTrades
 *
 * Auth: Polymarket private key via POLYMARKET_PRIVATE_KEY env var.
 * Without auth, these methods should fail with a credentials error.
 * fetchPositions and fetchBalance also accept an explicit address.
 */
import { Polymarket } from "pmxtjs";
import type {
  Position,
  Balance,
  UserTrade,
} from "pmxtjs";

interface TestResult {
  method: string;
  status: "PASS" | "FAIL" | "SKIP";
  duration: number;
  detail: string;
  shape?: Record<string, string>;
  error?: string;
  authMode: string;
}

const results: TestResult[] = [];

function logShape(obj: unknown): Record<string, string> {
  if (obj === null || obj === undefined) return { value: String(obj) };
  if (Array.isArray(obj)) {
    if (obj.length === 0) return { type: "empty array" };
    return logShape(obj[0]);
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

async function testFetchPositions(
  poly: Polymarket,
  authMode: string,
  address?: string,
): Promise<void> {
  const label = address
    ? `fetchPositions(address="${address.slice(0, 10)}...")`
    : "fetchPositions()";
  const start = Date.now();
  try {
    const positions: Position[] = await poly.fetchPositions(address);
    const elapsed = Date.now() - start;

    if (!Array.isArray(positions)) {
      results.push({
        method: label,
        status: "FAIL",
        duration: elapsed,
        detail: `Expected array, got ${typeof positions}`,
        authMode,
      });
      return;
    }

    const first = positions[0];
    const shape = first ? logShape(first) : {};

    console.log(`\n--- ${label} [${authMode}] ---`);
    console.log(`  Count: ${positions.length}`);
    if (first) {
      console.log(`  marketId: ${first.marketId}`);
      console.log(`  outcomeId: ${first.outcomeId}`);
      console.log(`  outcomeLabel: ${first.outcomeLabel}`);
      console.log(`  size: ${first.size}`);
      console.log(`  entryPrice: ${first.entryPrice}`);
      console.log(`  currentPrice: ${first.currentPrice}`);
      console.log(`  unrealizedPnL: ${first.unrealizedPnL}`);
      console.log(`  Shape: ${JSON.stringify(shape)}`);
    }

    results.push({
      method: label,
      status: "PASS",
      duration: elapsed,
      detail: `Returned ${positions.length} positions`,
      shape,
      authMode,
    });
  } catch (err) {
    const elapsed = Date.now() - start;
    const errStr = String(err);
    console.log(`\n--- ${label} [${authMode}] ---`);
    console.log(`  ERROR: ${errStr.slice(0, 200)}`);

    results.push({
      method: label,
      status: "FAIL",
      duration: elapsed,
      detail: "Exception thrown",
      error: errStr,
      authMode,
    });
  }
}

async function testFetchBalance(
  poly: Polymarket,
  authMode: string,
  address?: string,
): Promise<void> {
  const label = address
    ? `fetchBalance(address="${address.slice(0, 10)}...")`
    : "fetchBalance()";
  const start = Date.now();
  try {
    const balances: Balance[] = await poly.fetchBalance(address);
    const elapsed = Date.now() - start;

    if (!Array.isArray(balances)) {
      results.push({
        method: label,
        status: "FAIL",
        duration: elapsed,
        detail: `Expected array, got ${typeof balances}`,
        authMode,
      });
      return;
    }

    const first = balances[0];
    const shape = first ? logShape(first) : {};

    console.log(`\n--- ${label} [${authMode}] ---`);
    console.log(`  Count: ${balances.length}`);
    if (first) {
      console.log(`  currency: ${first.currency}`);
      console.log(`  total: ${first.total}`);
      console.log(`  available: ${first.available}`);
      console.log(`  locked: ${first.locked}`);
      console.log(`  Shape: ${JSON.stringify(shape)}`);
    }

    results.push({
      method: label,
      status: "PASS",
      duration: elapsed,
      detail: `Returned ${balances.length} balances`,
      shape,
      authMode,
    });
  } catch (err) {
    const elapsed = Date.now() - start;
    const errStr = String(err);
    console.log(`\n--- ${label} [${authMode}] ---`);
    console.log(`  ERROR: ${errStr.slice(0, 200)}`);

    results.push({
      method: label,
      status: "FAIL",
      duration: elapsed,
      detail: "Exception thrown",
      error: errStr,
      authMode,
    });
  }
}

async function testFetchMyTrades(
  poly: Polymarket,
  authMode: string,
): Promise<void> {
  const start = Date.now();
  try {
    const trades: UserTrade[] = await poly.fetchMyTrades();
    const elapsed = Date.now() - start;

    if (!Array.isArray(trades)) {
      results.push({
        method: "fetchMyTrades",
        status: "FAIL",
        duration: elapsed,
        detail: `Expected array, got ${typeof trades}`,
        authMode,
      });
      return;
    }

    const first = trades[0];
    const shape = first ? logShape(first) : {};

    console.log(`\n--- fetchMyTrades [${authMode}] ---`);
    console.log(`  Count: ${trades.length}`);
    if (first) {
      console.log(`  id: ${first.id}`);
      console.log(`  price: ${first.price}`);
      console.log(`  amount: ${first.amount}`);
      console.log(`  side: ${first.side}`);
      console.log(`  timestamp: ${first.timestamp}`);
      console.log(`  orderId: ${first.orderId ?? "N/A"}`);
      console.log(`  outcomeId: ${first.outcomeId ?? "N/A"}`);
      console.log(`  marketId: ${first.marketId ?? "N/A"}`);
      console.log(`  Shape: ${JSON.stringify(shape)}`);
    }

    results.push({
      method: "fetchMyTrades",
      status: "PASS",
      duration: elapsed,
      detail: `Returned ${trades.length} trades`,
      shape,
      authMode,
    });
  } catch (err) {
    const elapsed = Date.now() - start;
    const errStr = String(err);
    console.log(`\n--- fetchMyTrades [${authMode}] ---`);
    console.log(`  ERROR: ${errStr.slice(0, 200)}`);

    results.push({
      method: "fetchMyTrades",
      status: "FAIL",
      duration: elapsed,
      detail: "Exception thrown",
      error: errStr,
      authMode,
    });
  }
}

async function main(): Promise<void> {
  console.log("=== pmxt POC: Auth-Required Methods ===\n");

  const privateKey = process.env["POLYMARKET_PRIVATE_KEY"];
  const proxyAddress = process.env["PROXY_ADDRESS"];

  // Phase 1: Test without auth — document the error behavior
  console.log("== Phase 1: No auth (expect errors) ==");
  {
    const poly = new Polymarket();
    await testFetchPositions(poly, "no-auth");
    await testFetchBalance(poly, "no-auth");
    await testFetchMyTrades(poly, "no-auth");
    await poly.close();
  }

  // Phase 2: Test with auth (if POLYMARKET_PRIVATE_KEY is set)
  if (privateKey) {
    console.log("\n\n== Phase 2: With privateKey ==");
    const opts: Record<string, string> = { privateKey };
    if (proxyAddress) {
      opts["proxyAddress"] = proxyAddress;
    }
    const poly = new Polymarket(opts);

    await testFetchPositions(poly, "privateKey");
    await testFetchBalance(poly, "privateKey");
    await testFetchMyTrades(poly, "privateKey");
    await poly.close();
  } else {
    console.log("\n\n== Phase 2: SKIPPED (no POLYMARKET_PRIVATE_KEY) ==");
    console.log("  Set POLYMARKET_PRIVATE_KEY env var to test authenticated access.");
    console.log("  Example: POLYMARKET_PRIVATE_KEY=<hex-key> npx tsx src/test-auth.ts");

    for (const method of [
      "fetchPositions",
      "fetchBalance",
      "fetchMyTrades",
    ]) {
      results.push({
        method: `${method} [auth]`,
        status: "SKIP",
        duration: 0,
        detail: "No POLYMARKET_PRIVATE_KEY env var",
        authMode: "skipped",
      });
    }
  }

  // Summary
  console.log("\n\n=== SUMMARY ===");
  console.log(
    "Method                                     | Auth Mode  | Status | Duration | Detail",
  );
  console.log(
    "-------------------------------------------|------------|--------|----------|-------",
  );
  for (const r of results) {
    const method = r.method.padEnd(43);
    const auth = r.authMode.padEnd(10);
    const status = r.status.padEnd(6);
    const dur = `${r.duration}ms`.padEnd(8);
    console.log(`${method}| ${auth} | ${status} | ${dur} | ${r.detail}`);
    if (r.error) {
      console.log(
        `                                           |            |        |          | ERROR: ${r.error.slice(0, 200)}`,
      );
    }
  }

  const passed = results.filter((r) => r.status === "PASS").length;
  const failed = results.filter((r) => r.status === "FAIL").length;
  const skipped = results.filter((r) => r.status === "SKIP").length;
  console.log(`\nResult: ${passed} passed, ${failed} failed, ${skipped} skipped`);

  // Auth tests are informational — we expect no-auth to fail.
  // Exit 0 if: at least one PASS per method with auth, OR auth was skipped.
  // Exit 1 only if auth was provided but methods still failed.
  if (privateKey && failed > 0) {
    const authFailures = results.filter(
      (r) => r.authMode === "privateKey" && r.status === "FAIL",
    );
    if (authFailures.length > 0) {
      console.log(
        "\nAuth-mode failures detected — exiting with error.",
      );
      process.exit(1);
    }
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
