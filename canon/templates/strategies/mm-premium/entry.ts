/**
 * MINT-04 Market Making Premium — Project Entry Point
 *
 * Scanner-only wiring for the MINT-04 template. Uses a stubbed snapshot
 * provider, dry-run executor, and empty portfolio since this template does
 * not execute `mint_set` or `postLimitOrder` calls. Operators replace the
 * snapshot provider when promoting from dry-run to a live data feed.
 */

import { DEFAULT_MM_PREMIUM_CONFIG } from "./config.js";
import { createMintPremiumRunner } from "./main.js";
import type { MintPremiumSnapshot } from "./signal.js";
import type { ExecutorDeps, PositionDeps } from "../../runner.js";
import type { Portfolio } from "../../types/RiskInterface.js";

const dryRun = process.argv.includes("--dry-run");
const pollIntervalMs =
  Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

const strategyConfig = DEFAULT_MM_PREMIUM_CONFIG;

const stubScan = {
  async fetchSnapshots(): Promise<MintPremiumSnapshot[]> {
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

const runner = createMintPremiumRunner(
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
  `START MINT-04 scanner (${dryRun ? "dry-run" : "live"}) ` +
    `poll=${String(pollIntervalMs)}ms\n`,
);

runner.start().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  process.stdout.write(`SCAN_ERROR ${msg}\n`);
  process.exitCode = 1;
});
