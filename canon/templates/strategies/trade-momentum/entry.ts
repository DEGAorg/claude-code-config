/**
 * TRADE-02 Momentum Trading — Project Entry Point
 *
 * Scanner-only wiring for the TRADE-02 template. Uses a stubbed snapshot
 * provider, dry-run executor, and empty portfolio since no order
 * submission occurs. Operators replace the snapshot provider when
 * promoting from dry-run to a live data feed.
 */

import { DEFAULT_TRADE_MOMENTUM_CONFIG } from "./config.js";
import { createTradeMomentumRunner } from "./main.js";
import type { TradeMomentumSnapshot } from "./scan.js";
import type { ExecutorDeps, PositionDeps } from "../../runner.js";
import type { Portfolio } from "../../types/RiskInterface.js";

const dryRun = process.argv.includes("--dry-run");
const pollIntervalMs =
  Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

const strategyConfig = DEFAULT_TRADE_MOMENTUM_CONFIG;

const stubScan = {
  async fetchSnapshots(): Promise<TradeMomentumSnapshot[]> {
    return [];
  },
};

const stubExecutor: ExecutorDeps = {
  async submit(signal) {
    process.stdout.write(
      `[dry-run] would submit: ${signal.automation_id}\n`,
    );
    return { id: "dry-run", status: "simulated" };
  },
};

const emptyPortfolio: Portfolio = {
  total_value: strategyConfig.bankroll,
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

const runner = createTradeMomentumRunner(
  {
    strategy: strategyConfig,
    runner: {
      pollIntervalMs,
      dryRun,
      baseDir: ".canon/execution",
      statePath: ".canon/state.json",
    },
    maxConsecutiveLosses: 3,
  },
  {
    scan: stubScan,
    executor: stubExecutor,
    positions: stubPositions,
  },
);

process.stdout.write(
  `START TRADE-02 scanner (${dryRun ? "dry-run" : "live"}) ` +
    `poll=${String(pollIntervalMs)}ms\n`,
);

runner.start().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  process.stdout.write(`SCAN_ERROR ${msg}\n`);
  process.exitCode = 1;
});
