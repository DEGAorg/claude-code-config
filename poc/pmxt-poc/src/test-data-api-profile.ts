/**
 * POC: Test Polymarket Gamma API public profile endpoint.
 *
 * Endpoints tested:
 *   - GET /public-profile?address=ADDRESS (gamma-api.polymarket.com)
 *   - Invalid address handling
 *
 * No auth required — all data is public.
 */
import {
  gammaApiFetch,
  discoverTestWallet,
  logShape,
  printSummary,
} from "./data-api-common.ts";
import type { TestResult, PublicProfile } from "./data-api-common.ts";

const results: TestResult[] = [];

async function testPublicProfile(wallet: string): Promise<void> {
  console.log("\n--- GET /public-profile ---");
  const start = Date.now();
  const res = await gammaApiFetch<PublicProfile>(
    `/public-profile?address=${wallet}`,
  );
  const elapsed = Date.now() - start;

  if (!res.ok || !res.data) {
    // 404 is expected if the wallet has no profile — still informative
    if (res.status === 404) {
      console.log(`  Profile not found (404) — wallet may not have a profile`);
      results.push({
        method: "GET /public-profile",
        status: "PASS",
        duration: elapsed,
        detail: "404 — no profile for this wallet (expected for some wallets)",
      });
      return;
    }

    results.push({
      method: "GET /public-profile",
      status: "FAIL",
      duration: elapsed,
      detail: res.error ?? "No data",
      error: res.error,
    });
    return;
  }

  console.log(`  name: ${res.data.name ?? "(null)"}`);
  console.log(`  pseudonym: ${res.data.pseudonym ?? "(null)"}`);
  console.log(`  bio: ${res.data.bio ?? "(null)"}`);
  console.log(`  proxyWallet: ${res.data.proxyWallet ?? "(null)"}`);
  console.log(`  Shape: ${JSON.stringify(logShape(res.data))}`);

  results.push({
    method: "GET /public-profile",
    status: "PASS",
    duration: elapsed,
    detail: `name=${res.data.name ?? "(null)"}, pseudonym=${res.data.pseudonym ?? "(null)"}`,
    shape: logShape(res.data),
  });
}

async function testInvalidAddress(): Promise<void> {
  console.log("\n--- GET /public-profile (invalid address) ---");
  const start = Date.now();
  const res = await gammaApiFetch<PublicProfile>(
    "/public-profile?address=0xinvalid",
  );
  const elapsed = Date.now() - start;

  console.log(`  Status: ${res.status}`);
  console.log(`  Error: ${res.error ?? "none"}`);

  // Expect 400 or 422 for invalid address
  const isExpectedError = res.status === 400 || res.status === 404 || res.status === 422;

  results.push({
    method: "GET /public-profile (bad)",
    status: isExpectedError ? "PASS" : "FAIL",
    duration: elapsed,
    detail: `HTTP ${res.status} — ${isExpectedError ? "correct error" : "unexpected status"}`,
  });
}

async function main(): Promise<void> {
  console.log("=== Gamma API: Public Profile ===\n");

  const wallet = await discoverTestWallet();

  await testPublicProfile(wallet);
  await testInvalidAddress();

  const passed = printSummary("PROFILE", results);
  const total = results.length;

  if (passed < total) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
