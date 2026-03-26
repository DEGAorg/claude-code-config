/**
 * Shared types, fetch wrapper, and test wallet discovery for Data API tests.
 *
 * The Polymarket Data API (data-api.polymarket.com) is a public REST API
 * that requires no authentication. All endpoints return JSON arrays.
 */

const DATA_API_BASE = "https://data-api.polymarket.com";
const GAMMA_API_BASE = "https://gamma-api.polymarket.com";

/** Delay between requests to avoid undocumented rate limits. */
const REQUEST_DELAY_MS = 500;

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

export interface TestResult {
  method: string;
  status: "PASS" | "FAIL" | "SKIP";
  duration: number;
  detail: string;
  shape?: Record<string, string>;
  error?: string;
}

export interface Trade {
  proxyWallet: string;
  side: string;
  asset: string;
  conditionId: string;
  size: number;
  price: number;
  timestamp: number;
  title: string;
  slug: string;
  icon: string;
  eventSlug: string;
  outcome: string;
  outcomeIndex: number;
  name: string;
  pseudonym: string;
  bio: string;
  profileImage: string;
  profileImageOptimized: string;
  transactionHash: string;
}

export interface Position {
  proxyWallet: string;
  asset: string;
  conditionId: string;
  size: number;
  avgPrice: number;
  initialValue: number;
  currentValue: number;
  cashPnl: number;
  percentPnl: number;
  totalBought: number;
  realizedPnl: number;
  percentRealizedPnl: number;
  curPrice: number;
  redeemable: boolean;
  mergeable: boolean;
  title: string;
  slug: string;
  icon: string;
  eventId: string;
  eventSlug: string;
  outcome: string;
  outcomeIndex: number;
  oppositeOutcome: string;
  oppositeAsset: string;
  endDate: string;
  negativeRisk: boolean;
}

export interface ClosedPosition {
  proxyWallet: string;
  asset: string;
  conditionId: string;
  size: number;
  avgPrice: number;
  initialValue: number;
  currentValue: number;
  cashPnl: number;
  percentPnl: number;
  totalBought: number;
  realizedPnl: number;
  percentRealizedPnl: number;
  curPrice: number;
  redeemable: boolean;
  mergeable: boolean;
  title: string;
  slug: string;
  icon: string;
  eventSlug: string;
  outcome: string;
  outcomeIndex: number;
  endDate: string;
  negativeRisk: boolean;
}

export interface Activity {
  proxyWallet: string;
  asset: string;
  conditionId: string;
  type: string;
  size: number;
  price: number;
  timestamp: number;
  title: string;
  slug: string;
  icon: string;
  eventSlug: string;
  outcome: string;
  outcomeIndex: number;
  transactionHash: string;
}

export interface PortfolioValue {
  timestamp: number;
  value: number;
}

export interface PublicProfile {
  name: string;
  pseudonym: string;
  bio: string;
  profileImage: string;
  profileImageOptimized: string;
  proxyWallet: string;
}

// ---------------------------------------------------------------------------
// Fetch wrapper with error handling and rate-limit delay
// ---------------------------------------------------------------------------

let lastRequestTime = 0;

async function rateLimit(): Promise<void> {
  const elapsed = Date.now() - lastRequestTime;
  if (elapsed < REQUEST_DELAY_MS) {
    await new Promise((resolve) => {
      setTimeout(resolve, REQUEST_DELAY_MS - elapsed);
    });
  }
  lastRequestTime = Date.now();
}

export interface FetchResult<T> {
  ok: boolean;
  status: number;
  data: T | null;
  error?: string;
  duration: number;
}

/**
 * Fetch a Data API endpoint with built-in rate limiting and error handling.
 *
 * @param path  Absolute path starting with / (e.g. "/trades?limit=5")
 * @param base  API base URL — defaults to data-api.polymarket.com
 */
