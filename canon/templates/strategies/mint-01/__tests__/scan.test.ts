/**
 * Tests for `canon/templates/strategies/mint-01/scan.ts`.
 *
 * The scan layer adapts `client-polymarket.fetchBinaryMarketSnapshots`
 * (the venue-neutral snapshot shape) to the `MarketCandidate[]` shape
 * that `cycle.selectMarket` consumes. These tests pin the contract:
 *
 *   1. The adapter forwards a configurable query string to the
 *      injected `fetchBinaryMarketSnapshots` stub (default = empty).
 *   2. Each `BinaryMarketSnapshot` maps to a `MarketCandidate` with
 *      `volume24h`, `yesTokenId`, `noTokenId`, `midpoint`, and
 *      `timeToCloseMs` populated.
 *
 * Dependency injection (no `vi.mock`) keeps the seam explicit — the
 * cycle orchestrator in plan item 5 stubs `scan` as one of its deps,
 * so `fetchSnapshots(deps, query?)` is the production shape exercised
 * here.
 */

import { describe, it, expect, vi } from "vitest";

import type { BinaryMarketSnapshot } from "../../../client-polymarket.js";
import type { MarketCandidate } from "../cycle.js";
import { fetchSnapshots, type ScanDeps } from "../scan.js";

const yesTokenId =
  "12345678901234567890123456789012345678901234567890123456789012345";
const noTokenId =
  "98765432109876543210987654321098765432109876543210987654321098765";

function makeSnapshot(
  overrides?: Partial<BinaryMarketSnapshot>,
): BinaryMarketSnapshot {
  return {
    conditionId: "0xcond-001",
    question: "Will the Lakers win?",
    yesTokenId,
    noTokenId,
    yesPrice: 0.42,
    noPrice: 0.58,
    volume24h: 50_000,
    openInterest: 20_000,
    timeToCloseMs: 7 * 24 * 60 * 60 * 1000,
    timestampMs: 1_715_000_000_000,
    ...overrides,
  };
}

function makeDeps(
  snapshots: BinaryMarketSnapshot[] = [],
): ScanDeps & {
  fetchBinaryMarketSnapshots: ReturnType<typeof vi.fn>;
} {
  const fetchBinaryMarketSnapshots = vi.fn(async (_query: string) => snapshots);
  return { fetchBinaryMarketSnapshots };
}

describe("fetchSnapshots — query forwarding", () => {
  it("forwards a configurable query string to fetchBinaryMarketSnapshots", async () => {
    const deps = makeDeps([]);
    await fetchSnapshots(deps, "Sports");
    expect(deps.fetchBinaryMarketSnapshots).toHaveBeenCalledTimes(1);
    expect(deps.fetchBinaryMarketSnapshots).toHaveBeenCalledWith("Sports");
  });

  it("defaults the query to an empty string when none is supplied", async () => {
    const deps = makeDeps([]);
    await fetchSnapshots(deps);
    expect(deps.fetchBinaryMarketSnapshots).toHaveBeenCalledWith("");
  });

  it("forwards a distinct second query on a follow-up call", async () => {
    const deps = makeDeps([]);
    await fetchSnapshots(deps, "Politics");
    await fetchSnapshots(deps, "NBA");
    expect(deps.fetchBinaryMarketSnapshots).toHaveBeenNthCalledWith(1, "Politics");
    expect(deps.fetchBinaryMarketSnapshots).toHaveBeenNthCalledWith(2, "NBA");
  });
});

describe("fetchSnapshots — BinaryMarketSnapshot → MarketCandidate mapping", () => {
  it("returns one candidate per snapshot (preserves array shape)", async () => {
    const snaps = [
      makeSnapshot({ conditionId: "c1" }),
      makeSnapshot({ conditionId: "c2" }),
      makeSnapshot({ conditionId: "c3" }),
    ];
    const deps = makeDeps(snaps);
    const candidates = await fetchSnapshots(deps);
    expect(candidates).toHaveLength(3);
    expect(candidates.map((c) => c.conditionId)).toEqual(["c1", "c2", "c3"]);
  });

  it("populates volume24h from snapshot.volume24h", async () => {
    const deps = makeDeps([makeSnapshot({ volume24h: 87_500 })]);
    const [candidate] = await fetchSnapshots(deps);
    expect(candidate).toBeDefined();
    expect((candidate as MarketCandidate).volume24h).toBe(87_500);
  });

  it("populates yesTokenId from snapshot.yesTokenId", async () => {
    const deps = makeDeps([makeSnapshot()]);
    const [candidate] = await fetchSnapshots(deps);
    expect((candidate as MarketCandidate).yesTokenId).toBe(yesTokenId);
  });

  it("populates noTokenId from snapshot.noTokenId", async () => {
    const deps = makeDeps([makeSnapshot()]);
    const [candidate] = await fetchSnapshots(deps);
    expect((candidate as MarketCandidate).noTokenId).toBe(noTokenId);
  });

  it("populates midpoint from snapshot.yesPrice", async () => {
    const deps = makeDeps([makeSnapshot({ yesPrice: 0.42 })]);
    const [candidate] = await fetchSnapshots(deps);
    expect((candidate as MarketCandidate).midpoint).toBe(0.42);
  });

  it("populates timeToCloseMs from snapshot.timeToCloseMs", async () => {
    const sevenDays = 7 * 24 * 60 * 60 * 1000;
    const deps = makeDeps([makeSnapshot({ timeToCloseMs: sevenDays })]);
    const [candidate] = await fetchSnapshots(deps);
    expect((candidate as MarketCandidate).timeToCloseMs).toBe(sevenDays);
  });

  it("maps a single snapshot end-to-end with all five required fields", async () => {
    const snapshot = makeSnapshot({
      conditionId: "0xcond-end-to-end",
      question: "End-to-end mapping?",
      yesTokenId: "yes-end2end",
      noTokenId: "no-end2end",
      yesPrice: 0.61,
      volume24h: 123_456,
      timeToCloseMs: 3 * 24 * 60 * 60 * 1000,
    });
    const deps = makeDeps([snapshot]);
    const [candidate] = await fetchSnapshots(deps);

    expect(candidate).toMatchObject({
      conditionId: "0xcond-end-to-end",
      question: "End-to-end mapping?",
      yesTokenId: "yes-end2end",
      noTokenId: "no-end2end",
      midpoint: 0.61,
      volume24h: 123_456,
      timeToCloseMs: 3 * 24 * 60 * 60 * 1000,
    });
  });

  it("produces candidates that pass `selectMarket` filters when snapshot meets thresholds", async () => {
    // Smoke-test the contract end-to-end: a healthy snapshot should
    // survive selectMarket so the downstream cycle orchestrator can
    // pick it. Imported lazily to avoid coupling the mapping tests to
    // selectMarket's filter math.
    const { selectMarket } = await import("../cycle.js");
    const { DEFAULT_MINT_01_CONFIG } = await import("../config.js");

    const deps = makeDeps([
      makeSnapshot({
        volume24h: 50_000,
        openInterest: 20_000,
        yesPrice: 0.5,
        timeToCloseMs: 7 * 24 * 60 * 60 * 1000,
      }),
    ]);
    const candidates = await fetchSnapshots(deps);
    const choice = selectMarket(candidates, DEFAULT_MINT_01_CONFIG);
    expect(choice).not.toBeNull();
    expect(choice?.candidate.yesTokenId).toBe(yesTokenId);
    expect(choice?.candidate.noTokenId).toBe(noTokenId);
  });
});
