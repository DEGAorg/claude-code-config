/**
 * ARB-01 Binary Arbitrage — Risk Checks
 *
 * Implements RiskInterface for pre-trade risk gating:
 * - Kelly fractional position sizing (quarter Kelly)
 * - Max bankroll exposure cap (8%)
 * - Circuit breaker on consecutive losses
 *
 * TDD stub — implementation replaces this body (Item 4).
 */

import type { RiskInterface } from "../../types/RiskInterface.js";

/** Configuration for the ARB-01 risk checker. */
export interface RiskConfig {
  /** Total bankroll in USD. */
  bankroll: number;
  /** Kelly criterion fraction (e.g. 0.25 = quarter Kelly). */
  kellyFraction: number;
  /** Max single-position exposure as fraction of bankroll. */
  maxExposure: number;
  /** Consecutive losses before circuit breaker trips. */
  maxConsecutiveLosses: number;
}

/** ARB-01 risk checker with outcome tracking for circuit breaker. */
export interface ArbBinaryRisk extends RiskInterface {
  /** Record a trade outcome to track consecutive losses. */
  recordOutcome(won: boolean): void;
}

/**
 * Create an ARB-01 risk checker implementing RiskInterface.
 *
 * The checker gates every signal through:
 * 1. Circuit breaker — reject if consecutive losses >= threshold
 * 2. Exposure check — reject if signal size > maxExposure * bankroll
 * 3. Kelly sizing — reduce size to bankroll * kellyFraction * netReturn
 *    (reject if Kelly size rounds to zero)
 *
 * TDD stub — throws until Item 4 implements.
 */
export function createRiskChecker(_config: RiskConfig): ArbBinaryRisk {
  throw new Error("Not implemented — TDD stub");
}
