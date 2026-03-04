/**
 * Dry-run NBA momentum strategy runner.
 *
 * Polls for NBA injury-driven opportunities on a fixed interval,
 * evaluates entry/exit signals, and logs every decision to JSONL.
 * Never places orders.
 *
 * Usage: node --env-file=.env dist/runner.js --dry-run
 */

import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import type { TradeSignal } from "./types/TradeSignal.js";
import type { Portfolio } from "./types/game.js";
import { NbaMomentumStrategy } from "./strategy.js";

/** A single line in the JSONL decision log. */
interface DecisionLogEntry {
  ts: string;
  automation_id: string;
  signal: {
    marketId: string;
    direction: string;
    side: string;
    size: number;
    confidence: number;
  };
  risk_passed: boolean;
  action: "DRY_RUN_SKIP";
  reasoning: string;
}

/** Heartbeat when no edges are detected. */
interface HeartbeatLogEntry {
  ts: string;
  automation_id: string;
  action: "NO_EDGE";
  reasoning: string;
}

/** Error entry when a scan cycle fails. */
interface ScanErrorLogEntry {
  ts: string;
  automation_id: string;
  action: "SCAN_ERROR";
  reasoning: string;
}

type LogEntry = DecisionLogEntry | HeartbeatLogEntry | ScanErrorLogEntry;

const AUTOMATION_ID = "nba-momentum-v1";
const EXECUTION_DIR = join(process.cwd(), ".canon", "execution");
const DEFAULT_POLL_INTERVAL_MS = 15_000;

function ensureExecutionDir(): void {
  if (!existsSync(EXECUTION_DIR)) {
    mkdirSync(EXECUTION_DIR, { recursive: true });
  }
}

function logFilePath(): string {
  const date = new Date().toISOString().slice(0, 10);
  return join(EXECUTION_DIR, `${date}.jsonl`);
}

function appendLog(entry: LogEntry): void {
  ensureExecutionDir();
  appendFileSync(logFilePath(), JSON.stringify(entry) + "\n");
}

function dryRunPortfolio(): Portfolio {
  return {
    totalValue: 10_000,
    cashBalance: 7_000,
    positions: [],
    peakValue: 10_000,
    dailyPnl: 0,
    consecutiveLosses: 0,
  };
}

function parsePollInterval(): number {
  const envVal = process.env["POLL_INTERVAL_MS"];
  if (envVal) {
    const parsed = Number(envVal);
    if (Number.isFinite(parsed) && parsed > 0) return parsed;
  }
  return DEFAULT_POLL_INTERVAL_MS;
}

function isDryRun(): boolean {
  return process.argv.includes("--dry-run");
}

/**
 * Run a single poll cycle.
 *
 * TODO: Wire to real API clients after strategy logic is built.
 * For now this is a stub that logs a heartbeat.
 */
async function runCycle(strategy: NbaMomentumStrategy): Promise<void> {
  // TODO: Replace with real scan logic:
  // 1. fetchOdds("basketball_nba") from sportsbook client
  // 2. searchMarkets("NBA") from polymarket client
  // 3. Match games, check injury reports
  // 4. Call strategy.evaluate(game, injury) for each match
  // 5. Log signals

  const entry: HeartbeatLogEntry = {
    ts: new Date().toISOString(),
    automation_id: AUTOMATION_ID,
    action: "NO_EDGE",
    reasoning: "Scan cycle complete — no edges detected (stub)",
  };
  appendLog(entry);
  process.stdout.write(`[${entry.ts}] ${entry.reasoning}\n`);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function main(): Promise<void> {
  if (!isDryRun()) {
    process.stderr.write(
      "error: --dry-run flag is required. " +
        "Live trading is not implemented.\n",
    );
    process.exitCode = 1;
    return;
  }

  const pollInterval = parsePollInterval();
  const portfolio = dryRunPortfolio();
  const strategy = new NbaMomentumStrategy(portfolio);

  process.stdout.write(
    `NBA momentum runner (dry-run) starting\n` +
      `  pollInterval: ${pollInterval}ms\n` +
      `  logDir: ${EXECUTION_DIR}\n\n`,
  );

  let running = true;

  process.on("SIGINT", () => {
    process.stdout.write("\nSIGINT received, shutting down...\n");
    running = false;
  });

  while (running) {
    try {
      await runCycle(strategy);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      process.stderr.write(`Scan cycle error: ${message}\n`);

      const errorEntry: ScanErrorLogEntry = {
        ts: new Date().toISOString(),
        automation_id: AUTOMATION_ID,
        action: "SCAN_ERROR",
        reasoning: `Scan cycle error: ${message}`,
      };
      appendLog(errorEntry);
    }

    if (running) {
      await sleep(pollInterval);
    }
  }

  process.stdout.write("Runner stopped.\n");
}

main();
