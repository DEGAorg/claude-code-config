/**
 * NBA momentum strategy runner.
 *
 * Polls The Odds API for NBA game lines and Polymarket for NBA
 * prediction markets. Matches games by team name, compares implied
 * probabilities, and flags mispricings. Logs every decision to JSONL.
 *
 * In dry-run mode: scans and logs but never places orders.
 *
 * Stdout protocol — each line is tagged for dashboard parsing:
 *   START <message>       Runner started
 *   SCAN <message>        Cycle started, fetching data
 *   NO_EDGE <message>     Scan cycle complete, no opportunities
 *   SIGNAL <message>      Mispricing detected (dry-run skip)
 *   SCAN_ERROR <message>  Scan cycle failed
 *   STOP <message>        Runner shutting down
 *
 * Usage: pnpm exec tsx src/runner.ts --dry-run
 */

import { appendFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { fetchOdds, type SportEvent } from "./clients/sportsbook.js";
import {
  searchMarkets,
  type PolymarketMatch,
} from "./clients/polymarket.js";

// ── Log entry types ─────────────────────────────────────────────────────────

interface SignalLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
  action: "SIGNAL";
  homeTeam: string;
  awayTeam: string;
  sportsbookProb: number;
  polymarketPrice: number;
  delta: number;
  reasoning: string;
}

interface HeartbeatLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
  action: "NO_EDGE";
  games: number;
  markets: number;
  matched: number;
  reasoning: string;
}

interface ScanErrorLogEntry {
  ts: string;
  automation_id: string;
  cycle: number;
  action: "SCAN_ERROR";
  reasoning: string;
}

type LogEntry = SignalLogEntry | HeartbeatLogEntry | ScanErrorLogEntry;

// ── Constants ───────────────────────────────────────────────────────────────

const AUTOMATION_ID = "nba-momentum-v1";
const EXECUTION_DIR = join(process.cwd(), ".canon", "execution");
const DEFAULT_POLL_INTERVAL_MS = 30_000;

/** Minimum price delta to flag as a signal (5%). */
const MISPRICING_THRESHOLD = 0.05;

// ── Counters ────────────────────────────────────────────────────────────────

let cycleCount = 0;
let signalCount = 0;
let errorCount = 0;
let totalGames = 0;
let totalMarkets = 0;

// ── Helpers ─────────────────────────────────────────────────────────────────

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

function out(tag: string, msg: string): void {
  process.stdout.write(`${tag} ${msg}\n`);
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

// ── Team matching ───────────────────────────────────────────────────────────

/** Normalize team name for fuzzy matching. */
function normalize(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, "")
    .trim();
}

/**
 * NBA team name aliases — maps common short names to the full
 * team name fragments. Extend as needed.
 */
const NBA_ALIASES: Record<string, string[]> = {
  "76ers": ["philadelphia", "sixers", "76ers"],
  blazers: ["portland", "trail blazers", "blazers"],
  cavs: ["cleveland", "cavaliers", "cavs"],
  mavs: ["dallas", "mavericks", "mavs"],
  wolves: ["minnesota", "timberwolves", "wolves"],
};

/** Check if a Polymarket question mentions a team. */
function questionMentionsTeam(
  question: string,
  teamName: string,
): boolean {
  const q = normalize(question);
  const t = normalize(teamName);

  // Direct substring match (covers most cases)
  if (q.includes(t)) return true;

  // Try last word of team name (e.g. "Lakers" from "Los Angeles Lakers")
  const parts = t.split(" ");
  const last = parts[parts.length - 1];
  if (last && last.length > 3 && q.includes(last)) return true;

  // Check aliases
  for (const [, aliases] of Object.entries(NBA_ALIASES)) {
    const teamMatches = aliases.some((a) => t.includes(a));
    const questionMatches = aliases.some((a) => q.includes(a));
    if (teamMatches && questionMatches) return true;
  }

  return false;
}

interface MatchedGame {
  event: SportEvent;
  market: PolymarketMatch;
  homeImpliedProb: number;
}

/**
 * Match sportsbook events to Polymarket markets by team names.
 *
 * For each event, find a Polymarket market whose question mentions
 * both the home and away team.
 */
