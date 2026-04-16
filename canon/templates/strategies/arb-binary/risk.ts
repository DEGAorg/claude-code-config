/**
 * ARB-01 Binary Arbitrage — Risk Checks
 *
 * Implements RiskInterface for pre-trade risk gating:
 * - Kelly fractional position sizing (quarter Kelly)
 * - Max bankroll exposure cap (8%)
 * - Circuit breaker on consecutive losses
 *
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
 */
export function createRiskChecker(config: RiskConfig): ArbBinaryRisk {
  let consecutiveLosses = 0;

  return {
    preTradeCheck(signal, portfolio) {
      const { bankroll, kellyFraction, maxExposure, maxConsecutiveLosses } =
        config;

      // 1. Circuit breaker — halt after too many consecutive losses
      if (consecutiveLosses >= maxConsecutiveLosses) {
        return {
          approved: false,
          rejection_reason:
            `Circuit breaker: ${consecutiveLosses} consecutive losses` +
            ` (limit ${maxConsecutiveLosses})`,
        };
      }

      // 2. Exposure check — reject if size exceeds max exposure
      const exposureLimit = maxExposure * bankroll;
      if (signal.size > exposureLimit) {
        return {
          approved: false,
          rejection_reason:
            `Exposure limit: $${signal.size} exceeds` +
            ` $${exposureLimit} (${maxExposure * 100}% of bankroll)`,
        };
      }

      // 3. Kelly fractional sizing
      const netReturn = Number(signal.metadata["netReturn"] ?? 0);
      const kellySize = bankroll * kellyFraction * netReturn;

      if (kellySize <= 0) {
        return {
          approved: false,
          rejection_reason:
            `Kelly sizing: computed size $${kellySize.toFixed(2)}` +
            ` (netReturn=${netReturn})`,
        };
      }

      // Approve — reduce size if Kelly is smaller than requested
      if (kellySize < signal.size) {
        return {
          approved: true,
          modified_size: kellySize,
        };
      }

      void portfolio;
      return { approved: true };
    },

    getExposure() {
      return {
        total_capital_deployed: 0,
        position_count: 0,
        largest_position: 0,
        markets: [],
      };
    },

    onCircuitBreaker(_reason) {
      consecutiveLosses = config.maxConsecutiveLosses;
    },

    recordOutcome(won) {
      if (won) {
        consecutiveLosses = 0;
      } else {
        consecutiveLosses += 1;
      }
    },
  };
}
