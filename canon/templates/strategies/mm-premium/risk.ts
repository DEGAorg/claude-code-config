/**
 * MINT-04 Market Making Premium — Risk Checks
 *
 * Implements RiskInterface for pre-trade gating:
 *   - Circuit breaker halt
 *   - Market-close cutoff (reject < 24h to close)
 *   - Hurdle rate gate (projectedNet / cycleCapital ≥ 1.33%)
 *   - Exposure cap (≤ 25% of bankroll across active cycles)
 */

import type {
  AutomationExposure,
  Portfolio,
  RiskDecision,
  RiskInterface,
} from "../../types/RiskInterface.js";
import type { TradeSignal } from "../../types/TradeSignal.js";
import type { MintPremiumConfig } from "./config.js";

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function currentExposure(portfolio: Portfolio): number {
  let total = 0;
  for (const position of portfolio.positions) {
    total += position.size;
  }
  return total;
}

function cutoffReject(
  signal: TradeSignal,
  config: MintPremiumConfig,
): RiskDecision | undefined {
  const ttc = num(signal.metadata["timeToCloseMs"]);
  if (ttc < config.timeToCloseRejectMs) {
    return {
      approved: false,
      rejection_reason:
        `Market close cutoff: timeToClose=${ttc}ms <` +
        ` ${config.timeToCloseRejectMs}ms (24h).`,
    };
  }
  return undefined;
}

function hurdleReject(
  signal: TradeSignal,
  config: MintPremiumConfig,
): RiskDecision | undefined {
  const projectedNet = num(signal.metadata["projectedNet"]);
  const capital = num(signal.metadata["cycleCapital"]) || signal.size;
  const netReturn = capital > 0 ? projectedNet / capital : 0;
  if (netReturn < config.hurdleRate) {
    return {
      approved: false,
      rejection_reason:
        `Hurdle rate not met: ${netReturn.toFixed(5)} <` +
        ` ${config.hurdleRate}.`,
    };
  }
  return undefined;
}

function exposureReject(
  signal: TradeSignal,
  portfolio: Portfolio,
  config: MintPremiumConfig,
): RiskDecision | undefined {
  const bankroll = portfolio.total_value || config.bankroll;
  const limit = config.maxExposure * bankroll;
  const projected = currentExposure(portfolio) + signal.size;
  if (projected > limit) {
    return {
      approved: false,
      rejection_reason:
        `Exposure cap exceeded: $${projected} > $${limit}` +
        ` (${config.maxExposure * 100}% of $${bankroll}).`,
    };
  }
  return undefined;
}

/** MINT-04 risk checker. */
export type MintPremiumRisk = RiskInterface;

/** Create a MINT-04 risk checker implementing RiskInterface. */
export function createRiskChecker(config: MintPremiumConfig): MintPremiumRisk {
  let halted = false;
  let haltReason = "";

  function preTradeCheck(
    signal: TradeSignal,
    portfolio: Portfolio,
  ): RiskDecision {
    if (halted) {
      return {
        approved: false,
        rejection_reason: `Circuit breaker halt: ${haltReason}`,
      };
    }
    return (
      cutoffReject(signal, config) ??
      hurdleReject(signal, config) ??
      exposureReject(signal, portfolio, config) ?? { approved: true }
    );
  }

  function getExposure(): AutomationExposure {
    return {
      total_capital_deployed: 0,
      position_count: 0,
      largest_position: 0,
      markets: [],
    };
  }

  function onCircuitBreaker(reason: string): void {
    halted = true;
    haltReason = reason;
  }

  return { preTradeCheck, getExposure, onCircuitBreaker };
}