function matchGames(
  events: SportEvent[],
  markets: PolymarketMatch[],
): MatchedGame[] {
  const matched: MatchedGame[] = [];

  for (const event of events) {
    // Extract average home-win implied probability from bookmakers
    const homeProbs: number[] = [];
    for (const bm of event.bookmakers) {
      const h2h = bm.markets.find((m) => m.key === "h2h");
      if (!h2h) continue;
      const homeOutcome = h2h.outcomes.find(
        (o) => normalize(o.name) === normalize(event.homeTeam),
      );
      if (homeOutcome && homeOutcome.price > 1) {
        homeProbs.push(1 / homeOutcome.price);
      }
    }
    if (homeProbs.length === 0) continue;

    const avgHomeProb =
      homeProbs.reduce((a, b) => a + b, 0) / homeProbs.length;

    // Find matching Polymarket market
    for (const market of markets) {
      const mentionsHome = questionMentionsTeam(
        market.question,
        event.homeTeam,
      );
      const mentionsAway = questionMentionsTeam(
        market.question,
        event.awayTeam,
      );

      if (mentionsHome && mentionsAway) {
        matched.push({
          event,
          market,
          homeImpliedProb: avgHomeProb,
        });
        break; // one match per event
      }
    }
  }

  return matched;
}

// ── Scan cycle ──────────────────────────────────────────────────────────────

async function runCycle(): Promise<void> {
  cycleCount++;
  const ts = new Date().toISOString();

  out("SCAN", `Cycle ${cycleCount} — fetching NBA data...`);

  // 1. Fetch sportsbook odds
  const events = await fetchOdds("basketball_nba");
  totalGames = events.length;

  // 2. Fetch Polymarket NBA markets
  const markets = await searchMarkets("NBA");
  totalMarkets = markets.length;

  // 3. Match events to markets
  const matched = matchGames(events, markets);

  // 4. Check each match for mispricing
  let cycleSignals = 0;

  for (const { event, market, homeImpliedProb } of matched) {
    // Polymarket yesPrice = probability of the "yes" outcome.
    // For NBA game markets, "yes" typically = home team wins.
    const delta = homeImpliedProb - market.yesPrice;
    const absDelta = Math.abs(delta);

    if (absDelta >= MISPRICING_THRESHOLD) {
      cycleSignals++;
      signalCount++;

      const direction = delta > 0 ? "YES underpriced" : "NO underpriced";
      const reasoning =
        `${event.homeTeam} vs ${event.awayTeam}: ` +
        `sportsbook ${(homeImpliedProb * 100).toFixed(1)}% vs ` +
        `Polymarket ${(market.yesPrice * 100).toFixed(1)}% ` +
        `(${direction}, delta ${(absDelta * 100).toFixed(1)}%)`;

      const entry: SignalLogEntry = {
        ts,
        automation_id: AUTOMATION_ID,
        cycle: cycleCount,
        action: "SIGNAL",
        homeTeam: event.homeTeam,
        awayTeam: event.awayTeam,
        sportsbookProb: homeImpliedProb,
        polymarketPrice: market.yesPrice,
        delta: absDelta,
        reasoning,
      };
      appendLog(entry);
      out("SIGNAL", reasoning);
    }
  }

  // 5. Heartbeat if no signals
  if (cycleSignals === 0) {
    const reasoning =
      `Cycle ${cycleCount} — ${events.length} games, ` +
      `${markets.length} markets, ${matched.length} matched, no edges`;

    const entry: HeartbeatLogEntry = {
      ts,
      automation_id: AUTOMATION_ID,
      cycle: cycleCount,
      action: "NO_EDGE",
      games: events.length,
      markets: markets.length,
      matched: matched.length,
      reasoning,
    };
    appendLog(entry);
    out("NO_EDGE", reasoning);
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

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

  out("START", `NBA momentum runner (dry-run) poll=${pollInterval}ms`);

  let running = true;

  process.on("SIGINT", () => {
    out(
      "STOP",
      `Shutting down — ${cycleCount} cycles, ` +
        `${signalCount} signals, ${errorCount} errors`,
    );
    running = false;
  });

  while (running) {
    try {
      await runCycle();
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
    `Runner stopped — ${cycleCount} cycles, ` +
      `${signalCount} signals, ${errorCount} errors`,
  );
}

main();
