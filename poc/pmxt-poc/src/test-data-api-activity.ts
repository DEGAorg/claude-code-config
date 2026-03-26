/**
 * POC: Test Polymarket Data API activity and value endpoints.
 *
 * Endpoints tested:
 *   - GET /activity?user=ADDRESS (trade/split/merge/redeem history)
 *   - GET /value?user=ADDRESS (total portfolio value)
 *
 * No auth required — all data is public.
 */
import {
  dataApiFetch,
  discoverTestWallet,
  logShape,
  printSummary,
} from "./data-api-common.ts";
import type {
  TestResult,
  Activity,
  PortfolioValue,
} from "./data-api-common.ts";

const results: TestResult[] = [];

async function testActivity(wallet: string): Promise<void> {
  console.log("\n--- GET /activity (default) ---");
  const start = Date.now();
  const res = await dataApiFetch<Activity[]>(
    `/activity?user=${wallet}&limit=10`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /activity",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  console.log(`  Count: ${res.data.length}`);
  const first = res.data[0];
  if (first) {
    console.log(`  type: ${first.type}`);
    console.log(`  title: ${first.title}`);
    console.log(`  size: ${first.size}`);
    console.log(`  price: ${first.price}`);
    console.log(`  timestamp: ${first.timestamp}`);
    console.log(`  transactionHash: ${first.transactionHash}`);
    console.log(`  Shape: ${JSON.stringify(logShape(first))}`);
  }

  results.push({
    method: "GET /activity",
    status: "PASS",
    duration: elapsed,
    detail: `Returned ${res.data.length} activities`,
    shape: first ? logShape(first) : undefined,
  });
}

async function testActivityTypeFilter(wallet: string): Promise<void> {
  console.log("\n--- GET /activity (type=TRADE) ---");
  const start = Date.now();
  const res = await dataApiFetch<Activity[]>(
    `/activity?user=${wallet}&type=TRADE&limit=5`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /activity (type)",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  const allTrades = res.data.every((a) => a.type === "TRADE");
  console.log(`  Count: ${res.data.length}`);
  console.log(`  All TRADE type: ${allTrades}`);
  console.log(`  Types found: ${[...new Set(res.data.map((a) => a.type))].join(", ")}`);

  results.push({
    method: "GET /activity (type)",
    status: allTrades || res.data.length === 0 ? "PASS" : "FAIL",
    duration: elapsed,
    detail: `${res.data.length} items, allTrades=${allTrades}`,
  });
}

async function testActivitySideFilter(wallet: string): Promise<void> {
  console.log("\n--- GET /activity (side=BUY) ---");
  const start = Date.now();
  const res = await dataApiFetch<Activity[]>(
    `/activity?user=${wallet}&side=BUY&limit=5`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /activity (side)",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  console.log(`  Count: ${res.data.length}`);

  results.push({
    method: "GET /activity (side)",
    status: "PASS",
    duration: elapsed,
    detail: `Returned ${res.data.length} BUY activities`,
  });
}

async function testValue(wallet: string): Promise<void> {
  console.log("\n--- GET /value ---");
  const start = Date.now();
  const res = await dataApiFetch<PortfolioValue[]>(
    `/value?user=${wallet}`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /value",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  console.log(`  Count: ${res.data.length}`);
  const first = res.data[0];
  if (first) {
    console.log(`  value: $${first.value}`);
    console.log(`  Shape: ${JSON.stringify(logShape(first))}`);
  }

  results.push({
    method: "GET /value",
    status: "PASS",
    duration: elapsed,
    detail: `Returned ${res.data.length} entries`,
    shape: first ? logShape(first) : undefined,
  });
}

async function main(): Promise<void> {
  console.log("=== Data API: Activity & Value ===\n");

  const wallet = await discoverTestWallet();

  await testActivity(wallet);
  await testActivityTypeFilter(wallet);
  await testActivitySideFilter(wallet);
  await testValue(wallet);

  const passed = printSummary("ACTIVITY & VALUE", results);
  const total = results.length;

  if (passed < total) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
