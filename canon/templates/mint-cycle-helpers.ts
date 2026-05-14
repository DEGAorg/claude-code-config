/**
 * MINT cycle shared helpers.
 *
 * Strategy-agnostic primitives used by mint-cycle strategies (MINT-01 today,
 * future MINT-* variants). Two pure functions:
 *
 *   - `planTwoLegs(yesMidpoint, offset, size)` — derive a two-leg sell plan
 *     from a YES midpoint and a flat premium offset. The NO leg is sized off
 *     the binary complement `1 − yesMidpoint`. Throws on degenerate
 *     midpoints (outside `(0, 1)`) or when the premium would push either
 *     leg to `>= 1` (unfillable above-cap quotes).
 *
 *   - `withinDriftBand(entry, current, threshold)` — inclusive in-band
 *     check: returns `true` when `|current − entry| <= threshold`. The
 *     dual `shouldStopLoss` is therefore `!withinDriftBand(...)`.
 *
 * No I/O, no config coupling. Strategy modules (e.g. `strategies/mint-01/
 * cycle.ts`) compose these with their own config shape.
 */

/** A planned two-leg sell quote. */
export interface TwoLegPlan {
  /** Sell-limit price for the YES leg (= yesMidpoint + offset). */
  yesPrice: number;
  /** Sell-limit price for the NO leg (= (1 − yesMidpoint) + offset). */
  noPrice: number;
  /** Size of each leg in outcome-token units. */
  size: number;
}

/**
 * Plan two sell legs at `midpoint + offset` on each side of a binary market.
 *
 * @param yesMidpoint YES outcome midpoint in `(0, 1)`. The NO midpoint is
 *                    the binary complement `1 − yesMidpoint`.
 * @param offset      Flat premium offset added to each leg's midpoint, in
 *                    dollars. May be zero (legs sit on the midpoint).
 * @param size        Size of each leg in outcome-token units. Passed through
 *                    unchanged.
 *
 * Throws when `yesMidpoint` is outside `(0, 1)` or when either leg price
 * would land at `>= 1`.
 */
export function planTwoLegs(
  yesMidpoint: number,
  offset: number,
  size: number,
): TwoLegPlan {
  if (yesMidpoint <= 0 || yesMidpoint >= 1) {
    throw new Error(
      `planTwoLegs: yesMidpoint ${yesMidpoint} must be in (0, 1).`,
    );
  }
  const yesPrice = yesMidpoint + offset;
  const noPrice = 1 - yesMidpoint + offset;
  if (yesPrice >= 1 || noPrice >= 1) {
    throw new Error(
      `planTwoLegs: leg price >= 1 (yes=${yesPrice}, no=${noPrice}); ` +
        `midpoint ${yesMidpoint} too close to 0 or 1 for offset ${offset}.`,
    );
  }
  return { yesPrice, noPrice, size };
}

/**
 * Inclusive drift-band check.
 *
 * Returns `true` when `|current − entry| <= threshold`. Sign-agnostic;
 * a zero threshold passes only when `current === entry`.
 *
 * A tiny epsilon (`1e-9`) absorbs IEEE-754 rounding so on-the-tick inputs
 * like `|0.55 − 0.5| <= 0.05` pass cleanly. The epsilon is ~3 orders of
 * magnitude below the tightest Polymarket tick (0.001), so it never
 * collapses two meaningfully different prices.
 */
const DRIFT_BAND_EPSILON = 1e-9;

export function withinDriftBand(
  entry: number,
  current: number,
  threshold: number,
): boolean {
  return Math.abs(current - entry) <= threshold + DRIFT_BAND_EPSILON;
}
