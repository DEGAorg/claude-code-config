/**
 * ARB-01 Binary Arbitrage — Project Entry Point
 *
 * Wires the real Polymarket client into the arb-binary strategy via
 * scanMarkets(), which fetches order books and derives best-ask prices
 * from CLOB depth before running signal detection.
 */

import { createRunner } from "../runner.js";
import { appendEntry } from "../execution-log.js";
import { searchMarkets, fetchOrderBook } from "../client-polymarket.js";
import { scanMarkets } from "../strategies/arb-binary/scan.js";
import { detectSignals } from "../strategies/arb-binary/signal.js";
import { DEFAULT_ARB_BINARY_CONFIG } from "../strategies/arb-binary/config.js";
import { createRiskChecker } from "../strategies/arb-binary/risk.js";
import type { ExecutorDeps, PositionDeps } from "../runner.js";
import type { Portfolio } from "../types/RiskInterface.js";
import type { ExecutionLogEntry } from "../execution-log.js";

const dryRun = process.argv.includes("--dry-run");
const pollIntervalMs =
  Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

const strategyConfig = DEFAULT_ARB_BINARY_CONFIG;

const risk = createRiskChecker({
  bankroll: strategyConfig.bankroll,
  kellyFraction: strategyConfig.kellyFraction,
  maxExposure: strategyConfig.maxExposure,
  maxConsecutiveLosses: 3,
});

const strategy = async () => {
  const marketData = await scanMarkets(strategyConfig, {
    searchMarkets,
    fetchOrderBook,
  });
  return detectSignals(marketData, strategyConfig);
};

const stubExecutor: ExecutorDeps = {
  async submit(signal) {
    console.info("[dry-run] would submit:", signal.automation_id);
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

const runner = createRunner(
  { pollIntervalMs, dryRun, baseDir: ".canon/execution", statePath: ".canon/state.json" },
  {
    strategy,
    risk,
    executor: stubExecutor,
    positions: stubPositions,
    log: (entry: ExecutionLogEntry) =>
      appendEntry(".canon/execution", entry),
  },
);

process.stdout.write(
  `START ARB-01 scanner (${dryRun ? "dry-run" : "live"}) poll=${String(pollIntervalMs)}ms\n`,
);

runner.start().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  process.stdout.write(`SCAN_ERROR ${msg}\n`);
  process.exitCode = 1;
});
