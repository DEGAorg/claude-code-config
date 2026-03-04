/**
 * Dry-run NBA momentum strategy runner.
 *
 * Polls for NBA injury-driven opportunities on a fixed interval,
 * evaluates entry/exit signals, and logs every decision to JSONL.
 * Never places orders.
 *
 * Stdout protocol — each line is tagged for dashboard parsing:
 *   START <message>       Runner started
 *   NO_EDGE <message>     Scan cycle, no opportunities
 *   SIGNAL <message>      Trade signal detected (dry-run skip)
 *   SCAN_ERROR <message>  Scan cycle failed
 *   STOP <message>        Runner shutting down
 *
 * Usage: pnpm exec tsx src/runner.ts --dry-run
 */

import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import type { Portfolio } from "./types/game.js";
import { NbaMomentumStrategy } from "./strategy.js";

/** A single line in the JSONL decision log. */
interface DecisionLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
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
  cycle: number;
  action: "NO_EDGE";
  games_checked: number;
  reasoning: string;
}

/** Error entry when a scan cycle fails. */
interface ScanErrorLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
  action: "SCAN_ERROR";
  reasoning: string;
}

type LogEntry = DecisionLogEntry | HeartbeatLogEntry | ScanErrorLogEntry;

const AUTOMATION_ID = "nba-momentum-v1";
const EXECUTION_DIR = join(process.cwd(), ".canon", "execution");
const DEFAULT_POLL_INTERVAL_MS = 15_000;

let cycleCount = 0;
let signalCount = 0;
let errorCount = 0;

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

/** Tagged stdout line — parsed by the dashboard pipe wrapper. */
function out(tag: string, msg: string): void {
  process.stdout.write(`${tag} ${msg}\n`);
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
  cycleCount++;

  // TODO: Replace with real scan logic:
  // 1. fetchOdds("basketball_nba") from sportsbook client
  // 2. searchMarkets("NBA") from polymarket client
  // 3. Match games, check injury reports
  // 4. Call strategy.evaluate(game, injury) for each match
  // 5. For each signal: signalCount++, appendLog(decision), out("SIGNAL", ...)

  const gamesChecked = 0; // TODO: real count from API

  const entry: HeartbeatLogEntry = {
    ts: new Date().toISOString(),
    automation_id: AUTOMATION_ID,
    cycle: cycleCount,
    action: "NO_EDGE",
    games_checked: gamesChecked,
    reasoning: `Cycle ${cycleCount} — ${gamesChecked} games, no edges`,
  };
  appendLog(entry);
  out(
    "NO_EDGE",
    `Cycle ${cycleCount} — ${gamesChecked} games checked, no edges`,
  );
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

  out(
    "START",
    `NBA momentum runner (dry-run) poll=${pollInterval}ms`,
  );

  let running = true;

  process.on("SIGINT", () => {
    out(
      "STOP",
      `Shutting down — ${cycleCount} cycles, ${signalCount} signals, ${errorCount} errors`,
    );
    running = false;
  });

  while (running) {
    try {
      await runCycle(strategy);
    } catch (err: unknown) {
      errorCount++;
      const message = err instanceof Error ? err.message : String(err);

      const errorEntry: ScanErrorLogEntry = {
        ts: new Date().toISOString(),
        automation_id: AUTOMATION_ID,
        cycle: cycleCount,
        action: "SCAN_ERROR",
        reasoning: message,
      };
      appendLog(errorEntry);
      out("SCAN_ERROR", `Cycle ${cycleCount} — ${message}`);
    }

    if (running) {
      await sleep(pollInterval);
    }
  }

  out(
    "STOP",
    `Runner stopped — ${cycleCount} cycles, ${signalCount} signals, ${errorCount} errors`,
  );
}

main();
