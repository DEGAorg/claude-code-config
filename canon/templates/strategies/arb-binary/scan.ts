/**
 * ARB-01 Binary Arbitrage — Scan Layer
 *
 * Data fetching + transformation: calls searchMarkets and fetchOrderBook,
 * transforms results into MarketData format for signal detection.
 */

import type { MarketData, ArbBinaryConfig } from "./signal.js";
import type { OrderBook } from "../../client-polymarket.js";

/** Market from the search dependency — includes CLOB token IDs. */
export interface ScanSearchResult {
  /** Polymarket condition ID. */
  conditionId: string;
  /** Human-readable market question. */
  question: string;
  /** CLOB token ID for the YES outcome. */
  yesTokenId: string;
  /** CLOB token ID for the NO outcome. */
  noTokenId: string;
}

/** Injectable dependencies for the scan layer. */
export interface ScanDeps {
  /** Search for binary markets by category query. */
  searchMarkets: (query: string) => Promise<ScanSearchResult[]>;
  /** Fetch order book for a CLOB token. */
  fetchOrderBook: (tokenId: string) => Promise<OrderBook>;
}

/**
 * Scan Polymarket for binary markets and transform to signal input.
 *
 * For each market returned by searchMarkets(config.category):
 * 1. Fetch YES and NO order books
 * 2. Extract best ask prices (lowest ask)
 * 3. Estimate slippage from bid-ask spread
 * 4. Return as MarketData for signal detection
 */
export async function scanMarkets(
  config: ArbBinaryConfig,
  deps: ScanDeps,
): Promise<MarketData[]> {
  // TDD stub — implementation satisfies tests in item 6
  void config;
  void deps;
  return [];
}
