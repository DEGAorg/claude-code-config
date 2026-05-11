import { describe, expect, it } from "vitest";

import { planTwoLegs, withinDriftBand } from "../mint-cycle-helpers.js";

describe("planTwoLegs", () => {
  it("places both legs at midpoint + offset at a symmetric midpoint", () => {
    const legs = planTwoLegs(0.5, 0.0075, 1_000);

    expect(legs.yesPrice).toBeCloseTo(0.5075, 6);
    expect(legs.noPrice).toBeCloseTo(0.5075, 6);
    expect(legs.size).toBe(1_000);
  });

  it("derives the NO leg from the binary complement of the YES midpoint", () => {
    const legs = planTwoLegs(0.3, 0.0075, 1_000);

    // YES midpoint 0.30 → YES leg 0.3075
    // NO midpoint  0.70 → NO  leg 0.7075
    expect(legs.yesPrice).toBeCloseTo(0.3075, 6);
    expect(legs.noPrice).toBeCloseTo(0.7075, 6);
  });

  it("passes the size argument through unchanged", () => {
    expect(planTwoLegs(0.5, 0.0075, 2_500).size).toBe(2_500);
    expect(planTwoLegs(0.5, 0.0075, 1).size).toBe(1);
  });

  it("supports a zero offset (legs sit exactly on the midpoint)", () => {
    const legs = planTwoLegs(0.4, 0, 1_000);
    expect(legs.yesPrice).toBeCloseTo(0.4, 6);
    expect(legs.noPrice).toBeCloseTo(0.6, 6);
  });

  it("throws when yesMidpoint is 0 (degenerate)", () => {
    expect(() => planTwoLegs(0, 0.0075, 1_000)).toThrow(/0,\s*1/);
  });

  it("throws when yesMidpoint is 1 (degenerate)", () => {
    expect(() => planTwoLegs(1, 0.0075, 1_000)).toThrow(/0,\s*1/);
  });

  it("throws when yesMidpoint is below 0", () => {
    expect(() => planTwoLegs(-0.1, 0.0075, 1_000)).toThrow(/0,\s*1/);
  });

  it("throws when yesMidpoint is above 1", () => {
    expect(() => planTwoLegs(1.5, 0.0075, 1_000)).toThrow(/0,\s*1/);
  });

  it("throws when the YES leg price would be >= 1", () => {
    // 0.995 + 0.0075 = 1.0025 → unfillable.
    expect(() => planTwoLegs(0.995, 0.0075, 1_000)).toThrow(/>=\s*1/);
  });

  it("throws when the NO leg price would be >= 1", () => {
    // YES midpoint 0.005 → NO midpoint 0.995 → NO leg 1.0025.
    expect(() => planTwoLegs(0.005, 0.0075, 1_000)).toThrow(/>=\s*1/);
  });

  it("throws when offset alone pushes a leg >= 1 at a symmetric midpoint", () => {
    // 0.5 + 0.6 = 1.1 on each side.
    expect(() => planTwoLegs(0.5, 0.6, 1_000)).toThrow(/>=\s*1/);
  });
});

describe("withinDriftBand", () => {
  it("returns true when current equals entry (zero drift)", () => {
    expect(withinDriftBand(0.5, 0.5, 0.05)).toBe(true);
  });

  it("returns true when drift is strictly inside the band (upward)", () => {
    expect(withinDriftBand(0.5, 0.52, 0.05)).toBe(true);
  });

  it("returns true when drift is strictly inside the band (downward)", () => {
    expect(withinDriftBand(0.5, 0.48, 0.05)).toBe(true);
  });

  it("returns true when drift exactly equals the threshold (boundary inclusive)", () => {
    expect(withinDriftBand(0.5, 0.55, 0.05)).toBe(true);
    expect(withinDriftBand(0.5, 0.45, 0.05)).toBe(true);
  });

  it("returns false when current drifts up past the threshold", () => {
    expect(withinDriftBand(0.5, 0.56, 0.05)).toBe(false);
  });

  it("returns false when current drifts down past the threshold", () => {
    expect(withinDriftBand(0.5, 0.44, 0.05)).toBe(false);
  });

  it("respects tighter custom thresholds", () => {
    expect(withinDriftBand(0.5, 0.515, 0.01)).toBe(false);
    expect(withinDriftBand(0.5, 0.505, 0.01)).toBe(true);
  });

  it("uses absolute drift (sign-agnostic)", () => {
    expect(withinDriftBand(0.3, 0.34, 0.05)).toBe(true);
    expect(withinDriftBand(0.7, 0.66, 0.05)).toBe(true);
    expect(withinDriftBand(0.3, 0.36, 0.05)).toBe(false);
    expect(withinDriftBand(0.7, 0.64, 0.05)).toBe(false);
  });

  it("treats a zero threshold as only-equal-passes", () => {
    expect(withinDriftBand(0.5, 0.5, 0)).toBe(true);
    expect(withinDriftBand(0.5, 0.5001, 0)).toBe(false);
  });
});
