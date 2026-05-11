/**
 * MINT-01 Scan Adapter
 *
 * Maps the venue-neutral `BinaryMarketSnapshot` shape returned by
 * `client-polymarket.fetchBinaryMarketSnapshots` to the `MarketCandidate`
 * shape consumed by `cycle.selectMarket`. The adapter takes its fetcher
 * via dependency injection so the cycle orchestrator (plan item 5) can
 * stub it alongside its other I/O deps and tests can pin the contract
 * without `vi.mock`.
 *
 *   yesPrice → midpoint   (binary-market midpoint signal)
 *   volume24h, openInterest, yesTokenId, noTokenId, timeToCloseMs → passthrough
 */

import type { BinaryMarketSnapshot } from "../../client-polymarket.js";

import type { MarketCandidate } from "./cycle.js";

/** Injectable dependencies for the MINT-01 scan layer. */
export interface ScanDeps {
  /** Fetch the current set of binary market snapshots for `query`. */
  fetchBinaryMarketSnapshots: (query: string) => Promise<BinaryMarketSnapshot[]>;
}

function toCandidate(snapshot: BinaryMarketSnapshot): MarketCandidate {
  return {
    conditionId: snapshot.conditionId,
    question: snapshot.question,
    midpoint: snapshot.yesPrice,
    timeToCloseMs: snapshot.timeToCloseMs ?? 0,
    volume24h: snapshot.volume24h,
    openInterest: snapshot.openInterest,
    yesTokenId: snapshot.yesTokenId,
    noTokenId: snapshot.noTokenId,
  };
}

/**
 * Fetch binary market snapshots and map them to `MarketCandidate[]`.
 *
 * `query` is forwarded verbatim to `deps.fetchBinaryMarketSnapshots`; it
 * defaults to an empty string (the venue's "list everything" form) when
 * omitted.
 */
export async function fetchSnapshots(
  deps: ScanDeps,
  query: string = "",
): Promise<MarketCandidate[]> {
  const snapshots = await deps.fetchBinaryMarketSnapshots(query);
  return snapshots.map(toCandidate);
}
