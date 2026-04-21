/**
 * ARB-03 NegRisk Multi-condition Buy — Risk Checks
 *
 * Pre-trade gates for multi-leg NegRisk arbitrage:
 * - Circuit breaker on consecutive losses
 * - Per-leg low-liquidity price cap (thin high-price legs reject)
 * - Per-leg minimum-liquidity bottleneck
 * - Total-bundle exposure cap (maxExposure × bankroll)
 * - Fractional-Kelly bundle sizing, capped by bottleneck liquidity
 */

import type { Portfolio } from "../../types/RiskInterface.js";
import type { NegRiskOpportunity } from "./signal.js";

/** Configuration for the ARB-03 NegRisk risk checker. */
export interface RiskConfig {
  /** Total bankroll in USD. */
  bankroll: number;
  /** Kelly criterion fraction (e.g. 0.15 = 15% of Kelly). */
  kellyFraction: number;
  /** Max total-bundle exposure as fraction of bankroll (all legs combined). */
  maxExposure: number;
  /** Minimum per-leg liquidity in USD — bundle rejected if any leg below. */
  minLegLiquidity: number;
  /** Price cap for legs below `lowLiqThreshold`. */
  maxLegPriceWithLowLiq: number;
  /** Liquidity threshold that triggers the low-liq price cap. */
  lowLiqThreshold: number;
  /** Consecutive losses before the circuit breaker trips. */
  maxConsecutiveLosses: number;
}

/** Result of a pre-trade risk check on a NegRisk opportunity. */
export interface NegRiskRiskDecision {
  /** Whether the bundle is approved for entry. */
  approved: boolean;
  /** Reason for rejection (present when `approved` is false). */
  rejection_reason?: string | undefined;
  /** Total USD size across the whole bundle (all legs combined). */
  total_size?: number | undefined;
  /** USD size for each individual leg. */
  per_leg_size?: number | undefined;
}

/** ARB-03 risk checker with outcome tracking for circuit breaker. */
export interface NegRiskRiskChecker {
  /** Gate an opportunity before entry. */
  preTradeCheck(
    opportunity: NegRiskOpportunity,
    portfolio: Portfolio,
  ): NegRiskRiskDecision;
  /** Record the outcome of a completed bundle (true = win). */
  recordOutcome(won: boolean): void;
}

/**
 * Create an ARB-03 risk checker.
 *
 * Check order (fail-fast):
 * 1. Circuit breaker — reject if consecutive losses reached.
 * 2. Low-liquidity price cap — reject if any leg price > cap AND
 *    liquidity < `lowLiqThreshold` (thin high-price legs are traps).
 * 3. Bottleneck liquidity — reject if weakest leg < `minLegLiquidity`.
 * 4. Sizing — fractional-Kelly on netEdge, capped by both
 *    `maxExposure × bankroll` and the per-leg bottleneck liquidity.
 */
export function createRiskChecker(config: RiskConfig): NegRiskRiskChecker {
  let consecutiveLosses = 0;

  return {
    preTradeCheck(opportunity, portfolio) {
      void portfolio;

      if (consecutiveLosses >= config.maxConsecutiveLosses) {
        return {
          approved: false,
          rejection_reason:
            `Circuit breaker: ${consecutiveLosses} consecutive losses` +
            ` (limit ${config.maxConsecutiveLosses})`,
        };
      }

      const legs = opportunity.market.legs;

      for (const leg of legs) {
        if (
          leg.yesBid > config.maxLegPriceWithLowLiq &&
          leg.liquidity < config.lowLiqThreshold
        ) {
          return {
            approved: false,
            rejection_reason:
              `Leg ${leg.tokenId} price ${leg.yesBid} exceeds cap` +
              ` ${config.maxLegPriceWithLowLiq} with thin liquidity` +
              ` $${leg.liquidity} (< $${config.lowLiqThreshold})`,
          };
        }
      }

      let minLiq = Number.POSITIVE_INFINITY;
      for (const leg of legs) {
        if (leg.liquidity < minLiq) minLiq = leg.liquidity;
      }

      if (minLiq < config.minLegLiquidity) {
        return {
          approved: false,
          rejection_reason:
            `Bottleneck liquidity $${minLiq} below minLegLiquidity` +
            ` $${config.minLegLiquidity}`,
        };
      }

      const totalExposureCap = config.bankroll * config.maxExposure;
      const kellyBundleSize =
        config.bankroll * config.kellyFraction * opportunity.netEdge;
      const totalSize = Math.max(
        0,
        Math.min(totalExposureCap, kellyBundleSize),
      );
      const perLegFromTotal = totalSize / legs.length;
      const perLegSize = Math.min(perLegFromTotal, minLiq);

      return {
        approved: true,
        total_size: totalSize,
        per_leg_size: perLegSize,
      };
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
