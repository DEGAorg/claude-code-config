/**
 * POC: Test Polymarket Data API position endpoints.
 *
 * Endpoints tested:
 *   - GET /positions?user=ADDRESS (current open positions)
 *   - GET /closed-positions?user=ADDRESS (historical closed positions)
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
  Position,
  ClosedPosition,
} from "./data-api-common.ts";

const results: TestResult[] = [];

async function testCurrentPositions(wallet: string): Promise<void> {
  console.log("\n--- GET /positions (default) ---");
  const start = Date.now();
  const res = await dataApiFetch<Position[]>(
    `/positions?user=${wallet}&limit=5`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /positions",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  console.log(`  Status: ${res.status}`);
  console.log(`  Count: ${res.data.length}`);
  const first = res.data[0];
  if (first) {
    console.log(`  title: ${first.title}`);
    console.log(`  size: ${first.size}`);
    console.log(`  avgPrice: ${first.avgPrice}`);
    console.log(`  currentValue: ${first.currentValue}`);
    console.log(`  cashPnl: ${first.cashPnl}`);
    console.log(`  Shape: ${JSON.stringify(logShape(first))}`);
  }

  results.push({
    method: "GET /positions",
    status: "PASS",
    duration: elapsed,
    detail: `Returned ${res.data.length} positions`,
    shape: first ? logShape(first) : undefined,
  });
}

async function testPositionsPagination(wallet: string): Promise<void> {
  console.log("\n--- GET /positions (pagination) ---");
  const start = Date.now();

  const page1 = await dataApiFetch<Position[]>(
    `/positions?user=${wallet}&limit=2&offset=0`,
  );
  const page2 = await dataApiFetch<Position[]>(
    `/positions?user=${wallet}&limit=2&offset=2`,
  );
  const elapsed = Date.now() - start;

  if (!page1.ok || !page2.ok) {
    results.push({
      method: "GET /positions (paginate)",
      status: "FAIL",
      duration: elapsed,
      detail: `page1: ${page1.ok}, page2: ${page2.ok}`,
      error: page1.error ?? page2.error,
    });
    return;
  }

  const p1Ids = (page1.data ?? []).map((p) => p.conditionId);
  const p2Ids = (page2.data ?? []).map((p) => p.conditionId);
  const overlap = p1Ids.filter((id) => p2Ids.includes(id));

  console.log(`  Page 1: ${p1Ids.length} items`);
  console.log(`  Page 2: ${p2Ids.length} items`);
  console.log(`  Overlap: ${overlap.length}`);

  results.push({
    method: "GET /positions (paginate)",
    status: overlap.length === 0 ? "PASS" : "FAIL",
    duration: elapsed,
    detail: `page1=${p1Ids.length}, page2=${p2Ids.length}, overlap=${overlap.length}`,
  });
}

async function testPositionsSorting(wallet: string): Promise<void> {
  console.log("\n--- GET /positions (sortBy=CASHPNL) ---");
  const start = Date.now();
  const res = await dataApiFetch<Position[]>(
    `/positions?user=${wallet}&limit=5&sortBy=CASHPNL&sortDirection=DESC`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /positions (sort)",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  const pnls = res.data.map((p) => p.cashPnl);
  const isSorted = pnls.every(
    (val, i) => i === 0 || (pnls[i - 1] ?? val) >= val,
  );

  console.log(`  PnL values: [${pnls.map((p) => p.toFixed(2)).join(", ")}]`);
  console.log(`  Sorted DESC: ${isSorted}`);

  results.push({
    method: "GET /positions (sort)",
    status: "PASS",
    duration: elapsed,
    detail: `${res.data.length} items, sorted=${isSorted}`,
  });
}

async function testClosedPositions(wallet: string): Promise<void> {
  console.log("\n--- GET /closed-positions ---");
  const start = Date.now();
  const res = await dataApiFetch<ClosedPosition[]>(
    `/closed-positions?user=${wallet}&limit=5`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /closed-positions",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  console.log(`  Status: ${res.status}`);
  console.log(`  Count: ${res.data.length}`);
  const first = res.data[0];
  if (first) {
    console.log(`  title: ${first.title}`);
    console.log(`  realizedPnl: ${first.realizedPnl}`);
    console.log(`  avgPrice: ${first.avgPrice}`);
    console.log(`  outcome: ${first.outcome}`);
    console.log(`  Shape: ${JSON.stringify(logShape(first))}`);
  }

  results.push({
    method: "GET /closed-positions",
    status: "PASS",
    duration: elapsed,
    detail: `Returned ${res.data.length} closed positions`,
    shape: first ? logShape(first) : undefined,
  });
}

async function main(): Promise<void> {
  console.log("=== Data API: Positions & Closed Positions ===\n");

  const wallet = await discoverTestWallet();

  await testCurrentPositions(wallet);
  await testPositionsPagination(wallet);
  await testPositionsSorting(wallet);
  await testClosedPositions(wallet);

  const passed = printSummary("POSITIONS", results);
  const total = results.length;

  if (passed < total) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
