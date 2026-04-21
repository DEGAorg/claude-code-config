/**
 * ARB-03 NegRisk Multi-condition Buy — Project Entry Point
 *
 * Dry-run scanner wire-up. The real Polymarket client does not currently
 * expose a NegRisk-aware search helper, so this entry point injects an
 * empty search stub — flip `searchMarkets` to a live feed once the CLOB
 * SDK surfaces `neg_risk` metadata + per-condition leg token IDs.
 */

import { appendEntry } from "../../execution-log.js";
import type { ExecutionLogEntry } from "../../execution-log.js";
import type { OrderBook } from "../../client-polymarket.js";
import { fetchOrderBook as polyFetchOrderBook } from "../../client-polymarket.js";
import type {
  ExecutorDeps,
  PositionDeps,
} from "../../runner.js";
import type { Portfolio } from "../../types/RiskInterface.js";
import { DEFAULT_NEGRISK_BUY_CONFIG } from "./config.js";
import { createNegRiskBuyRunner } from "./main.js";
import type { NegRiskBuyRunnerConfig } from "./main.js";
import type { ScanDeps, ScanSearchResult } from "./scan.js";

const dryRun = process.argv.includes("--dry-run");
const pollIntervalMs =
  Number(process.env["POLL_INTERVAL_MS"]) || 30_000;

const strategyConfig = DEFAULT_NEGRISK_BUY_CONFIG;

// TODO(ARB-03): replace with a live NegRisk-aware search once the CLOB
// SDK exposes `neg_risk` + per-condition leg token IDs.
const searchMarkets = async (
  _query: string,
): Promise<ScanSearchResult[]> => {
  void _query;
  return [];
};

const fetchOrderBook = async (tokenId: string): Promise<OrderBook> =>
  polyFetchOrderBook(tokenId);

const scan: ScanDeps = { searchMarkets, fetchOrderBook };

const stubExecutor: ExecutorDeps = {
  async submit(signal) {
    process.stdout.write(
      `[dry-run] would submit ${signal.automation_id} ${signal.market.market_id} ${signal.direction}\n`,
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

const runnerConfig: NegRiskBuyRunnerConfig = {
  strategy: strategyConfig,
  runner: {
    pollIntervalMs,
    dryRun,
    baseDir: ".canon/execution",
    statePath: ".canon/state.json",
  },
  maxConsecutiveLosses: 3,
};

const runner = createNegRiskBuyRunner(runnerConfig, {
  scan,
  executor: stubExecutor,
  positions: stubPositions,
  log: (entry: ExecutionLogEntry) =>
    appendEntry(".canon/execution", entry),
});

process.stdout.write(
  `START ARB-03 scanner (${dryRun ? "dry-run" : "live"}) poll=${String(pollIntervalMs)}ms\n`,
);

runner.start().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  process.stdout.write(`SCAN_ERROR ${msg}\n`);
  process.exitCode = 1;
});
