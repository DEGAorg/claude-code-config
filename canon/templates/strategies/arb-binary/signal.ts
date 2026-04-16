/**
 * ARB-01 Binary Arbitrage — Signal Detection
 *
 * Pure function: takes pre-fetched market data and config,
 * returns TradeSignal[] for markets with arbitrage edges.
 *
 * TDD stub — implementation replaces this body (Item 3).
 */

import type { TradeSignal } from "../../types/TradeSignal.js";

/** Market data from the scan layer — input to signal detection. */
export interface MarketData {
  /** Polymarket condition ID. */
  conditionId: string;
  /** Human-readable market question. */
  question: string;
  /** Market category (e.g. "NBA", "crypto"). */
  category: string;
  /** Best ask price for the YES outcome (0.0-1.0). */
  yesAsk: number;
  /** Best ask price for the NO outcome (0.0-1.0). */
  noAsk: number;
  /** CLOB token ID for the YES outcome. */
  yesTokenId: string;
  /** CLOB token ID for the NO outcome. */
  noTokenId: string;
  /** Estimated slippage as a fraction (e.g. 0.001 = 0.1%). */
  estimatedSlippage: number;
}

/** Configuration for the ARB-01 signal detector. */
export interface ArbBinaryConfig {
  /** Required category filter — no scan-all mode. */
  category: string;
  /** Platform fee rate per trade (e.g. 0.02 = 2%). */
  feeRate: number;
  /** Flat gas cost per signal in USD. */
  gasCost: number;
  /** Minimum net return threshold (e.g. 0.015 = 1.5%). */
  hurdleRate: number;
  /** Max estimated slippage before aborting (e.g. 0.003 = 0.3%). */
  slippageAbort: number;
  /** Total bankroll in USD. */
  bankroll: number;
  /** Kelly criterion fraction (e.g. 0.25 = quarter Kelly). */
  kellyFraction: number;
  /** Max single-position exposure as fraction of bankroll. */
  maxExposure: number;
  /** Signal time-to-live in milliseconds. */
  signalTtlMs: number;
}

/**
 * Detect binary arbitrage opportunities in market data.
 *
 * For each market matching the config category:
 * 1. Check if YES_ask + NO_ask < $1.00 (edge exists)
 * 2. Deduct fees (platform fee + gas)
 * 3. Verify net return >= hurdle rate
 * 4. Verify estimated slippage < abort threshold
 * 5. Emit buy_yes + buy_no TradeSignal pair
 *
 * TDD stub — throws until Item 3 implements.
 */
export function detectSignals(
  _markets: MarketData[],
  _config: ArbBinaryConfig,
): TradeSignal[] {
  throw new Error("Not implemented — TDD stub");
}
