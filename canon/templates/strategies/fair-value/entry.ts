/**
 * IA-03 Fair Value Probability Model — Project Entry Point
 *
 * Scanner-only wiring for the IA-03 template. Ships a stubbed snapshot
 * provider, neutral fixture-driven model, dry-run executor, and empty
 * portfolio. Operators replace the snapshot provider and register real
 * `ProbabilityModel` fixtures when promoting from dry-run to a live
 * data feed.
 */

import { DEFAULT_FAIR_VALUE_CONFIG } from "./config.js";
import { createFairValueRunner } from "./main.js";
import type {
  FairValueSnapshot,
  ModelContext,
  ModelResult,
  ProbabilityModel,
} from "./scan.js";
import type { ExecutorDeps, PositionDeps } from "../../runner.js";
import type { Portfolio } from "../../types/RiskInterface.js";

const dryRun = process.argv.includes("--dry-run");
const pollIntervalMs =
  Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

const strategyConfig = DEFAULT_FAIR_VALUE_CONFIG;

const stubScan = {
  async fetchSnapshots(): Promise<FairValueSnapshot[]> {
    return [];
  },
  model: {
    computeFairValue(ctx: ModelContext): ModelResult {
      return {
        fairValue: ctx.snapshot.marketPrice,
        sources: [],
        confidence: 0,
      };
    },
  } satisfies ProbabilityModel,
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

const runner = createFairValueRunner(
  {
    strategy: strategyConfig,
    runner: {
      pollIntervalMs,
      dryRun,
      baseDir: ".canon/execution",
      statePath: ".canon/state.json",
    },
  },
  {
    scan: stubScan,
    executor: stubExecutor,
    positions: stubPositions,
  },
);

process.stdout.write(
  `START IA-03 scanner (${dryRun ? "dry-run" : "live"}) ` +
    `poll=${String(pollIntervalMs)}ms\n`,
);

runner.start().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  process.stdout.write(`SCAN_ERROR ${msg}\n`);
  process.exitCode = 1;
});
