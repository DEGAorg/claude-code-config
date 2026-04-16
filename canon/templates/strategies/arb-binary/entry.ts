/**
 * ARB-01 Binary Arbitrage — Project Entry Point
 *
 * This file is copied to src/main.ts by canon-start when the user
 * selects the arb-binary strategy. It wires the real Polymarket
 * client into the strategy's scan layer.
 */

import { createArbBinaryRunner } from "../strategies/arb-binary/main.js";
import { DEFAULT_ARB_BINARY_CONFIG } from "../strategies/arb-binary/config.js";
import {
  searchMarkets as polySearchMarkets,
  fetchOrderBook as polyFetchOrderBook,
} from "../client-polymarket.js";
import type { ArbBinaryRunnerConfig } from "../strategies/arb-binary/main.js";
import type { ScanSearchResult } from "../strategies/arb-binary/scan.js";
import type { ExecutorDeps, PositionDeps } from "../runner.js";
import type { Portfolio } from "../types/RiskInterface.js";

const dryRun = process.argv.includes("--dry-run");
const pollIntervalMs =
  Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

const config: ArbBinaryRunnerConfig = {
  strategy: DEFAULT_ARB_BINARY_CONFIG,
  runner: {
    pollIntervalMs,
    dryRun,
    baseDir: ".canon/execution",
    statePath: ".canon/state.json",
  },
  maxConsecutiveLosses: 3,
};

const stubExecutor: ExecutorDeps = {
  async submit(signal) {
    console.info("[dry-run] would submit:", signal.automation_id);
    return { id: "dry-run", status: "simulated" };
  },
};

const emptyPortfolio: Portfolio = {
  total_value: config.strategy.bankroll,
  positions: [],
  daily_pnl: 0,
};

const stubPositions: PositionDeps = {
  async reconcile() {
    return emptyPortfolio;
  },
  getPortfolio() {
    return emptyPortfolio;
  },
};

const runner = createArbBinaryRunner(config, {
  scan: {
    async searchMarkets(query: string): Promise<ScanSearchResult[]> {
      const markets = await polySearchMarkets(query);
      return markets.map((m) => ({
        conditionId: m.conditionId,
        question: m.question,
        yesTokenId: m.yesTokenId,
        noTokenId: m.noTokenId,
      }));
    },
    fetchOrderBook: polyFetchOrderBook,
  },
  executor: stubExecutor,
  positions: stubPositions,
});

process.stdout.write(
  `START ARB-01 scanner (${dryRun ? "dry-run" : "live"}) poll=${String(pollIntervalMs)}ms\n`,
);

runner.start().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  process.stdout.write(`SCAN_ERROR ${msg}\n`);
  process.exitCode = 1;
});
