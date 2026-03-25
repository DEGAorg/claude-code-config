/**
 * POC: Test write operations against Polymarket via pmxtjs.
 *
 * Methods tested:
 *   - buildOrder (dry-run: builds signed payload without submitting)
 *   - createOrder + cancelOrder (live order flow, auth required)
 *
 * Auth: Polymarket private key via POLYMARKET_PRIVATE_KEY env var.
 * Without auth, buildOrder and createOrder should fail with credentials error.
 *
 * Safety: createOrder uses a limit order at an extreme price (0.01) so it
 * will NOT fill. cancelOrder immediately cancels it. If createOrder fails
 * or is skipped, cancelOrder is also skipped.
 */
import { Polymarket } from "pmxtjs";
import type {
  BuiltOrder,
  Order,
  UnifiedMarket,
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

/**
 * Find a liquid market with a known outcomeId for order tests.
 * Returns the market + first outcome's outcomeId.
 */
async function findTestMarket(
  poly: Polymarket,
): Promise<{ market: UnifiedMarket; outcomeId: string } | null> {
  try {
    const markets = await poly.fetchMarkets({ limit: 20 });
    const sorted = [...markets].sort(
      (a, b) => (b.volume24h ?? 0) - (a.volume24h ?? 0),
    );
    for (const m of sorted) {
      const oid = m.outcomes?.[0]?.outcomeId;
      if (oid && m.marketId) {
        return { market: m, outcomeId: oid };
      }
    }
  } catch (err) {
    console.log(`  Could not fetch markets: ${String(err).slice(0, 120)}`);
  }
  return null;
}

async function testBuildOrder(
  poly: Polymarket,
  authMode: string,
  marketId: string,
  outcomeId: string,
): Promise<void> {
  const start = Date.now();
  try {
    const built: BuiltOrder = await poly.buildOrder({
      marketId,
      outcomeId,
      side: "buy",
      type: "limit",
      amount: 1,
      price: 0.01,
    });
    const elapsed = Date.now() - start;
    const shape = logShape(built);

    console.log(`\n--- buildOrder [${authMode}] ---`);
    console.log(`  exchange: ${built.exchange}`);
    console.log(`  params.marketId: ${built.params.marketId}`);
    console.log(`  params.outcomeId: ${built.params.outcomeId}`);
    console.log(`  params.side: ${built.params.side}`);
    console.log(`  params.type: ${built.params.type}`);
    console.log(`  params.amount: ${built.params.amount}`);
    console.log(`  params.price: ${built.params.price}`);
    console.log(`  signedOrder present: ${built.signedOrder !== undefined}`);
    console.log(`  tx present: ${built.tx !== undefined}`);
    console.log(`  raw present: ${built.raw !== undefined}`);
    console.log(`  Shape: ${JSON.stringify(shape)}`);

    results.push({
      method: "buildOrder",
      status: "PASS",
      duration: elapsed,
      detail: `Built order for ${marketId} (dry-run, not submitted)`,
      shape,
      authMode,
    });
  } catch (err) {
    const elapsed = Date.now() - start;
    const errStr = String(err);
    console.log(`\n--- buildOrder [${authMode}] ---`);
    console.log(`  ERROR: ${errStr.slice(0, 200)}`);

    results.push({
      method: "buildOrder",
      status: "FAIL",
      duration: elapsed,
      detail: "Exception thrown",
      error: errStr,
      authMode,
    });
  }
}

async function testCreateAndCancelOrder(
  poly: Polymarket,
  authMode: string,
  marketId: string,
  outcomeId: string,
): Promise<void> {
  // createOrder with extreme limit price (0.01) so it sits unfilled
  const startCreate = Date.now();
  let createdOrder: Order | null = null;
  try {
    createdOrder = await poly.createOrder({
      marketId,
      outcomeId,
      side: "buy",
      type: "limit",
      amount: 1,
      price: 0.01,
    });
    const elapsed = Date.now() - startCreate;
    const shape = logShape(createdOrder);

    console.log(`\n--- createOrder [${authMode}] ---`);
    console.log(`  id: ${createdOrder.id}`);
    console.log(`  marketId: ${createdOrder.marketId}`);
    console.log(`  outcomeId: ${createdOrder.outcomeId}`);
    console.log(`  side: ${createdOrder.side}`);
    console.log(`  type: ${createdOrder.type}`);
    console.log(`  amount: ${createdOrder.amount}`);
    console.log(`  price: ${createdOrder.price}`);
    console.log(`  status: ${createdOrder.status}`);
    console.log(`  filled: ${createdOrder.filled}`);
    console.log(`  remaining: ${createdOrder.remaining}`);
    console.log(`  Shape: ${JSON.stringify(shape)}`);

    results.push({
      method: "createOrder",
      status: "PASS",
      duration: elapsed,
      detail: `Created limit order id=${createdOrder.id} status=${createdOrder.status}`,
      shape,
      authMode,
    });
  } catch (err) {
    const elapsed = Date.now() - startCreate;
    const errStr = String(err);
    console.log(`\n--- createOrder [${authMode}] ---`);
    console.log(`  ERROR: ${errStr.slice(0, 200)}`);

    results.push({
      method: "createOrder",
      status: "FAIL",
      duration: elapsed,
      detail: "Exception thrown",
      error: errStr,
      authMode,
    });
  }

  // cancelOrder — only if createOrder succeeded
  if (!createdOrder) {
    console.log(`\n--- cancelOrder [${authMode}] ---`);
    console.log(`  SKIP: no order to cancel (createOrder failed)`);
    results.push({
      method: "cancelOrder",
      status: "SKIP",
      duration: 0,
      detail: "Skipped: createOrder did not produce an order to cancel",
      authMode,
    });
    return;
  }

  const startCancel = Date.now();
  try {
    const cancelled: Order = await poly.cancelOrder(createdOrder.id);
    const elapsed = Date.now() - startCancel;
    const shape = logShape(cancelled);

    console.log(`\n--- cancelOrder [${authMode}] ---`);
    console.log(`  id: ${cancelled.id}`);
    console.log(`  status: ${cancelled.status}`);
    console.log(`  filled: ${cancelled.filled}`);
    console.log(`  remaining: ${cancelled.remaining}`);
    console.log(`  Shape: ${JSON.stringify(shape)}`);

    results.push({
      method: "cancelOrder",
      status: "PASS",
      duration: elapsed,
      detail: `Cancelled order id=${cancelled.id} status=${cancelled.status}`,
      shape,
      authMode,
    });
  } catch (err) {
    const elapsed = Date.now() - startCancel;
    const errStr = String(err);
    console.log(`\n--- cancelOrder [${authMode}] ---`);
    console.log(`  ERROR: ${errStr.slice(0, 200)}`);

    results.push({
      method: "cancelOrder",
      status: "FAIL",
      duration: elapsed,
      detail: "Exception thrown",
      error: errStr,
      authMode,
    });
  }
}

async function main(): Promise<void> {
  console.log("=== pmxt POC: Write Operations ===\n");

  const privateKey = process.env["POLYMARKET_PRIVATE_KEY"];
  const proxyAddress = process.env["PROXY_ADDRESS"];

  // Find a liquid market for order tests
  console.log("Finding a liquid market for order tests...");
  const noAuthPoly = new Polymarket();
  const testMarket = await findTestMarket(noAuthPoly);

  if (!testMarket) {
    console.log("FATAL: Could not find a market with outcomes for testing.");
    await noAuthPoly.close();
    process.exit(1);
  }

  const { market, outcomeId } = testMarket;
  console.log(`  Using market: "${market.title}"`);
  console.log(`  marketId: ${market.marketId}`);
  console.log(`  outcomeId: ${outcomeId}`);
  console.log(`  volume24h: ${market.volume24h}`);

  // Phase 1: buildOrder without auth (expect error)
  console.log("\n== Phase 1: No auth (expect errors) ==");
  await testBuildOrder(noAuthPoly, "no-auth", market.marketId, outcomeId);

  // Also test createOrder without auth to document the error
  await testCreateAndCancelOrder(
    noAuthPoly,
    "no-auth",
    market.marketId,
    outcomeId,
  );
  await noAuthPoly.close();

  // Phase 2: With auth
  if (privateKey) {
    console.log("\n\n== Phase 2: With privateKey ==");
    const opts: Record<string, string> = { privateKey };
    if (proxyAddress) {
      opts["proxyAddress"] = proxyAddress;
    }
    const authPoly = new Polymarket(opts);

    // buildOrder with auth (dry-run — does NOT submit)
    await testBuildOrder(authPoly, "privateKey", market.marketId, outcomeId);

    // createOrder + cancelOrder with auth (live, but safe limit price)
    console.log("\n  NOTE: createOrder uses price=0.01 (extreme low).");
    console.log("  Order should NOT fill. cancelOrder follows immediately.");
    await testCreateAndCancelOrder(
      authPoly,
      "privateKey",
      market.marketId,
      outcomeId,
    );

    await authPoly.close();
  } else {
    console.log("\n\n== Phase 2: SKIPPED (no POLYMARKET_PRIVATE_KEY) ==");
    console.log(
      "  Set POLYMARKET_PRIVATE_KEY to test authenticated write ops.",
    );
    console.log(
      "  Example: POLYMARKET_PRIVATE_KEY=<hex> npx tsx src/test-orders.ts",
    );

    for (const method of [
      "buildOrder [auth]",
      "createOrder [auth]",
      "cancelOrder [auth]",
    ]) {
      results.push({
        method,
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
    "Method                    | Auth Mode  | Status | Duration | Detail",
  );
  console.log(
    "--------------------------|------------|--------|----------|-------",
  );
  for (const r of results) {
    const method = r.method.padEnd(26);
    const auth = r.authMode.padEnd(10);
    const status = r.status.padEnd(6);
    const dur = `${r.duration}ms`.padEnd(8);
    console.log(`${method}| ${auth} | ${status} | ${dur} | ${r.detail}`);
    if (r.error) {
      console.log(
        `                          |            |        |          | ERROR: ${r.error.slice(0, 200)}`,
      );
    }
  }

  const passed = results.filter((r) => r.status === "PASS").length;
  const failed = results.filter((r) => r.status === "FAIL").length;
  const skipped = results.filter((r) => r.status === "SKIP").length;
  console.log(
    `\nResult: ${passed} passed, ${failed} failed, ${skipped} skipped`,
  );

  // Write ops without auth are expected to fail.
  // Exit 1 only if auth was provided and auth-mode methods still failed.
  if (privateKey && failed > 0) {
    const authFailures = results.filter(
      (r) => r.authMode === "privateKey" && r.status === "FAIL",
    );
    if (authFailures.length > 0) {
      console.log("\nAuth-mode failures detected — exiting with error.");
      process.exit(1);
    }
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