export async function dataApiFetch<T>(
  path: string,
  base: string = DATA_API_BASE,
): Promise<FetchResult<T>> {
  await rateLimit();

  const url = `${base}${path}`;
  const start = Date.now();

  try {
    const resp = await fetch(url, {
      headers: { Accept: "application/json" },
    });
    const duration = Date.now() - start;

    if (!resp.ok) {
      const body = await resp.text().catch(() => "(unreadable)");
      return {
        ok: false,
        status: resp.status,
        data: null,
        error: `HTTP ${resp.status}: ${body.slice(0, 200)}`,
        duration,
      };
    }

    const data = (await resp.json()) as T;
    return { ok: true, status: resp.status, data, duration };
  } catch (err) {
    return {
      ok: false,
      status: 0,
      data: null,
      error: `Fetch error: ${String(err).slice(0, 200)}`,
      duration: Date.now() - start,
    };
  }
}

/**
 * Convenience wrapper for gamma-api.polymarket.com endpoints.
 */
export async function gammaApiFetch<T>(
  path: string,
): Promise<FetchResult<T>> {
  return dataApiFetch<T>(path, GAMMA_API_BASE);
}

// ---------------------------------------------------------------------------
// Test wallet discovery from /trades
// ---------------------------------------------------------------------------

/**
 * Discover a test wallet by fetching recent trades. Returns the proxyWallet
 * of a recent trader with meaningful activity (size > threshold).
 *
 * Tries multiple passes with increasing limit to find a suitable wallet.
 */
export async function discoverTestWallet(): Promise<string> {
  console.log("\n--- Discovering test wallet from /trades ---");

  const result = await dataApiFetch<Trade[]>("/trades?limit=50");

  if (!result.ok || !result.data || result.data.length === 0) {
    throw new Error(
      `Failed to discover test wallet: ${result.error ?? "no trades returned"}`,
    );
  }

  // Find a wallet with a reasonable trade size (not dust)
  const minSize = 5;
  const candidate = result.data.find((t) => t.size >= minSize);

  if (!candidate) {
    // Fall back to first trade if none meet size threshold
    const fallback = result.data[0];
    if (!fallback) {
      throw new Error("No trades returned from /trades");
    }
    console.log(
      `  No trade >= $${minSize} found, using fallback wallet`,
    );
    console.log(`  Wallet: ${fallback.proxyWallet}`);
    console.log(
      `  From trade: "${fallback.title}" ($${fallback.size} @ ${fallback.price})`,
    );
    return fallback.proxyWallet;
  }

  console.log(`  Found wallet: ${candidate.proxyWallet}`);
  console.log(
    `  From trade: "${candidate.title}" ($${candidate.size} @ ${candidate.price})`,
  );
  console.log(`  Side: ${candidate.side}, Outcome: ${candidate.outcome}`);

  return candidate.proxyWallet;
}

// ---------------------------------------------------------------------------
// Helpers shared across test files
// ---------------------------------------------------------------------------

/**
 * Introspect the shape of an object for logging. Returns a flat
 * {fieldName: "type"} map. Recurses into the first element of arrays.
 */
export function logShape(obj: unknown): Record<string, string> {
  if (obj === null || obj === undefined) return { value: String(obj) };
  if (Array.isArray(obj)) {
    if (obj.length === 0) return { type: "empty array" };
    return logShape(obj[0]);
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

/**
 * Print summary table and "Result:" line for run-all.ts parser.
 * Returns the number of passed tests.
 */
export function printSummary(
  suiteName: string,
  results: TestResult[],
): number {
  console.log(`\n\n=== ${suiteName} SUMMARY ===`);
  console.log(
    "Method                  | Status | Duration | Detail",
  );
  console.log(
    "------------------------|--------|----------|-------",
  );
  for (const r of results) {
    const method = r.method.padEnd(24);
    const status = r.status.padEnd(6);
    const dur = `${r.duration}ms`.padEnd(8);
    console.log(`${method}| ${status} | ${dur} | ${r.detail}`);
    if (r.error) {
      console.log(
        `                        |        |          | ERROR: ${r.error.slice(0, 200)}`,
      );
    }
  }

  const passed = results.filter((r) => r.status === "PASS").length;
  const total = results.length;
  console.log(`\nResult: ${passed}/${total} passed`);

  return passed;
}
