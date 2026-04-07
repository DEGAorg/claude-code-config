/**
 * FuturesScanner — high-level strategy class wrapping runner primitives.
 *
 * Provides a testable, composable interface over the scan logic so
 * tests and the dashboard can instantiate it without starting the
 * polling loop.
 */

import { extractTeamOdds, textMentionsTeam } from "./runner.js";
import type { OddsEvent, TeamOdds } from "./runner.js";
import type { PolymarketMatch } from "../client-polymarket.js";
import type { StrategyConfig } from "./config/strategy.js";
import { DEFAULT_CONFIG } from "./config/strategy.js";
import { shouldFlag } from "./service/signals.js";
import { checkRiskLimits } from "./service/risk.js";
import { DEFAULT_RISK_CONFIG } from "./config/risk.js";

export interface ScanResult {
  team: string;
  sportsbookProb: number;
  polymarketPrice: number;
  delta: number;
  direction: string;
}

/**
 * FuturesScanner wraps the core scan logic for testability.
 *
 * Usage:
 *   const scanner = new FuturesScanner();
 *   const signals = scanner.findSignals(oddsEvents, polyMarkets);
 */
export class FuturesScanner {
  private readonly config: StrategyConfig;

  constructor(config: StrategyConfig = DEFAULT_CONFIG) {
    this.config = config;
  }

  /**
   * Given raw sportsbook events and Polymarket markets, return all
   * detected mispricings above the configured threshold.
   */
  findSignals(
    events: OddsEvent[],
    polyMarkets: PolymarketMatch[],
  ): ScanResult[] {
    const teamOddsList = extractTeamOdds(events);
    const results: ScanResult[] = [];

    for (const teamOdds of teamOddsList) {
      // Enforce minimum bookmaker source requirement
      const riskOk = checkRiskLimits(
        { sources: teamOdds.sources },
        DEFAULT_RISK_CONFIG,
      );
      if (!riskOk) continue;

      // Match to a Polymarket market
      const match = polyMarkets.find((m) =>
        textMentionsTeam(m.question, teamOdds.team),
      );
      if (!match) continue;

      // Evaluate mispricing signal
      const signal = shouldFlag(
        teamOdds.impliedProb,
        match.yesPrice,
        this.config,
      );
      if (!signal) continue;

      results.push({
        team: teamOdds.team,
        sportsbookProb: teamOdds.impliedProb,
        polymarketPrice: match.yesPrice,
        delta: signal.absDelta,
        direction: signal.direction,
      });
    }

    return results;
  }
}
