/**
 * TRADE-02 Momentum Trading — Risk Checks
 *
 * Implements RiskInterface for pre-trade risk gating:
 * - Per-position exposure cap (10% of bankroll)
 * - Max concurrent open positions (3)
 * - Aggregate exposure cap (30% = maxExposure × maxConcurrent)
 * - Hard floor: reject if timeToClose < 24h
 * - Manipulation guard: reject if topWalletShare > maxTopWalletShare
 * - Circuit breaker halts all approvals once tripped
 */

import type { RiskInterface } from "../../types/RiskInterface.js";
import type { TradeMomentumConfig } from "./config.js";

const HOUR_MS = 60 * 60 * 1000;

/**
 * Create the TRADE-02 risk checker.
 *
 * Check order in `preTradeCheck`:
 * 1. Circuit breaker
 * 2. Wallet-concentration manipulation guard
 * 3. 24h hard floor (timeToClose cutoff)
 * 4. Per-position exposure cap
 * 5. Max concurrent positions
 * 6. Aggregate exposure cap
 */
export function createRiskChecker(
  config: TradeMomentumConfig,
): RiskInterface {
  let circuitBreakerTripped = false;
  let circuitBreakerReason: string | undefined;

  return {
    preTradeCheck(signal, portfolio) {
      if (circuitBreakerTripped) {
        return {
          approved: false,
          rejection_reason:
            `Circuit breaker halted approvals:`
            + ` ${circuitBreakerReason ?? "tripped"}`,
        };
      }

      const topWalletShare = Number(signal.metadata["topWalletShare"] ?? 0);
      if (topWalletShare > config.maxTopWalletShare) {
        return {
          approved: false,
          rejection_reason:
            `Wallet concentration manipulation guard:`
            + ` topWalletShare=${topWalletShare.toFixed(3)}`
            + ` > ${config.maxTopWalletShare}`,
        };
      }

      const timeToCloseMs = Number(
        signal.metadata["timeToCloseMs"] ?? Number.POSITIVE_INFINITY,
      );
      const hardFloorMs = config.minTimeToCloseHours * HOUR_MS;
      if (timeToCloseMs < hardFloorMs) {
        const hours = (timeToCloseMs / HOUR_MS).toFixed(1);
        return {
          approved: false,
          rejection_reason:
            `timeToClose ${hours}h below ${config.minTimeToCloseHours}h`
            + ` hard-floor cutoff`,
        };
      }

      const bankroll = portfolio.total_value > 0
        ? portfolio.total_value
        : config.bankroll;

      const perPositionCap = bankroll * config.maxExposure;
      if (signal.size > perPositionCap) {
        return {
          approved: false,
          rejection_reason:
            `Exposure: requested size $${signal.size.toFixed(2)}`
            + ` exceeds per-position cap $${perPositionCap.toFixed(2)}`
            + ` (${(config.maxExposure * 100).toFixed(0)}% of bankroll)`,
        };
      }

      if (portfolio.positions.length >= config.maxConcurrent) {
        return {
          approved: false,
          rejection_reason:
            `Max concurrent positions reached:`
            + ` ${portfolio.positions.length} >= ${config.maxConcurrent}`,
        };
      }

      const aggregateCap =
        bankroll * config.maxExposure * config.maxConcurrent;
      const currentExposure = portfolio.positions.reduce(
        (sum, pos) => sum + pos.size,
        0,
      );
      if (currentExposure + signal.size > aggregateCap) {
        return {
          approved: false,
          rejection_reason:
            `Aggregate exposure $${(currentExposure + signal.size).toFixed(2)}`
            + ` would exceed cap $${aggregateCap.toFixed(2)}`,
        };
      }

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

    onCircuitBreaker(reason) {
      circuitBreakerTripped = true;
      circuitBreakerReason = reason;
    },
  };
}
