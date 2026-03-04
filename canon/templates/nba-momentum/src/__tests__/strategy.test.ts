import { describe, it, expect } from "vitest";
import { NbaMomentumStrategy } from "../strategy.js";
import type { Game, InjuryReport, Portfolio } from "../types/game.js";

function makePortfolio(
  overrides: Partial<Portfolio> = {},
): Portfolio {
  return {
    totalValue: 10_000,
    cashBalance: 7_000,
    positions: [],
    peakValue: 10_000,
    dailyPnl: 0,
    consecutiveLosses: 0,
    ...overrides,
  };
}

function makeGame(overrides: Partial<Game> = {}): Game {
  return {
    id: "game-456",
    homeTeam: "Lakers",
    awayTeam: "Celtics",
    tipoff: new Date(Date.now() + 60 * 60 * 1000),
    polymarketPrice: 0.62,
    totalVolume: 100_000,
    isLive: false,
    isResolved: false,
    pregameSpread: -5,
    currentSpread: -1,
    ...overrides,
  };
}

function makeInjury(
  overrides: Partial<InjuryReport> = {},
): InjuryReport {
  return {
    playerId: "p1",
    playerName: "Star Player",
    team: "Lakers",
    minutesRank: 1,
    status: "out",
    reportedAt: new Date(),
    ...overrides,
  };
}

describe("NbaMomentumStrategy", () => {
  // TODO: AI fills in these test assertions based on the strategy spec.
  // The factories above provide valid defaults that meet all entry conditions.

  it("returns signal when all conditions pass", () => {
    const strategy = new NbaMomentumStrategy(makePortfolio());
    const signal = strategy.evaluate(makeGame(), makeInjury());
    // TODO: assert signal is not null, check direction, size, confidence
    expect(signal).not.toBeNull();
  });

  it("returns null when risk check fails", () => {
    const strategy = new NbaMomentumStrategy(
      makePortfolio({ consecutiveLosses: 5 }),
    );
    const signal = strategy.evaluate(makeGame(), makeInjury());
    // TODO: assert null — circuit breaker should trigger
    expect(signal).toBeNull();
  });

  it("returns null when player minutes rank too low", () => {
    const strategy = new NbaMomentumStrategy(makePortfolio());
    const signal = strategy.evaluate(
      makeGame(),
      makeInjury({ minutesRank: 10 }),
    );
    // TODO: assert null — player not important enough
    expect(signal).toBeNull();
  });

  it("returns null when line move too small", () => {
    const strategy = new NbaMomentumStrategy(makePortfolio());
    const signal = strategy.evaluate(
      makeGame({ pregameSpread: -5, currentSpread: -4.5 }),
      makeInjury(),
    );
    // TODO: assert null — spread move < 3 points
    expect(signal).toBeNull();
  });

  it("checks exit conditions on resolved game", () => {
    const strategy = new NbaMomentumStrategy(makePortfolio());
    const position = {
      marketId: "g1",
      side: "no" as const,
      entryPrice: 0.38,
      size: 300,
      enteredAt: new Date(),
    };
    const result = strategy.checkExit(
      position,
      makeGame({ isResolved: true }),
    );
    // TODO: assert "resolution"
    expect(result).toBe("resolution");
  });

  it("returns hold for active position with edge", () => {
    const strategy = new NbaMomentumStrategy(makePortfolio());
    const position = {
      marketId: "g1",
      side: "no" as const,
      entryPrice: 0.38,
      size: 300,
      enteredAt: new Date(),
    };
    const result = strategy.checkExit(position, makeGame());
    // TODO: assert "hold"
    expect(result).toBe("hold");
  });
});
