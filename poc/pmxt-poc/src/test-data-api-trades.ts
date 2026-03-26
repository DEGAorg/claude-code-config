/**
 * POC: Test Polymarket Data API trades endpoint.
 *
 * Endpoints tested:
 *   - GET /trades (recent trades, no user filter)
 *   - GET /trades?user=ADDRESS (user-specific trades)
 *   - GET /trades?user=ADDRESS&side=BUY (side filter)
 *   - GET /trades pagination
 *
 * No auth required — all data is public.
 */
import {
  dataApiFetch,
  discoverTestWallet,
  logShape,
  printSummary,
} from "./data-api-common.ts";
import type { TestResult, Trade } from "./data-api-common.ts";

const results: TestResult[] = [];

async function testRecentTrades(): Promise<void> {
  console.log("\n--- GET /trades (no user, limit=5) ---");
  const start = Date.now();
  const res = await dataApiFetch<Trade[]>("/trades?limit=5");
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /trades (global)",
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
    console.log(`  title: ${first.title}`);
    console.log(`  side: ${first.side}`);
    console.log(`  size: ${first.size}`);
    console.log(`  price: ${first.price}`);
    console.log(`  proxyWallet: ${first.proxyWallet}`);
    console.log(`  Shape: ${JSON.stringify(logShape(first))}`);
  }

  results.push({
    method: "GET /trades (global)",
    status: "PASS",
    duration: elapsed,
    detail: `Returned ${res.data.length} trades`,
    shape: first ? logShape(first) : undefined,
  });
}

async function testUserTrades(wallet: string): Promise<void> {
  console.log("\n--- GET /trades?user=... ---");
  const start = Date.now();
  const res = await dataApiFetch<Trade[]>(
    `/trades?user=${wallet}&limit=5`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /trades (user)",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  const allSameWallet = res.data.every(
    (t) => t.proxyWallet.toLowerCase() === wallet.toLowerCase(),
  );
  console.log(`  Count: ${res.data.length}`);
  console.log(`  All same wallet: ${allSameWallet}`);

  results.push({
    method: "GET /trades (user)",
    status: allSameWallet || res.data.length === 0 ? "PASS" : "FAIL",
    duration: elapsed,
    detail: `${res.data.length} trades, allSameWallet=${allSameWallet}`,
  });
}

async function testTradesSideFilter(wallet: string): Promise<void> {
  console.log("\n--- GET /trades?user=...&side=BUY ---");
  const start = Date.now();
  const res = await dataApiFetch<Trade[]>(
    `/trades?user=${wallet}&side=BUY&limit=5`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    results.push({
      method: "GET /trades (side)",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  const allBuy = res.data.every((t) => t.side === "BUY");
  console.log(`  Count: ${res.data.length}`);
  console.log(`  All BUY: ${allBuy}`);
  console.log(`  Sides: ${[...new Set(res.data.map((t) => t.side))].join(", ")}`);

  results.push({
    method: "GET /trades (side)",
    status: allBuy || res.data.length === 0 ? "PASS" : "FAIL",
    duration: elapsed,
    detail: `${res.data.length} trades, allBuy=${allBuy}`,
  });
}

async function testTradesPagination(): Promise<void> {
  console.log("\n--- GET /trades (pagination) ---");
  const start = Date.now();

  const page1 = await dataApiFetch<Trade[]>("/trades?limit=3&offset=0");
  const page2 = await dataApiFetch<Trade[]>("/trades?limit=3&offset=3");
  const elapsed = Date.now() - start;

  if (!page1.ok || !page2.ok) {
    results.push({
      method: "GET /trades (paginate)",
      status: "FAIL",
      duration: elapsed,
      detail: `page1: ${page1.ok}, page2: ${page2.ok}`,
      error: page1.error ?? page2.error,
    });
    return;
  }

  const p1Hashes = (page1.data ?? []).map((t) => t.transactionHash);
  const p2Hashes = (page2.data ?? []).map((t) => t.transactionHash);
  const overlap = p1Hashes.filter((h) => p2Hashes.includes(h));

  console.log(`  Page 1: ${p1Hashes.length} items`);
  console.log(`  Page 2: ${p2Hashes.length} items`);
  console.log(`  Overlap: ${overlap.length}`);

  results.push({
    method: "GET /trades (paginate)",
    status: overlap.length === 0 ? "PASS" : "FAIL",
    duration: elapsed,
    detail: `page1=${p1Hashes.length}, page2=${p2Hashes.length}, overlap=${overlap.length}`,
  });
}

async function main(): Promise<void> {
  console.log("=== Data API: Trades ===\n");

  const wallet = await discoverTestWallet();

  await testRecentTrades();
  await testUserTrades(wallet);
  await testTradesSideFilter(wallet);
  await testTradesPagination();

  const passed = printSummary("TRADES", results);
  const total = results.length;

  if (passed < total) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
