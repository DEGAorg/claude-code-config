/**
 * MINT-04 Market Making Premium — Configuration
 *
 * Scanner + live cycle template: detects markets where minting $N sets and
 * posting paired limit sells at midpoint ± offset is viable, then
 * (when `--live`) runs a full mint + dual-leg cycle via
 * `cycle.ts:runMmPremiumCycle`.
 *
 * **`cycleCapital` default is $5 — a safe smoke-test size.** Spec target
 * for production is $1,000 (the C2-spec scale at which the hurdle rate
 * — net/capital ≥ 1.33% — clears). Operators raise this in their
 * scaffolded `src/config.ts` after live verification.
 */

/** MINT-04 market-making premium configuration. */
export interface MintPremiumConfig {
  /** Kelly fraction for position sizing. */
  kellyFraction: number;
  /** Max share of bankroll allowed in active cycles. */
  maxExposure: number;
  /** Minimum net-return per cycle required to pass the hurdle gate. */
  hurdleRate: number;
  /** Flat fee per $1,000 cycle (USD). */
  feeRate: number;
  /** Flat gas cost per cycle (USD). */
  gasCost: number;
  /** LP rebate credited per $1,000 cycle (USD). */
  lpRebate: number;
  /** Gross revenue per $1,000 cycle at default offset (USD). */
  grossPerCycle: number;
  /** Capital deployed per cycle (USD). */
  cycleCapital: number;
  /** Default offset in cents for mid-volume markets. */
  offsetDefaultC: number;
  /** Aggressive offset in cents for high-volume markets. */
  offsetAggressiveC: number;
  /** Fallback offset when per-leg activity is low. */
  offsetDefensiveC: number;
  /** Confluence threshold — volume_24h (USD). */
  volume24hThreshold: number;
  /** Confluence threshold — trades per hour. */
  trades1hThreshold: number;
  /** Confluence threshold — max bid-ask spread. */
  spreadThreshold: number;
  /** Volume bracket above which the aggressive offset is selected. */
  volumeAggressiveThreshold: number;
  /** Volume floor below which MINT-02 downgrade is advised. */
  volumeDowngradeThreshold: number;
  /** Minimum trades/hour per leg before a low-activity warning fires. */
  minTradesPerHour: number;
  /** Market-close cutoff (ms) — reject cycles below. */
  timeToCloseRejectMs: number;
  /** Short-cycle adjustment window (ms) — between reject and full. */
  timeToCloseAdjustMs: number;
  /** Signal time-to-live (ms). */
  signalTtlMs: number;
  /** Total available bankroll (USD). */
  bankroll: number;
  /**
   * Stop-loss drift threshold in dollars. If `|currentMidpoint − entryMidpoint|`
   * exceeds this value, both legs are cancelled and the cycle exits.
   */
  stopLossDrift: number;
  /** Override the fill-poll interval (ms). */
  fillPollIntervalMs: number;
  /** Maximum duration to keep an unfilled cycle open before forcing reconcile. */
  maxCycleDurationMs: number;
}

/** C2/D2 production defaults for MINT-04. */
export const DEFAULT_MM_PREMIUM_CONFIG: MintPremiumConfig = {
  kellyFraction: 1.0,
  maxExposure: 0.25,
  // hurdleRate ships at 0 so the $5 smoke default actually finds a
  // viable market. The C2 spec gate is 0.0133 (1.33% net/capital) — at
  // that level the strategy needs ≥~$154 cycleCapital to clear gas. Raise
  // this when you raise cycleCapital for production. Setting it >0 with
  // a small cycleCapital will reject every market.
  hurdleRate: 0,
  feeRate: 0.0017,
  gasCost: 0.05,
  lpRebate: 0.325,
  grossPerCycle: 15,
  cycleCapital: 5,
  offsetDefaultC: 0.0075,
  offsetAggressiveC: 0.01,
  offsetDefensiveC: 0.005,
  volume24hThreshold: 20_000,
  trades1hThreshold: 10,
  spreadThreshold: 0.015,
  volumeAggressiveThreshold: 50_000,
  volumeDowngradeThreshold: 10_000,
  minTradesPerHour: 3,
  timeToCloseRejectMs: 24 * 60 * 60 * 1000,
  timeToCloseAdjustMs: 48 * 60 * 60 * 1000,
  signalTtlMs: 6 * 60 * 60 * 1000,
  bankroll: 10_000,
  stopLossDrift: 0.05,
  fillPollIntervalMs: 300_000,
  maxCycleDurationMs: 24 * 60 * 60 * 1000,
};

/**
 * Projected net profit per $1,000 cycle at default offset, in USD.
 *
 * bruto ($15) − fees ($1.70) − gas ($0.05) + lp ($0.325) = $13.575.
 * Fees are quoted flat per $1,000 in the source spec, so they are scaled
 * linearly by cycle capital and converted to USD here.
 */
export function projectedNetPerCycle(
  config: MintPremiumConfig = DEFAULT_MM_PREMIUM_CONFIG,
): number {
  const capitalRatio = config.cycleCapital / 1_000;
  const fees = config.feeRate * 1_000 * capitalRatio;
  const lp = config.lpRebate * capitalRatio;
  const gross = config.grossPerCycle * capitalRatio;
  return gross - fees - config.gasCost + lp;
}
